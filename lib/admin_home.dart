import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data.dart';
import 'geo.dart';
import 'guard_home.dart';
import 'i18n.dart';
import 'theme.dart';
import 'widgets.dart';

/// Écran de l'administrateur : suivi en direct, agents, sites.
class AdminHome extends StatefulWidget {
  const AdminHome({super.key, required this.prefs, required this.me});
  final Prefs prefs;
  final UserDoc me;

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  late final Stream<QueryMap> _alerts = db
      .collection('alerts')
      .where('status', whereIn: ['open', 'taken']).snapshots();
  late final Stream<QueryMap> _punches = db
      .collection('punches')
      .where('inAt',
          isGreaterThan: Timestamp.fromDate(
              DateTime.now().subtract(const Duration(hours: 24))))
      .snapshots();
  late final Stream<QueryMap> _users = db.collection('users').snapshots();
  late final Stream<QueryMap> _sites = db.collection('sites').snapshots();

  final _seenAlerts = <String>{};
  bool _alertsLoaded = false;

  T get t => T(widget.prefs.lang);

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: amaneAppBar(
          context,
          widget.prefs,
          bottom: TabBar(
            labelColor: const Color(0xFFD1A850),
            unselectedLabelColor: const Color(0xFFB8C2CC),
            indicatorColor: const Color(0xFFD1A850),
            tabs: [
              Tab(text: t('tab_live')),
              Tab(text: t('tab_guards')),
              Tab(text: t('tab_sites')),
            ],
          ),
        ),
        body: StreamBuilder<QueryMap>(
          stream: _sites,
          builder: (context, sitesSnap) {
            final sites = (sitesSnap.data?.docs ?? const [])
                .map((d) => Site(d.id, d.data()))
                .toList()
              ..sort((a, b) => a.name.compareTo(b.name));
            return TabBarView(
              children: [
                _liveTab(),
                _guardsTab(sites),
                _sitesTab(sites),
              ],
            );
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- Suivi

  Widget _liveTab() {
    return StreamBuilder<QueryMap>(
      stream: _alerts,
      builder: (context, aSnap) {
        final alerts = (aSnap.data?.docs ?? const [])
            .map((d) => AlertDoc(d.id, d.data()))
            .toList()
          ..sort((a, b) => b.at.compareTo(a.at));
        _notifyNewAlerts(aSnap.data, alerts);
        return StreamBuilder<QueryMap>(
          stream: _punches,
          builder: (context, pSnap) {
            final ps = (pSnap.data?.docs ?? const [])
                .map((d) => PunchDoc(d.id, d.data()))
                .toList()
              ..sort((a, b) => b.inAt.compareTo(a.inAt));
            final onDuty = ps.where((p) => p.open).toList();
            final recent = ps.where((p) => !p.open).toList();
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _h(t('alerts'), color: alerts.isEmpty ? null : danger),
                if (alerts.isEmpty)
                  _empty(t('no_alerts'))
                else
                  ...alerts.map(_alertCard),
                const SizedBox(height: 20),
                _h(t('on_duty_now', {'n': '${onDuty.length}'})),
                if (onDuty.isEmpty)
                  _empty(t('none_on_duty'))
                else
                  ...onDuty.map((p) => PunchTile(t: t, p: p)),
                const SizedBox(height: 20),
                _h(t('recent')),
                if (recent.isEmpty)
                  _empty(t('none_recent'))
                else
                  ...recent.map((p) => PunchTile(t: t, p: p)),
              ],
            );
          },
        );
      },
    );
  }

