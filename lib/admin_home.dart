import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data.dart';
import 'geo.dart';
import 'accounting.dart';
import 'emergency.dart';
import 'guard_home.dart';
import 'logbook.dart';
import 'map_tab.dart';
import 'people.dart';
import 'planning.dart';
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
  late final Stream<QueryMap> _logs = db
      .collection('logs')
      .where('at',
          isGreaterThan: Timestamp.fromDate(
              DateTime.now().subtract(const Duration(hours: 24))))
      .snapshots();

  final _seenAlerts = <String>{};
  bool _alertsLoaded = false;

  T get t => T(widget.prefs.lang);

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 7,
      child: Scaffold(
        appBar: amaneAppBar(
          context,
          widget.prefs,
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: const Color(0xFFD1A850),
            unselectedLabelColor: const Color(0xFFB8C2CC),
            indicatorColor: const Color(0xFFD1A850),
            tabs: [
              Tab(text: t('tab_live')),
              Tab(text: t('tab_mine')),
              Tab(text: t('tab_map')),
              Tab(text: t('tab_plan')),
              Tab(text: t('tab_guards')),
              Tab(text: t('tab_sites')),
              Tab(text: t('tab_acc')),
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
            return StreamBuilder<QueryMap>(
              stream: _users,
              builder: (context, uSnap) {
                final users = (uSnap.data?.docs ?? const [])
                    .map((d) => UserDoc(d.id, d.data()))
                    .where((u) => u.id != widget.me.id)
                    .toList()
                  ..sort((a, b) => a.name.compareTo(b.name));
                return TabBarView(
                  // Pas de glissement entre onglets : la carte en a besoin.
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _liveTab(),
                    GuardHome(prefs: widget.prefs, me: widget.me, embedded: true),
                    MapTab(t: t, sites: sites),
                    PlanningTab(t: t, guards: users, sites: sites),
                    _guardsTab(sites, users),
                    _sitesTab(sites),
                    AccountingTab(t: t, users: users, sites: sites),
                  ],
                );
              },
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
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: emergencyButton(context, t),
                ),
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
                _h(t('logs_24h')),
                StreamBuilder<QueryMap>(
                  stream: _logs,
                  builder: (context, lSnap) {
                    final logs = (lSnap.data?.docs ?? const [])
                        .map((d) => LogDoc(d.id, d.data()))
                        .toList()
                      ..sort((a, b) => b.at.compareTo(a.at));
                    if (logs.isEmpty) return _empty(t('no_logs'));
                    return Column(
                        children:
                            logs.map((l) => LogTile(t: t, l: l)).toList());
                  },
                ),
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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _alarm(fresh.first);
      });
    }
    _alertsLoaded = true;
  }

  bool _alarmOpen = false;

  /// Alarme plein écran : son et vibration répétés jusqu'à ce que
  /// l'administrateur réagisse.
  Future<void> _alarm(AlertDoc a) async {
    if (_alarmOpen) return;
    _alarmOpen = true;
    var ringing = true;
    final siren = AudioPlayer();
    try {
      await siren.setAudioContext(AudioContext(
        android: const AudioContextAndroid(
          usageType: AndroidUsageType.alarm,
          contentType: AndroidContentType.sonification,
          audioFocus: AndroidAudioFocus.gainTransient,
        ),
      ));
      await siren.setReleaseMode(ReleaseMode.loop);
      await siren.play(AssetSource('siren.wav'), volume: 1.0);
    } catch (_) {}
    () async {
      while (ringing && mounted) {
        HapticFeedback.heavyImpact();
        await Future.delayed(const Duration(milliseconds: 900));
      }
    }();
    final f = a.fix;
    final kind = t(a.fromClient ? 'need_${a.type}' : 'ty_${a.type}');
    final go = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFBE9E7),
        icon: const Icon(Icons.warning_rounded, color: danger, size: 56),
        title: Text('SOS · $kind',
            textAlign: TextAlign.center,
            style: const TextStyle(color: danger, fontWeight: FontWeight.w800)),
        content: Text(
          [
            a.name,
            if (a.siteName.isNotEmpty) a.siteName,
            if (a.fromClient) t('from_client'),
            '${dm(a.at)} ${hm(a.at)}',
          ].join('\n'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          if (f != null)
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, 'map'),
              icon: const Icon(Icons.map),
              label: Text(t('map')),
            ),
          if (a.phone.isNotEmpty)
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: okGreen),
              onPressed: () => Navigator.pop(ctx, 'call'),
              icon: const Icon(Icons.phone),
              label: Text(t('call')),
            ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: danger),
            onPressed: () => Navigator.pop(ctx, 'take'),
            child: Text(t('take')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t('alarm_silence')),
          ),
        ],
      ),
    );
    ringing = false;
    _alarmOpen = false;
    siren.stop().catchError((_) {});
    siren.dispose();
    if (go == 'take' || go == 'call' || go == 'map') {
      await db
          .collection('alerts')
          .doc(a.id)
          .update({'status': 'taken', 'takenAt': Timestamp.now()});
    }
    if (go == 'map' && f != null) await openUrl(f.mapUrl);
    if (go == 'call') await openUrl('tel:${a.phone}');
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
                if (a.fromClient) ...[
                  pill(t('from_client'), navy),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text('${t(a.fromClient ? 'need_${a.type}' : 'ty_${a.type}')} · ${a.siteName}',
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
            if (a.note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('« ${a.note} »', style: const TextStyle(fontStyle: FontStyle.italic)),
              ),
            if (a.action.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: pill(t('act_${a.action}'), okGreen),
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
                // Réponse : patrouille AMANE ou services publics.
                PopupMenuButton<String>(
                  tooltip: t('respond'),
                  onSelected: (act) async {
                    await db.collection('alerts').doc(a.id).update({
                      'action': act,
                      'status': 'taken',
                      'actionAt': Timestamp.now(),
                    });
                    if (act == 'police') await openUrl('tel:$policeNumber');
                    if (act == 'civil' || act == 'ambulance') await openUrl('tel:$fireNumber');
                  },
                  itemBuilder: (_) => [
                    for (final act in ['patrol', 'police', 'civil', 'ambulance'])
                      PopupMenuItem(value: act, child: Text(t('act_${act}_menu'))),
                  ],
                  child: Chip(
                    avatar: const Icon(Icons.campaign, size: 18, color: navy),
                    label: Text(t('respond')),
                  ),
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

  Widget _guardsTab(List<Site> sites, List<UserDoc> users) {
    return Builder(
      builder: (context) {
        final pending = users.where((u) => u.role == 'pending').toList();
        final staff = users.where((u) => u.role == 'guard' || u.role == 'admin').toList();
        final clients = users.where((u) => u.role == 'client').toList();
        final off = users.where((u) => u.role == 'disabled').toList();
        final siteName = {for (final s in sites) s.id: s.name};
        Widget tile(UserDoc u) => Card(
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
                    if (u.phone.isNotEmpty)
                      PopupMenuItem(value: 'invite', child: Text(t('invite_again'))),
                    PopupMenuItem(value: 'site', child: Text(t('set_site'))),
                    if (u.role == 'guard')
                      PopupMenuItem(value: 'admin', child: Text(t('make_admin'))),
                    if (u.role == 'admin' || u.role == 'client')
                      PopupMenuItem(value: 'guard', child: Text(t('make_guard'))),
                    if (u.role == 'guard')
                      PopupMenuItem(value: 'client', child: Text(t('make_client'))),
                    if (u.role != 'disabled')
                      PopupMenuItem(value: 'disable', child: Text(t('disable')))
                    else
                      PopupMenuItem(value: 'guard', child: Text(t('enable'))),
                  ],
                ),
              ),
            );
        return Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.share, color: navy),
                  label: Text(t('share_app')),
                  onPressed: () => shareInvite(context, t),
                ),
                const SizedBox(height: 16),
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
                _h(t('sec_guards', {'n': '${staff.length}'})),
                if (staff.isEmpty) _empty(t('no_guards')),
                ...staff.map(tile),
                const SizedBox(height: 16),
                _h(t('sec_clients', {'n': '${clients.length}'})),
                if (clients.isEmpty) _empty(t('no_clients')),
                ...clients.map(tile),
                if (off.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _h(t('sec_disabled', {'n': '${off.length}'}), color: danger),
                  ...off.map(tile),
                ],
              ],
            ),
            PositionedDirectional(
              end: 16,
              bottom: 16,
              child: FloatingActionButton.extended(
                heroTag: 'addPerson',
                onPressed: () => addPerson(context, t, sites),
                icon: const Icon(Icons.person_add),
                label: Text(t('add_short')),
              ),
            ),
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
            'client' => Icons.storefront,
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
      case 'client':
        await ref.update({'role': 'client'});
      case 'invite':
        if (mounted) await shareInvite(context, t, phone: u.phone);
      case 'disable':
        await ref.update({'role': 'disabled'});
    }
  }

  /// Choisit le site d'un agent (et le valide si c'est une demande).
  Future<void> _assign(UserDoc u, List<Site> sites,
      {bool approve = false}) async {
    var role = u.role;
    if (approve) {
      final r = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text('${t('approve_as')} · ${u.name}'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'guard'),
              child: ListTile(leading: const Icon(Icons.badge), title: Text(t('role_guard'))),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'client'),
              child: ListTile(leading: const Icon(Icons.storefront), title: Text(t('role_client'))),
            ),
          ],
        ),
      );
      if (r == null || !mounted) return;
      role = r;
    }
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
    final sName = sites.where((s) => s.id == picked).firstOrNull?.name ?? '';
    await db.collection('users').doc(u.id).update({
      'siteId': picked,
      'siteName': sName,
      if (approve) 'role': role,
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
                    title: Text(s.client.isEmpty ? s.name : '${s.name} · ${s.client}'),
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
    final client = TextEditingController(text: s?.client ?? '');
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
                    controller: client,
                    decoration: InputDecoration(labelText: t('client'))),
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
        'client': client.text.trim(),
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
