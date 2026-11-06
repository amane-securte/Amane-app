import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'data.dart';
import 'geo.dart';
import 'i18n.dart';
import 'theme.dart';
import 'tracking.dart';
import 'widgets.dart';

/// Déplacement d'un client (« Je suis en route ») : position suivie pendant le
/// trajet seulement, à sa demande, visible par la salle de contrôle.
class TripDoc {
  TripDoc(this.id, Map<String, dynamic> m)
      : uid = m['uid'] is String ? m['uid'] as String : '',
        name = m['name'] is String ? m['name'] as String : '',
        phone = m['phone'] is String ? m['phone'] as String : '',
        to = m['to'] is String ? m['to'] as String : '',
        startAt = m['startAt'] is Timestamp ? (m['startAt'] as Timestamp).toDate() : DateTime.now(),
        lastAt = m['lastAt'] is Timestamp ? (m['lastAt'] as Timestamp).toDate() : null,
        lastFix = Fix.read(m, 'last') ?? Fix.read(m, 'start');
  final String id, uid, name, phone, to;
  final DateTime startAt;
  final DateTime? lastAt;
  final Fix? lastFix;
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.route, color: navy, size: 36),
        title: Text(t('trip_start')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(t('trip_hint'), style: const TextStyle(color: muted)),
          const SizedBox(height: 8),
          TextField(
            controller: to,
            autofocus: true,
            decoration: InputDecoration(labelText: t('trip_to'), hintText: t('trip_to_hint')),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('trip_go'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final r = await getFix(seconds: 15);
    try {
      await db.collection('trips').add({
        'uid': widget.me.id,
        'name': widget.me.name,
        'phone': widget.me.phone,
        'to': to.text.trim(),
        'active': true,
        'startAt': Timestamp.now(),
        if (r.fix != null) ...r.fix!.write('start'),
        if (r.fix != null) ...r.fix!.write('last'),
        if (r.fix != null) 'lastAt': Timestamp.now(),
      });
      if (mounted && r.error != null) showGpsError(context, t, r.error!);
    } catch (e) {
      if (mounted) snack(context, t('err_generic', {'e': '$e'}), color: danger);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _end(TripDoc trip) async {
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
              Text(t('trip_tracked'), style: const TextStyle(color: muted, fontSize: 12)),
              const SizedBox(height: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: okGreen, minimumSize: const Size.fromHeight(44)),
                onPressed: _busy ? null : () => _end(trip),
                icon: const Icon(Icons.check_circle),
                label: Text(t('trip_arrived')),
              ),
            ]),
          ),
        );
      },
    );
  }
}

/// Liste des trajets en cours, pour la salle de contrôle.
class ActiveTrips extends StatelessWidget {
  const ActiveTrips({super.key, required this.t});
  final T t;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QueryMap>(
      stream: activeTrips().snapshots(),
      builder: (context, snap) {
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
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.route, color: okGreen),
                title: whoWhere(tr.name, tr.to, client: true),
                subtitle: Text([
                  t('trip_since', {'t': hm(tr.startAt)}),
                  if (tr.lastAt != null) t('trip_last', {'t': hm(tr.lastAt!)}),
                  if (kmFromNouakchott(tr.lastFix) case final km? when km > inlandKm)
                    t('inland_pill', {'km': km.round().toString()}),
                ].join(' · ')),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (tr.lastFix != null)
                    IconButton(
                      icon: const Icon(Icons.map, color: navy),
                      onPressed: () => openUrl(tr.lastFix!.mapUrl),
                    ),
                  if (tr.phone.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.phone, color: okGreen),
                      onPressed: () => openUrl('tel:${tr.phone}'),
                    ),
                ]),
              ),
            ),
        ]);
      },
    );
  }
}