  /// Vibre quand une nouvelle alerte arrive pendant que l'écran est ouvert.
  void _notifyNewAlerts(QueryMap? snap, List<AlertDoc> alerts) {
    if (snap == null) return;
    final fresh = alerts
        .where((a) => a.status == 'open' && !_seenAlerts.contains(a.id))
        .toList();
    _seenAlerts.addAll(alerts.map((a) => a.id));
    if (_alertsLoaded && fresh.isNotEmpty) {
      HapticFeedback.heavyImpact();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final a = fresh.first;
        snack(context, 'SOS · ${t('ty_${a.type}')} · ${a.name}', color: danger);
      });
    }
    _alertsLoaded = true;
  }

  Widget _alertCard(AlertDoc a) {
    final open = a.status == 'open';
    final f = a.fix;
    return Card(
      color: open ? const Color(0xFFFBE9E7) : paper,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: open ? danger : const Color(0xFFDBD1BA)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: danger),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('${t('ty_${a.type}')} · ${a.siteName}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 16)),
                ),
                pill(t(open ? 'st_open' : 'st_taken'), open ? danger : warn),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(child: Text(a.name)),
                ltrText('${dm(a.at)} ${hm(a.at)}',
                    style: const TextStyle(color: muted)),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (f != null)
                  OutlinedButton.icon(
                    onPressed: () => openUrl(f.mapUrl),
                    icon: const Icon(Icons.map, size: 18),
                    label: Text('${t('map')} (±${f.acc.round()} m)'),
                  ),
                if (a.phone.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () => openUrl('tel:${a.phone}'),
                    icon: const Icon(Icons.phone, size: 18),
                    label: Text(t('call')),
                  ),
                if (open)
                  FilledButton(
                    onPressed: () => db
                        .collection('alerts')
                        .doc(a.id)
                        .update({'status': 'taken', 'takenAt': Timestamp.now()}),
                    child: Text(t('take')),
                  ),
                TextButton(
                  onPressed: () => db
                      .collection('alerts')
                      .doc(a.id)
                      .update({'status': 'closed', 'closedAt': Timestamp.now()}),
                  child: Text(t('close')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- Agents

  Widget _guardsTab(List<Site> sites) {
    return StreamBuilder<QueryMap>(
      stream: _users,
      builder: (context, snap) {
        final users = (snap.data?.docs ?? const [])
            .map((d) => UserDoc(d.id, d.data()))
            .where((u) => u.id != widget.me.id)
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
        final pending = users.where((u) => u.role == 'pending').toList();
        final others = users.where((u) => u.role != 'pending').toList();
        final siteName = {for (final s in sites) s.id: s.name};
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (pending.isNotEmpty) ...[
              _h(t('pending_req', {'n': '${pending.length}'}), color: warn),
              ...pending.map((u) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(u.name),
                      subtitle: ltrText(u.phone),
                      trailing: FilledButton(
                        onPressed: () => _assign(u, sites, approve: true),
                        child: Text(t('approve')),
                      ),
                    ),
                  )),
              const SizedBox(height: 16),
            ],
            _h(t('tab_guards')),
            if (others.isEmpty) _empty(t('no_guards')),
            ...others.map((u) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(u.name),
                    subtitle: Text(
                        [
                          if (u.phone.isNotEmpty) u.phone,
                          siteName[u.siteId] ?? '—',
                        ].join(' · '),
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.start),
                    leading: _roleIcon(u.role),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) => _userAction(u, v, sites),
                      itemBuilder: (_) => [
                        if (u.phone.isNotEmpty)
                          PopupMenuItem(value: 'call', child: Text(t('call'))),
                        PopupMenuItem(value: 'site', child: Text(t('set_site'))),
                        if (u.role == 'guard')
                          PopupMenuItem(
                              value: 'admin', child: Text(t('make_admin'))),
                        if (u.role == 'admin')
                          PopupMenuItem(
                              value: 'guard', child: Text(t('make_guard'))),
                        if (u.role != 'disabled')
                          PopupMenuItem(
                              value: 'disable', child: Text(t('disable')))
                        else
                          PopupMenuItem(
                              value: 'guard', child: Text(t('enable'))),
                      ],
                    ),
                  ),
                )),
          ],
        );
      },
    );
  }

  Widget _roleIcon(String role) => Tooltip(
        message: t('role_$role'),
        child: Icon(
          switch (role) {
            'admin' => Icons.admin_panel_settings,
            'disabled' => Icons.block,
            _ => Icons.badge,
          },
          color: switch (role) {
            'admin' => gold,
            'disabled' => danger,
            _ => navy,
          },
        ),
      );

  Future<void> _userAction(UserDoc u, String v, List<Site> sites) async {
    final ref = db.collection('users').doc(u.id);
    switch (v) {
      case 'call':
        await openUrl('tel:${u.phone}');
      case 'site':
        await _assign(u, sites);
      case 'admin':
        await ref.update({'role': 'admin'});
      case 'guard':
        await ref.update({'role': 'guard'});
      case 'disable':
        await ref.update({'role': 'disabled'});
    }
  }

  /// Choisit le site d'un agent (et le valide si c'est une demande).
  Future<void> _assign(UserDoc u, List<Site> sites,
      {bool approve = false}) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('${t('choose_site')} · ${u.name}'),
        children: [
          if (sites.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(t('no_sites')),
            ),
          for (final s in sites)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, s.id),
              child: Text(s.name, style: const TextStyle(fontSize: 16)),
            ),
        ],
      ),
    );
    if (picked == null) return;
    await db.collection('users').doc(u.id).update({
      'siteId': picked,
      if (approve) 'role': 'guard',
    });
  }

  // ---------------------------------------------------------------- Sites

  Widget _sitesTab(List<Site> sites) {
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            if (sites.isEmpty) _empty(t('no_sites')),
            ...sites.map((s) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(Icons.location_on,
                        color: s.fix == null ? muted : okGreen),
                    title: Text(s.name),
                    subtitle: Text(s.fix == null
                        ? t('no_coords')
                        : '${s.fix!.lat.toStringAsFixed(5)}, ${s.fix!.lng.toStringAsFixed(5)} · ${s.radius} m'),
                    onTap: () => _editSite(s),
                    trailing: s.fix == null
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.map),
                            onPressed: () => openUrl(s.fix!.mapUrl),
                          ),
                  ),
                )),
          ],
        ),
        PositionedDirectional(
          end: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: () => _editSite(null),
            icon: const Icon(Icons.add_location_alt),
            label: Text(t('add_site')),
          ),
        ),
      ],
    );
  }

  Future<void> _editSite(Site? s) async {
    final name = TextEditingController(text: s?.name ?? '');
    final coords = TextEditingController(
        text: s?.fix == null ? '' : '${s!.fix!.lat}, ${s.fix!.lng}');
    final radius = TextEditingController(text: '${s?.radius ?? 200}');
    String? error;
    var locating = false;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(s == null ? t('add_site') : t('edit_site')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: name,
                    decoration: InputDecoration(labelText: t('site_name'))),
                const SizedBox(height: 10),
                TextField(
                  controller: coords,
                  decoration: InputDecoration(
                      labelText: t('coords'), errorText: error),
                  textDirection: TextDirection.ltr,
                ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    onPressed: locating
                        ? null
                        : () async {
                            setD(() => locating = true);
                            final r = await getFix();
                            setD(() {
                              locating = false;
                              final f = r.fix;
                              if (f != null) {
                                coords.text =
                                    '${f.lat.toStringAsFixed(6)}, ${f.lng.toStringAsFixed(6)}';
                                error = null;
                              } else if (r.error != null) {
                                error = gpsErrorText(t, r.error!);
                              }
                            });
                          },
                    child: Text(locating ? t('locating') : t('coords_here')),
                  ),
                ),
                TextField(
                  controller: radius,
                  decoration: InputDecoration(labelText: t('radius')),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
          actions: [
            if (s != null)
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'delete'),
                child: Text(t('delete'), style: const TextStyle(color: danger)),
              ),
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(t('cancel'))),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isEmpty) return;
                if (coords.text.trim().isNotEmpty &&
                    Fix.parse(coords.text) == null) {
                  setD(() => error = t('coords_bad'));
                  return;
                }
                Navigator.pop(ctx, 'save');
              },
              child: Text(t('save')),
            ),
          ],
        ),
      ),
    );

    if (result == 'save') {
      final f = Fix.parse(coords.text);
      final r = int.tryParse(radius.text.trim()) ?? 200;
      final data = <String, dynamic>{
        'name': name.text.trim(),
        'radius': r < 20 ? 20 : r,
        'Lat': f?.lat,
        'Lng': f?.lng,
      };
      if (s == null) {
        await db.collection('sites').add(data);
      } else {
        await db.collection('sites').doc(s.id).update(data);
      }
      if (mounted) snack(context, t('saved'), color: okGreen);
    } else if (result == 'delete' && s != null && mounted) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(t('confirm_delete')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(t('cancel'))),
            FilledButton(
                style: FilledButton.styleFrom(backgroundColor: danger),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(t('delete'))),
          ],
        ),
      );
      if (ok == true) await db.collection('sites').doc(s.id).delete();
    }
  }

  // ---------------------------------------------------------------- Divers

  Widget _h(String text, {Color? color}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w600, color: color)),
      );

  Widget _empty(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(text, style: const TextStyle(color: muted)),
      );
}
