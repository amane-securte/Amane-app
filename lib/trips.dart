import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'data.dart';
import 'geo.dart';
import 'silent.dart';
import 'i18n.dart';
import 'theme.dart';
import 'tracking.dart';
import 'widgets.dart';

/// Déplacement d'un client (« Je suis en route ») : position suivie pendant le
/// trajet seulement, à sa demande, visible par la salle de contrôle.
/// Pour les zones isolées (orpaillage, brousse) : heure d'arrivée prévue,
/// pointage « Je vais bien » périodique et alerte automatique en cas de silence.
class TripDoc {
  TripDoc(this.id, Map<String, dynamic> m)
      : uid = _s(m['uid']),
        name = _s(m['name']),
        phone = _s(m['phone']),
        to = _s(m['to']),
        contactName = _s(m['contactName']),
        contactPhone = _s(m['contactPhone']),
        checkEvery = m['checkEvery'] is num ? (m['checkEvery'] as num).toInt() : 0,
        startAt = _d(m['startAt']) ?? DateTime.now(),
        eta = _d(m['eta']),
        lastAt = _d(m['lastAt']),
        lastOk = _d(m['lastOk']),
        overdueAt = _d(m['overdueAt']),
        lastFix = Fix.read(m, 'last') ?? Fix.read(m, 'start');
  final String id, uid, name, phone, to, contactName, contactPhone;
  /// Heures entre deux « Je vais bien » (0 : pas de pointage périodique).
  final int checkEvery;
  final DateTime startAt;
  final DateTime? eta, lastAt, lastOk, overdueAt;
  final Fix? lastFix;

  static String _s(Object? v) => v is String ? v : '';
  static DateTime? _d(Object? v) => v is Timestamp ? v.toDate() : null;

  /// Marge avant l'alerte automatique.
  static const grace = Duration(minutes: 20);

  /// Pourquoi ce trajet est en retard (null : tout va bien).
  String? overdueReason(DateTime now) {
    if (eta != null && now.isAfter(eta!.add(grace))) return 'eta';
    if (checkEvery > 0 && now.isAfter((lastOk ?? startAt).add(Duration(hours: checkEvery)).add(grace))) {
      return 'checkin';
    }
    return null;
  }

  DateTime? get nextCheck => checkEvery > 0 ? (lastOk ?? startAt).add(Duration(hours: checkEvery)) : null;
}

Query<Map<String, dynamic>> activeTrips() => db.collection('trips').where('active', isEqualTo: true);

/// Carte « Je suis en route » de l'écran client.
class TripCard extends StatefulWidget {
  const TripCard({super.key, required this.t, required this.me});
  final T t;
  final UserDoc me;
  @override
  State<TripCard> createState() => _TripCardState();
}

class _TripCardState extends State<TripCard> {
  T get t => widget.t;
  late final Stream<QueryMap> _mine =
      db.collection('trips').where('uid', isEqualTo: widget.me.id).where('active', isEqualTo: true).snapshots();
  var _busy = false;

  void _track(TripDoc? trip) {
    final tr = ShiftTracker.instance;
    if (trip != null) {
      tr.start(trip.id,
          title: t('trip_track_title'), text: t('trip_track_text'), mobile: true, collection: 'trips');
    } else if (tr.running && tr.collection == 'trips') {
      tr.stop();
    }
  }

