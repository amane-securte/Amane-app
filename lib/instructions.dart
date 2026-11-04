import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'data.dart';
import 'i18n.dart';
import 'theme.dart';
import 'widgets.dart';

/// Consigne d'un site : permanente ou temporaire (jusqu'à une date).
/// Proposée par le client (« pending »), validée / modifiée par AMANE
/// (« approved ») : elle s'affiche alors au client et aux agents du site.
class Instruction {
  Instruction(this.id, Map<String, dynamic> m)
      : siteId = _s(m['siteId']),
        siteName = _s(m['siteName']),
        kind = _s(m['kind']) == 'temporary' ? 'temporary' : 'permanent',
        text = _s(m['text']),
        status = _s(m['status']).isEmpty ? 'pending' : _s(m['status']),
        from = _s(m['from']),
        byName = _s(m['byName']),
        adminNote = _s(m['adminNote']),
        until = m['until'] is Timestamp ? (m['until'] as Timestamp).toDate() : null,
        at = m['at'] is Timestamp ? (m['at'] as Timestamp).toDate() : DateTime.now();
  final String id, siteId, siteName, kind, text, status, from, byName, adminNote;
  final DateTime? until;
  final DateTime at;

  static String _s(Object? v) => v is String ? v : '';

  /// Temporaire dont la date de fin est passée.
  bool get expired =>
      kind == 'temporary' && until != null && until!.isBefore(DateTime.now().subtract(const Duration(days: 1)));
  bool get active => status == 'approved' && !expired;
}

String _d(DateTime d) => '${two(d.day)}/${two(d.month)}/${d.year}';

Widget _instrTile(T t, Instruction i, {Widget? trailing, bool showSite = false}) {
  final (label, color) = switch (i.status) {
    'approved' => i.expired ? (t('ins_expired'), muted) : (t('ins_approved'), okGreen),
    'rejected' => (t('ins_rejected'), danger),
    _ => (t('ins_pending'), warn),
  };
  return Card(
    margin: const EdgeInsets.only(bottom: 6),
    child: ListTile(
      leading: Icon(i.kind == 'temporary' ? Icons.timer : Icons.push_pin,
          color: i.kind == 'temporary' ? warn : navy),
      title: Text(i.text),
      subtitle: Text([
        t(i.kind == 'temporary' ? 'ins_temporary' : 'ins_permanent'),
        if (i.kind == 'temporary' && i.until != null) t('ins_until', {'d': _d(i.until!)}),
        if (showSite && i.siteName.isNotEmpty) i.siteName,
        if (i.from == 'client' && i.byName.isNotEmpty) t('ins_by', {'n': i.byName}),
        if (i.adminNote.isNotEmpty) '${t('ins_note')} ${i.adminNote}',
      ].join(' · ')),
      isThreeLine: true,
      trailing: trailing ?? pill(label, color),
    ),
  );
}

/// Saisie / modification d'une consigne. Renvoie les champs ou null.
Future<Map<String, dynamic>?> _editDialog(BuildContext context, T t,
    {Instruction? cur, bool admin = false}) async {
  var kind = cur?.kind ?? 'permanent';
  DateTime? until = cur?.until;
  final text = TextEditingController(text: cur?.text ?? '');
  final note = TextEditingController(text: cur?.adminNote ?? '');
  String? error;
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text(t(cur == null ? 'ins_new' : 'ins_edit')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                      value: 'permanent',
                      icon: const Icon(Icons.push_pin),
                      label: Text(t('ins_permanent'))),
                  ButtonSegment(
                      value: 'temporary',
                      icon: const Icon(Icons.timer),
                      label: Text(t('ins_temporary'))),
                ],
                selected: {kind},
                onSelectionChanged: (s) => setS(() => kind = s.first),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: text,
                minLines: 3,
                maxLines: 6,
                decoration: InputDecoration(labelText: t('ins_text'), hintText: t('ins_hint')),
              ),
              if (kind == 'temporary') ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.event),
                  label: Text(until == null ? t('ins_pick_until') : t('ins_until', {'d': _d(until!)})),
                  onPressed: () async {
                    final now = DateTime.now();
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: until ?? now.add(const Duration(days: 7)),
                      firstDate: DateTime(now.year, now.month, now.day),
                      lastDate: DateTime(now.year + 2),
                    );
                    if (d != null) setS(() => until = d);
                  },
                ),
              ],
              if (admin) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: note,
                  decoration: InputDecoration(labelText: t('ins_admin_note')),
                ),
              ],
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: const TextStyle(color: danger)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('cancel'))),
          FilledButton(
            onPressed: () {
              if (text.text.trim().isEmpty) {
                setS(() => error = t('ins_err_text'));
                return;
              }
              if (kind == 'temporary' && until == null) {
                setS(() => error = t('ins_err_until'));
                return;
              }
              Navigator.pop(ctx, {
                'kind': kind,
                'text': text.text.trim(),
                'until': kind == 'temporary' && until != null ? Timestamp.fromDate(until!) : null,
                if (admin) 'adminNote': note.text.trim(),
              });
            },
            child: Text(t(admin ? 'save' : 'send')),
          ),
        ],
      ),
    ),
  );
}

