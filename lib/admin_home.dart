import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data.dart';
import 'geo.dart';
import 'accounting.dart';
import 'control_room.dart';
import 'emergency.dart';
import 'guard_home.dart';
import 'logbook.dart';
import 'map_tab.dart';
import 'messages.dart';
import 'people.dart';
import 'planning.dart';
import 'services.dart';
import 'i18n.dart';
import 'instructions.dart';
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

  final _placed = <String>{};
  StreamSubscription<QueryMap>? _placeSub;
  StreamSubscription<AlertDoc>? _alarmSub;

  @override
  void dispose() {
    _placeSub?.cancel();
    _alarmSub?.cancel();
    ControlRoom.instance.detach();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Écoute des SOS (sirène), y compris en arrière-plan si le mode
    // « salle de contrôle » est activé.
    final cr = ControlRoom.instance;
    cr.attach(title: t('cr_notif_title'), text: t('cr_notif_text'));
    _alarmSub = cr.newAlerts.listen((a) {
      if (mounted) _alarm(a);
    });
    // Reporte sur le site la position envoyée par le téléphone du client.
    _placeSub = db.collection('users').snapshots().listen((q) async {
      for (final d in q.docs) {
        final m = d.data();
        final sid = m['siteId'];
        if (m['role'] != 'client' || sid is! String || m['homeLat'] is! num) continue;
        if (!_placed.add(d.id)) continue;
        try {
          final site = await db.collection('sites').doc(sid).get();
          final sm = site.data();
          if (sm == null || sm['Lat'] is num || sm['autoFrom'] != d.id) continue;
          await db.collection('sites').doc(sid).update({
            'Lat': m['homeLat'],
            'Lng': m['homeLng'],
            'autoFrom': FieldValue.delete(),
          });
        } catch (_) {}
      }
    }, onError: (_) {});
  }

  T get t => T(widget.prefs.lang);

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 8,
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
              Tab(text: t('tab_msg')),
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
                final everyone = (uSnap.data?.docs ?? const [])
                    .map((d) => UserDoc(d.id, d.data()))
                    .toList()
                  ..sort((a, b) => a.name.compareTo(b.name));
                final users = everyone.where((u) => u.id != widget.me.id).toList();
                final me = everyone.where((u) => u.id == widget.me.id).firstOrNull ?? widget.me;
                return TabBarView(
                  // Pas de glissement entre onglets : la carte en a besoin.
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _liveTab(),
                    GuardHome(prefs: widget.prefs, me: widget.me, embedded: true),
                    MapTab(t: t, sites: sites),
                    PlanningTab(t: t, guards: users, sites: sites),
                    _guardsTab(sites, users, me),
                    _sitesTab(sites),
                    AccountingTab(t: t, users: everyone, sites: sites),
                    AdminMessagesTab(t: t),
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
                ValueListenableBuilder<bool>(
                  valueListenable: ControlRoom.instance.enabled,
                  builder: (context, on, _) => Card(
                    color: on ? const Color(0xFFE8F5E9) : null,
                    child: SwitchListTile(
                      secondary: Icon(Icons.notifications_active,
                          color: on ? okGreen : muted),
                      title: Text(t('cr_title'),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(t(on ? 'cr_on' : 'cr_off')),
                      value: on,
                      onChanged: (v) async {
                        final ok = await ControlRoom.instance.setEnabled(v,
                            title: t('cr_notif_title'), text: t('cr_notif_text'));
                        if (!ok && context.mounted) {
                          snack(context, t('cr_need_gps'), color: danger);
                        }
                      },
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.volume_up, color: danger),
                      label: Text(t('cr_test')),
                      onPressed: () async {
                        await ControlRoom.instance.ring();
                        if (context.mounted) {
                          snack(context, t('cr_test_hint'),
                              action: SnackBarAction(
                                  label: t('alarm_silence'),
                                  onPressed: ControlRoom.instance.silence));
                        }
                      },
                    ),
                    emergencyButton(context, t),
                  ],
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

  bool _alarmOpen = false;

  /// Alarme plein écran : son et vibration répétés jusqu'à ce que
  /// l'administrateur réagisse.
  Future<void> _alarm(AlertDoc a) async {
    if (_alarmOpen) return;
    _alarmOpen = true;
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
            if (isInland(a.fix))
              t('inland_pill', {'km': kmFromNouakchott(a.fix)!.round().toString()}),
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
    _alarmOpen = false;
    ControlRoom.instance.silence();
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
                if (isInland(a.fix))
                  pill(t('inland_pill', {'km': kmFromNouakchott(a.fix)!.round().toString()}),
                      const Color(0xFF2E5E3A)),
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
                    for (final act in ['patrol', 'police', 'gendarmerie', 'civil', 'ambulance'])
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

  Widget _guardsTab(List<Site> sites, List<UserDoc> users, UserDoc me) {
    return Builder(
      builder: (context) {
        final pending = users.where((u) => u.role == 'pending').toList();
        final staff = users.where((u) => u.role == 'guard' || u.role == 'admin').toList()
          ..sort((a, b) {
            final c = jobs.indexOf(b.job).compareTo(jobs.indexOf(a.job));
            return c != 0 ? c : a.name.compareTo(b.name);
          });
        final clients = users.where((u) => u.role == 'client').toList();
        final off = users.where((u) => u.role == 'disabled').toList();
        final siteName = {for (final s in sites) s.id: s.name};
        Widget tile(UserDoc u) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Row(children: [
                  Flexible(child: Text(u.name, overflow: TextOverflow.ellipsis)),
                  if (u.role == 'guard' || u.role == 'client') ...[
                    const SizedBox(width: 4),
                    Tooltip(
                      message: t(u.consentAt == null ? 'consent_none' : 'consent_ok'),
                      child: Icon(u.consentAt == null ? Icons.pending_outlined : Icons.verified,
                          size: 16, color: u.consentAt == null ? warn : okGreen),
                    ),
                  ],
                ]),
                subtitle: Text(
                  [
                    if (u.role != 'client') t('job_${u.job}'),
                    if (u.mission.isNotEmpty) u.mission,
                    if (u.phone.isNotEmpty) u.phone,
                    if (u.siteId != null) siteName[u.siteId] ?? '—',
                  ].join(' · '),
                ),
                leading: u.role == 'guard' || u.role == 'admin'
                    ? Icon(jobIcon(u.job), color: u.role == 'admin' ? gold : navy)
                    : _roleIcon(u.role),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) => _userAction(u, v, sites),
                  itemBuilder: (_) => [
                    if (u.phone.isNotEmpty)
                      PopupMenuItem(value: 'call', child: Text(t('call'))),
                    if (u.phone.isNotEmpty)
                      PopupMenuItem(value: 'invite', child: Text(t('invite_again'))),
                    if (u.role != 'client')
                      PopupMenuItem(value: 'job', child: Text(t('edit_staff'))),
                    PopupMenuItem(value: 'info', child: Text(t('info_menu'))),
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
                Card(
                  color: const Color(0xFFFFF8E1),
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: Icon(jobIcon(me.job), color: gold),
                    title: Text('${me.name} · ${t('me_label')}'),
                    subtitle: Text([t('job_${me.job}'), if (me.mission.isNotEmpty) me.mission].join(' · ')),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => editStaff(context, t, me),
                    ),
                  ),
                ),
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
      case 'job':
        if (mounted) await editStaff(context, t, u);
      case 'info':
        if (mounted) await editInfo(context, t, u, sites);
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
                    leading: Icon(s.type.isEmpty ? Icons.location_on : siteTypeIcon(s.type),
                        color: s.fix == null ? muted : okGreen),
                    title: Text(s.client.isEmpty ? s.name : '${s.name} · ${s.client}'),
                    subtitle: Text([
                      if (s.type.isNotEmpty) t('st_${s.type}'),
                      if (s.services.isNotEmpty) s.services.map((x) => t('sv_$x')).join('، '),
                      s.fix == null
                          ? t('no_coords')
                          : '${s.fix!.lat.toStringAsFixed(5)}, ${s.fix!.lng.toStringAsFixed(5)} · ${s.radius} m',
                    ].join('\n')),
                    isThreeLine: s.services.isNotEmpty,
                    onTap: () => _editSite(s),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: t('ins_title'),
                        icon: const Icon(Icons.assignment, color: navy),
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => SiteInstructionsPage(t: t, site: s))),
                      ),
                      if (s.fix != null)
                        IconButton(
                          icon: const Icon(Icons.map),
                          onPressed: () => openUrl(s.fix!.mapUrl),
                        ),
                    ]),
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
    var type = s?.type ?? '';
    final svc = {...?s?.services};

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
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(t('site_type'), style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 4),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final ty in siteTypes)
                    ChoiceChip(
                      avatar: Icon(siteTypeIcon(ty), size: 16),
                      label: Text(t('st_$ty')),
                      selected: type == ty,
                      onSelected: (_) => setD(() => type = ty),
                    ),
                ]),
                if (type == 'bank' || type == 'agency') ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    key: ValueKey('org-$type'),
                    initialValue: (type == 'bank' ? mauritanianBanks : financialAgencies).contains(client.text)
                        ? client.text
                        : null,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: t(type == 'bank' ? 'pick_bank' : 'pick_agency')),
                    items: [
                      for (final b in (type == 'bank' ? mauritanianBanks : financialAgencies))
                        DropdownMenuItem(value: b, child: Text(b, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setD(() {
                      if (v == null) return;
                      client.text = v;
                      if (name.text.trim().isEmpty) {
                        final short = RegExp(r'\(([^)]+)\)').firstMatch(v)?.group(1) ?? v.split(' – ').first;
                        name.text = '$short – ';
                      }
                    }),
                  ),
                  Text(t('pick_bank_hint'), style: const TextStyle(color: muted, fontSize: 12)),
                ],
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(t('site_services'), style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 4),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final sv in services)
                    FilterChip(
                      avatar: Icon(serviceIcon(sv), size: 16),
                      label: Text(t('sv_$sv')),
                      selected: svc.contains(sv),
                      onSelected: (on) => setD(() => on ? svc.add(sv) : svc.remove(sv)),
                    ),
                ]),
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
        'type': type,
        'services': [for (final sv in services) if (svc.contains(sv)) sv],
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