  Future<void> _start() async {
    final to = TextEditingController();
    final cName = TextEditingController();
    final cPhone = TextEditingController();
    TimeOfDay? eta;
    var etaTomorrow = false;
    var every = 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          icon: const Icon(Icons.route, color: navy, size: 36),
          title: Text(t('trip_start')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(t('trip_hint'), style: const TextStyle(color: muted)),
              const SizedBox(height: 8),
              TextField(
                controller: to,
                decoration: InputDecoration(labelText: t('trip_to'), hintText: t('trip_to_hint')),
              ),
              const SizedBox(height: 10),
              // Heure d'arrivée prévue : passé ce délai, alerte automatique.
              OutlinedButton.icon(
                icon: const Icon(Icons.schedule),
                label: Text(eta == null
                    ? t('trip_eta_pick')
                    : t('trip_eta_set', {'t': eta!.format(ctx), 'd': etaTomorrow ? t('tomorrow') : t('today')})),
                onPressed: () async {
                  final v = await showTimePicker(context: ctx, initialTime: TimeOfDay.now());
                  if (v == null) return;
                  final now = TimeOfDay.now();
                  setD(() {
                    eta = v;
                    etaTomorrow = v.hour * 60 + v.minute <= now.hour * 60 + now.minute;
                  });
                },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: every,
                decoration: InputDecoration(labelText: t('trip_check')),
                items: [
                  for (final h in const [0, 3, 6, 12, 24])
                    DropdownMenuItem(value: h, child: Text(h == 0 ? t('trip_check_none') : t('trip_check_h', {'h': '$h'}))),
                ],
                onChanged: (v) => setD(() => every = v ?? 0),
              ),
              const SizedBox(height: 8),
              Text(t('trip_contact'), style: const TextStyle(fontWeight: FontWeight.w600)),
              TextField(controller: cName, decoration: InputDecoration(labelText: t('name'))),
              TextField(
                controller: cPhone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: t('phone')),
              ),
              const SizedBox(height: 8),
              Text(t('trip_auto_hint'), style: const TextStyle(color: muted, fontSize: 12)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('trip_go'))),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    DateTime? etaAt;
    if (eta != null) {
      final n = DateTime.now();
      etaAt = DateTime(n.year, n.month, n.day, eta!.hour, eta!.minute).add(Duration(days: etaTomorrow ? 1 : 0));
    }
    final r = await getFix(seconds: 15);
    try {
      final now = Timestamp.now();
      await db.collection('trips').add({
        'uid': widget.me.id,
        'name': widget.me.name,
        'phone': widget.me.phone,
        'to': to.text.trim(),
        'active': true,
        'startAt': now,
        if (etaAt != null) 'eta': Timestamp.fromDate(etaAt),
        'checkEvery': every,
        if (cName.text.trim().isNotEmpty) 'contactName': cName.text.trim(),
        if (cPhone.text.trim().isNotEmpty) 'contactPhone': cPhone.text.trim(),
        if (r.fix != null) ...r.fix!.write('start'),
        if (r.fix != null) ...r.fix!.write('last'),
        if (r.fix != null) 'lastAt': now,
      });
      if (mounted && r.error != null) showGpsError(context, t, r.error!);
    } catch (e) {
      if (mounted) snack(context, t('err_generic', {'e': '$e'}), color: danger);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _ok(TripDoc trip) async {
    if (!await SafetyCodes.confirm(context, t, widget.me, note: t('od_duress_ok', {'d': trip.to}))) return;
    if (!mounted) return;
    setState(() => _busy = true);
    final r = await getFix(seconds: 10);
    try {
      await db.collection('trips').doc(trip.id).update({
        'lastOk': Timestamp.now(),
        if (r.fix != null) ...r.fix!.write('last'),
        if (r.fix != null) 'lastAt': Timestamp.now(),
      });
      if (mounted) snack(context, t('trip_ok_sent'), color: okGreen);
    } catch (e) {
      if (mounted) snack(context, t('err_generic', {'e': '$e'}), color: danger);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _end(TripDoc trip) async {
    if (!await SafetyCodes.confirm(context, t, widget.me, note: t('od_duress_end', {'d': trip.to}))) return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await db.collection('trips').doc(trip.id).update({'active': false, 'endAt': Timestamp.now()});
      if (mounted) snack(context, t('trip_ended'), color: okGreen);
    } catch (e) {
      if (mounted) snack(context, t('err_generic', {'e': '$e'}), color: danger);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QueryMap>(
      stream: _mine,
      builder: (context, snap) {
        final docs = snap.data?.docs ?? const [];
        final trip = docs.isEmpty ? null : TripDoc(docs.first.id, docs.first.data());
        if (snap.hasData) WidgetsBinding.instance.addPostFrameCallback((_) => _track(trip));
        if (trip == null) {
          return Card(
            child: ListTile(
              leading: const Icon(Icons.route, color: navy, size: 30),
              title: Text(t('trip_start'), style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(t('trip_hint')),
              trailing: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.chevron_left),
              onTap: _busy ? null : _start,
            ),
          );
        }
        final next = trip.nextCheck;
        return Card(
          color: const Color(0xFFE8F1EA),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.route, color: okGreen),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(t('trip_on', {'d': trip.to.isEmpty ? '—' : trip.to}),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ]),
              const SizedBox(height: 4),
              Text(t('trip_since', {'t': hm(trip.startAt)}), style: const TextStyle(color: muted)),
              if (trip.eta != null)
                Text(t('trip_eta_line', {'t': '${dm(trip.eta!)} ${hm(trip.eta!)}'}), style: const TextStyle(color: muted)),
              if (next != null)
                Text(t('trip_next_check', {'t': '${dm(next)} ${hm(next)}'}),
                    style: TextStyle(color: DateTime.now().isAfter(next) ? danger : muted, fontWeight: FontWeight.w600)),
              Text(t('trip_tracked'), style: const TextStyle(color: muted, fontSize: 12)),
              const SizedBox(height: 8),
              if (trip.checkEvery > 0) ...[
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                  onPressed: _busy ? null : () => _ok(trip),
                  icon: const Icon(Icons.favorite, color: okGreen),
                  label: Text(t('trip_im_ok')),
                ),
                const SizedBox(height: 6),
              ],
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: okGreen, minimumSize: const Size.fromHeight(44)),
                onPressed: _busy ? null : () => _end(trip),
                icon: const Icon(Icons.check_circle),
                label: Text(t('trip_arrived')),
              ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  onPressed: () => SafetyCodes.setup(context, t),
                  icon: const Icon(Icons.key, size: 18),
                  label: Text(t('codes_title')),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }
}

/// Surveillance par la salle de contrôle : un trajet dont l'heure d'arrivée ou
/// le pointage « Je vais bien » est dépassé déclenche une alerte SOS
/// automatique (même si le téléphone du voyageur n'a plus de réseau).
class TripWatchdog {
  TripWatchdog(this.t);
  final T t;
  StreamSubscription<QueryMap>? _sub;
  Timer? _timer;
  var _trips = <TripDoc>[];

  void start() {
    _sub = activeTrips().snapshots().listen((q) {
      _trips = q.docs.map((d) => TripDoc(d.id, d.data())).toList();
      _check();
    }, onError: (_) {});
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _check());
  }

  void stop() {
    _sub?.cancel();
    _timer?.cancel();
  }

  Future<void> _check() async {
    final now = DateTime.now();
    for (final tr in _trips) {
      if (tr.overdueAt != null) continue;
      final why = tr.overdueReason(now);
      if (why == null) continue;
      final ref = db.collection('trips').doc(tr.id);
      try {
        // Une seule alerte, même si plusieurs téléphones de la salle surveillent.
        await db.runTransaction((x) async {
          final cur = await x.get(ref);
          final m = cur.data();
          if (m == null || m['active'] != true || m['overdueAt'] != null) return;
          x.update(ref, {'overdueAt': Timestamp.now()});
          final f = tr.lastFix;
          x.set(db.collection('alerts').doc(), {
            'uid': tr.uid,
            'name': tr.name,
            'phone': tr.phone,
            'siteName': '🧭 ${tr.to}',
            'type': 'overdue',
            'fromClient': true,
            'status': 'open',
            'source': 'auto',
            'tripId': tr.id,
            'note': [
              t(why == 'eta' ? 'od_eta' : 'od_checkin'),
              if (tr.lastAt != null) t('od_last', {'t': '${dm(tr.lastAt!)} ${hm(tr.lastAt!)}'}),
              if (tr.contactPhone.isNotEmpty) t('od_contact', {'n': tr.contactName, 'p': tr.contactPhone}),
            ].join(' · '),
            'at': Timestamp.now(),
            if (f != null) ...f.write(''),
            if (f == null) 'gpsErr': 'unknown',
          });
        });
      } catch (_) {}
    }
  }
}

/// Liste des trajets en cours, pour la salle de contrôle.
class ActiveTrips extends StatelessWidget {
  const ActiveTrips({super.key, required this.t});
  final T t;