// ------------------------------------------------------------------ Client

/// Consignes du site, vues par le client, avec proposition de nouvelles.
class ClientInstructions extends StatelessWidget {
  const ClientInstructions({super.key, required this.t, required this.me});
  final T t;
  final UserDoc me;

  @override
  Widget build(BuildContext context) {
    final sid = me.siteId;
    if (sid == null) return const SizedBox.shrink();
    return StreamBuilder<QueryMap>(
      stream: db.collection('instructions').where('siteId', isEqualTo: sid).snapshots(),
      builder: (context, snap) {
        final all = (snap.data?.docs ?? const [])
            .map((d) => Instruction(d.id, d.data()))
            .where((i) => !i.expired)
            .toList()
          ..sort((a, b) {
            final c = a.kind.compareTo(b.kind);
            return c != 0 ? c : b.at.compareTo(a.at);
          });
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(
                child: Text(t('ins_title'),
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              ),
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: Text(t('ins_propose')),
                onPressed: () async {
                  final v = await _editDialog(context, t);
                  if (v == null) return;
                  try {
                    await db.collection('instructions').add({
                      ...v,
                      'siteId': sid,
                      'siteName': me.siteName,
                      'status': 'pending',
                      'from': 'client',
                      'by': me.id,
                      'byName': me.name,
                      'at': Timestamp.now(),
                    });
                    if (context.mounted) snack(context, t('ins_sent'), color: okGreen);
                  } catch (e) {
                    if (context.mounted) snack(context, t('err_generic', {'e': '$e'}), color: danger);
                  }
                },
              ),
            ]),
            Text(t('ins_client_hint'), style: const TextStyle(color: muted, fontSize: 12)),
            const SizedBox(height: 6),
            if (all.isEmpty)
              Text(t('ins_none'), style: const TextStyle(color: muted))
            else
              for (final i in all) _instrTile(t, i),
          ],
        );
      },
    );
  }
}

// ------------------------------------------------------------------ Agent

/// Consignes validées du site, affichées à l'agent de service.
class GuardInstructions extends StatelessWidget {
  const GuardInstructions({super.key, required this.t, required this.siteId});
  final T t;
  final String? siteId;

  @override
  Widget build(BuildContext context) {
    if (siteId == null) return const SizedBox.shrink();
    return StreamBuilder<QueryMap>(
      stream: db
          .collection('instructions')
          .where('siteId', isEqualTo: siteId)
          .where('status', isEqualTo: 'approved')
          .snapshots(),
      builder: (context, snap) {
        final list = (snap.data?.docs ?? const [])
            .map((d) => Instruction(d.id, d.data()))
            .where((i) => i.active)
            .toList()
          ..sort((a, b) => b.kind.compareTo(a.kind));
        if (list.isEmpty) return const SizedBox.shrink();
        return Card(
          color: const Color(0xFFFFF8E1),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.assignment, color: navy),
                  const SizedBox(width: 8),
                  Text(t('ins_title'),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 6),
                for (final i in list)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(i.kind == 'temporary' ? Icons.timer : Icons.push_pin,
                          size: 18, color: i.kind == 'temporary' ? warn : navy),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          i.kind == 'temporary' && i.until != null
                              ? '${i.text}  (${t('ins_until', {'d': _d(i.until!)})})'
                              : i.text,
                          style: const TextStyle(fontSize: 15),
                        ),
                      ),
                    ]),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ------------------------------------------------------------------ Administration

