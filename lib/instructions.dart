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
        replaces = _s(m['replaces']),
        start = m['start'] is Timestamp ? (m['start'] as Timestamp).toDate() : null,
        until = m['until'] is Timestamp ? (m['until'] as Timestamp).toDate() : null,
        at = m['at'] is Timestamp ? (m['at'] as Timestamp).toDate() : DateTime.now();
  final String id, siteId, siteName, kind, text, status, from, byName, adminNote;
  /// Demande de modification d'une consigne existante (son identifiant).
  final String replaces;
  /// Période de validité d'une consigne temporaire.
  final DateTime? start, until;
  final DateTime at;

  static String _s(Object? v) => v is String ? v : '';

  /// Temporaire dont la date de fin est passée.
  bool get expired =>
      kind == 'temporary' && until != null && until!.isBefore(DateTime.now().subtract(const Duration(days: 1)));
  /// Temporaire qui n'a pas encore commencé.
  bool get upcoming => kind == 'temporary' && start != null && start!.isAfter(DateTime.now());
  bool get active => status == 'approved' && !expired && !upcoming;
}

String _d(DateTime d) => '${two(d.day)}/${two(d.month)}/${d.year}';

String period(T t, Instruction i) => i.start != null && i.until != null
    ? t('ins_period', {'s': _d(i.start!), 'e': _d(i.until!)})
    : i.until != null
        ? t('ins_until', {'d': _d(i.until!)})
        : '';

Widget _instrTile(T t, Instruction i, {Widget? trailing, bool showSite = false}) {
  final (label, color) = switch (i.status) {
    'approved' => i.expired
        ? (t('ins_expired'), muted)
        : i.upcoming
            ? (t('ins_upcoming'), navy)
            : (t('ins_approved'), okGreen),
    'rejected' => (t('ins_rejected'), danger),
    _ => (t(i.replaces.isNotEmpty ? 'ins_pending_edit' : 'ins_pending'), warn),
  };
  return Card(
    margin: const EdgeInsets.only(bottom: 6),
    child: ListTile(
      leading: Icon(i.kind == 'temporary' ? Icons.timer : Icons.push_pin,
          color: i.kind == 'temporary' ? warn : navy),
      title: Text(i.text),
      subtitle: Text([
        t(i.kind == 'temporary' ? 'ins_temporary' : 'ins_permanent'),
        if (i.kind == 'temporary') period(t, i),
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
  DateTime? start = cur?.start;
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
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.play_arrow),
                      label: Text(start == null ? t('ins_pick_start') : '${t('ins_from')} ${_d(start!)}'),
                      onPressed: () async {
                        final now = DateTime.now();
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate: start ?? now,
                          firstDate: DateTime(now.year - 1),
                          lastDate: DateTime(now.year + 2),
                        );
                        if (d != null) setS(() => start = d);
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.stop),
                      label: Text(until == null ? t('ins_pick_until') : '${t('ins_to')} ${_d(until!)}'),
                      onPressed: () async {
                        final now = DateTime.now();
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate: until ?? (start ?? now).add(const Duration(days: 7)),
                          firstDate: start ?? DateTime(now.year, now.month, now.day),
                          lastDate: DateTime(now.year + 2),
                        );
                        if (d != null) setS(() => until = d);
                      },
                    ),
                  ),
                ]),
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
              if (kind == 'temporary' && (start == null || until == null)) {
                setS(() => error = t('ins_err_until'));
                return;
              }
              if (kind == 'temporary' && until!.isBefore(start!)) {
                setS(() => error = t('ins_err_order'));
                return;
              }
              Navigator.pop(ctx, {
                'kind': kind,
                'text': text.text.trim(),
                'start': kind == 'temporary' && start != null ? Timestamp.fromDate(start!) : null,
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

  /// Demande de mise à jour d'une consigne validée : nouvelle proposition
  /// qui remplacera l'ancienne une fois acceptée par AMANE.
  Future<void> _clientEdit(BuildContext context, Instruction i) async {
    final v = await _editDialog(context, t, cur: i);
    if (v == null) return;
    try {
      await db.collection('instructions').add({
        ...v,
        'siteId': me.siteId,
        'siteName': me.siteName,
        'status': 'pending',
        'from': 'client',
        'by': me.id,
        'byName': me.name,
        'replaces': i.id,
        'at': Timestamp.now(),
      });
      if (context.mounted) snack(context, t('ins_sent'), color: okGreen);
    } catch (e) {
      if (context.mounted) snack(context, t('err_generic', {'e': '$e'}), color: danger);
    }
  }

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
              for (final i in all)
                _instrTile(t, i,
                    trailing: i.status == 'approved' && !all.any((x) => x.replaces == i.id)
                        ? IconButton(
                            tooltip: t('ins_request_edit'),
                            icon: const Icon(Icons.edit_note, color: navy),
                            onPressed: () => _clientEdit(context, i),
                          )
                        : null),
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
                          i.kind == 'temporary' ? '${i.text}  (${period(t, i)})' : i.text,
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
  if (i.replaces.isNotEmpty) {
    // Mise à jour demandée par le client : on remplace l'ancienne consigne.
    await db.collection('instructions').doc(i.replaces).update({
      ...v,
      'status': 'approved',
      'approvedAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
    });
    await db.collection('instructions').doc(i.id).delete();
  } else {
    await db.collection('instructions').doc(i.id).update({
      ...v,
      'status': 'approved',
      'approvedAt': Timestamp.now(),
    });
  }
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
                ? (i.expired ? 'ins_expired' : i.upcoming ? 'ins_upcoming' : 'ins_approved')
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