  Future<void> _route(TripDoc tr) async {
    // Parcours enregistré (points gardés hors réseau puis envoyés) : itinéraire sur la carte.
    try {
      final q = await db.collection('trips').doc(tr.id).collection('points').orderBy('at').get();
      final pts = q.docs.map((d) => Fix.read(d.data(), '')).whereType<Fix>().toList();
      if (pts.isEmpty) {
        if (tr.lastFix != null) await openUrl(tr.lastFix!.mapUrl);
        return;
      }
      // Google Maps accepte une dizaine d'étapes : on échantillonne le parcours.
      final step = (pts.length / 9).ceil().clamp(1, 1 << 30);
      final keep = [for (var i = 0; i < pts.length; i += step) pts[i], pts.last];
      final path = keep.map((p) => '${p.lat},${p.lng}').join('/');
      await openUrl('https://www.google.com/maps/dir/$path');
    } catch (_) {
      if (tr.lastFix != null) await openUrl(tr.lastFix!.mapUrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QueryMap>(
      stream: activeTrips().snapshots(),
      builder: (context, snap) {
        final now = DateTime.now();
        final trips = (snap.data?.docs ?? const []).map((d) => TripDoc(d.id, d.data())).toList()
          ..sort((a, b) => b.startAt.compareTo(a.startAt));
        if (trips.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 6),
            child: Text(t('trips_title', {'n': '${trips.length}'}),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: navy)),
          ),
          for (final tr in trips)
            Card(
              color: tr.overdueReason(now) != null ? const Color(0xFFFBE9E7) : null,
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.route, color: tr.overdueReason(now) != null ? danger : okGreen),
                    const SizedBox(width: 8),
                    Expanded(child: whoWhere(tr.name, tr.to, client: true)),
                    IconButton(
                      tooltip: t('trip_route'),
                      icon: const Icon(Icons.map, color: navy),
                      onPressed: () => _route(tr),
                    ),
                    if (tr.phone.isNotEmpty)
                      IconButton(
                        tooltip: t('call'),
                        icon: const Icon(Icons.phone, color: okGreen),
                        onPressed: () => openUrl('tel:${tr.phone}'),
                      ),
                  ]),
                  Text(
                    [
                      t('trip_since', {'t': hm(tr.startAt)}),
                      if (tr.eta != null) t('trip_eta_short', {'t': hm(tr.eta!)}),
                      if (tr.lastAt != null) t('trip_last', {'t': hm(tr.lastAt!)}),
                      if (tr.nextCheck != null) t('trip_next_short', {'t': hm(tr.nextCheck!)}),
                      if (kmFromNouakchott(tr.lastFix) case final km? when km > inlandKm)
                        t('inland_pill', {'km': km.round().toString()}),
                    ].join(' · '),
                    style: const TextStyle(color: muted, fontSize: 13),
                  ),
                  if (tr.overdueReason(now) != null)
                    Text(t(tr.overdueReason(now) == 'eta' ? 'od_eta' : 'od_checkin'),
                        style: const TextStyle(color: danger, fontWeight: FontWeight.w700)),
                  if (tr.contactPhone.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => openUrl('tel:${tr.contactPhone}'),
                      icon: const Icon(Icons.contact_phone, size: 18),
                      label: Text(t('od_contact', {'n': tr.contactName, 'p': tr.contactPhone})),
                    ),
                ]),
              ),
            ),
        ]);
      },
    );
  }
}