Future<void> _approve(BuildContext context, T t, Instruction i) async {
  final v = await _editDialog(context, t, cur: i, admin: true);
  if (v == null) return;
  await db.collection('instructions').doc(i.id).update({
    ...v,
    'status': 'approved',
    'approvedAt': Timestamp.now(),
  });
  if (context.mounted) snack(context, t('ins_ok'), color: okGreen);
}

Future<void> _reject(BuildContext context, T t, Instruction i) async {
  final c = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t('ins_reject')),
      content: TextField(controller: c, decoration: InputDecoration(labelText: t('ins_admin_note'))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: danger),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(t('ins_reject')),
        ),
      ],
    ),
  );
  if (ok != true) return;
  await db.collection('instructions').doc(i.id).update({'status': 'rejected', 'adminNote': c.text.trim()});
}

Widget _adminActions(BuildContext context, T t, Instruction i) => PopupMenuButton<String>(
      onSelected: (v) async {
        switch (v) {
          case 'ok':
            await _approve(context, t, i);
          case 'no':
            await _reject(context, t, i);
          case 'del':
            await db.collection('instructions').doc(i.id).delete();
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: 'ok', child: Text(t(i.status == 'approved' ? 'ins_edit' : 'ins_approve'))),
        if (i.status != 'rejected') PopupMenuItem(value: 'no', child: Text(t('ins_reject'))),
        PopupMenuItem(value: 'del', child: Text(t('delete'))),
      ],
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: pill(
            t(i.status == 'approved'
                ? (i.expired ? 'ins_expired' : 'ins_approved')
                : i.status == 'rejected'
                    ? 'ins_rejected'
                    : 'ins_pending'),
            i.status == 'approved' ? okGreen : (i.status == 'rejected' ? danger : warn)),
      ),
    );

/// Écran de l'administration : consignes d'un site.
class SiteInstructionsPage extends StatelessWidget {
  const SiteInstructionsPage({super.key, required this.t, required this.site});
  final T t;
  final Site site;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${t('ins_title')} · ${site.name}')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: Text(t('ins_new')),
        onPressed: () async {
          final v = await _editDialog(context, t, admin: true);
          if (v == null) return;
          await db.collection('instructions').add({
            ...v,
            'siteId': site.id,
            'siteName': site.name,
            'status': 'approved',
            'from': 'admin',
            'at': Timestamp.now(),
            'approvedAt': Timestamp.now(),
          });
        },
      ),
      body: StreamBuilder<QueryMap>(
        stream: db.collection('instructions').where('siteId', isEqualTo: site.id).snapshots(),
        builder: (context, snap) {
          final list = (snap.data?.docs ?? const [])
              .map((d) => Instruction(d.id, d.data()))
              .toList()
            ..sort((a, b) => b.at.compareTo(a.at));
          if (list.isEmpty) {
            return Center(child: Text(t('ins_none'), style: const TextStyle(color: muted)));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [for (final i in list) _instrTile(t, i, trailing: _adminActions(context, t, i))],
          );
        },
      ),
    );
  }
}

/// Consignes proposées par les clients, en attente de validation.
class PendingInstructions extends StatelessWidget {
  const PendingInstructions({super.key, required this.t});
  final T t;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QueryMap>(
      stream: db.collection('instructions').where('status', isEqualTo: 'pending').snapshots(),
      builder: (context, snap) {
        final list = (snap.data?.docs ?? const [])
            .map((d) => Instruction(d.id, d.data()))
            .toList()
          ..sort((a, b) => b.at.compareTo(a.at));
        if (list.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t('ins_pending_title', {'n': '${list.length}'}),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: warn)),
            const SizedBox(height: 6),
            for (final i in list)
              _instrTile(t, i, showSite: true, trailing: _adminActions(context, t, i)),
            const SizedBox(height: 18),
          ],
        );
      },
    );
  }
}
