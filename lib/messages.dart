import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'data.dart';
import 'i18n.dart';
import 'instructions.dart';
import 'services.dart';
import 'theme.dart';
import 'widgets.dart';

/// Un élément du fil client ↔ AMANE : message, remarque ou évaluation.
class Msg {
  Msg(this.id, Map<String, dynamic> m)
      : clientUid = _s(m['clientUid']),
        clientName = _s(m['clientName']),
        siteName = _s(m['siteName']),
        from = _s(m['from']).isEmpty ? 'client' : _s(m['from']),
        kind = _s(m['kind']).isEmpty ? 'msg' : _s(m['kind']),
        text = _s(m['text']),
        service = m['service'] is num ? (m['service'] as num).toInt() : 0,
        svc = _s(m['svc']),
        guards = [
          if (m['guards'] is List)
            for (final g in m['guards'] as List)
              if (g is Map) (_s(g['uid']), _s(g['name']), g['stars'] is num ? (g['stars'] as num).toInt() : 0),
        ],
        seenAdmin = m['seenAdmin'] == true,
        seenClient = m['seenClient'] == true,
        at = m['at'] is Timestamp ? (m['at'] as Timestamp).toDate() : DateTime.now();
  final String id, clientUid, clientName, siteName, from, kind, text;
  /// Prestation demandée (kind == 'service').
  final String svc;
  final int service;
  final List<(String, String, int)> guards;
  final bool seenAdmin, seenClient;
  final DateTime at;

  static String _s(Object? v) => v is String ? v : '';
}

Widget stars(int n, {double size = 18}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(i <= n ? Icons.star : Icons.star_border, size: size, color: const Color(0xFFD1A850)),
      ],
    );

class _StarPicker extends StatelessWidget {
  const _StarPicker({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= 5; i++)
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: () => onChanged(i),
              icon: Icon(i <= value ? Icons.star : Icons.star_border,
                  size: 30, color: const Color(0xFFD1A850)),
            ),
        ],
      );
}

/// Bulles d'un fil, du plus ancien au plus récent.
class _Thread extends StatelessWidget {
  const _Thread({required this.t, required this.items, required this.mine});
  final T t;
  final List<Msg> items;
  /// 'client' ou 'admin' : côté de l'écran qui regarde.
  final String mine;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(t(mine == 'client' ? 'msg_empty_client' : 'msg_empty'),
              textAlign: TextAlign.center, style: const TextStyle(color: muted)),
        ),
      );
    }
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final m = items[items.length - 1 - i];
        final me = m.from == mine;
        final color = m.kind == 'rating' || m.kind == 'service'
            ? const Color(0xFFFFF8E1)
            : m.kind == 'note'
                ? const Color(0xFFE3F2FD)
                : me
                    ? const Color(0xFFE8F0E3)
                    : Colors.white;
        return Align(
          alignment: me ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
          child: Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFDBD1BA)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (m.kind != 'msg')
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(
                          m.kind == 'rating'
                              ? Icons.star_rate
                              : m.kind == 'service'
                                  ? serviceIcon(m.svc)
                                  : Icons.sticky_note_2,
                          size: 16,
                          color: navy),
                      const SizedBox(width: 4),
                      Text(
                          m.kind == 'service'
                              ? '${t('service_req')} : ${t('sv_${m.svc}')}'
                              : t(m.kind == 'rating' ? 'rate_title' : 'note_title'),
                          style: const TextStyle(fontWeight: FontWeight.w700, color: navy)),
                    ]),
                  ),
                if (m.kind == 'rating') ...[
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('${t('rate_service')}  '),
                    stars(m.service),
                  ]),
                  for (final g in m.guards)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('${g.$2}  '),
                      stars(g.$3, size: 16),
                    ]),
                ],
                if (m.text.isNotEmpty) Text(m.text, style: const TextStyle(fontSize: 15)),
                const SizedBox(height: 4),
                Text(
                  '${m.from == 'admin' ? 'AMANE' : m.clientName} · ${dm(m.at)} ${hm(m.at)}',
                  style: const TextStyle(fontSize: 11, color: muted),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Composer extends StatefulWidget {
  const _Composer({required this.t, required this.onSend, this.allowNote = false});
  final T t;
  final bool allowNote;
  final Future<void> Function(String text, String kind) onSend;
  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final _c = TextEditingController();
  var _kind = 'msg';
  var _busy = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        decoration: const BoxDecoration(
          color: Color(0xFFFFFCF5),
          border: Border(top: BorderSide(color: Color(0xFFDBD1BA))),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.allowNote)
              Row(children: [
                ChoiceChip(
                  label: Text(t('kind_msg')),
                  selected: _kind == 'msg',
                  onSelected: (_) => setState(() => _kind = 'msg'),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  avatar: const Icon(Icons.sticky_note_2, size: 16),
                  label: Text(t('kind_note')),
                  selected: _kind == 'note',
                  onSelected: (_) => setState(() => _kind = 'note'),
                ),
              ]),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _c,
                  minLines: 1,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: t(_kind == 'note' ? 'note_hint' : 'msg_hint'),
                    isDense: true,
                  ),
                ),
              ),
              IconButton.filled(
                onPressed: _busy
                    ? null
                    : () async {
                        final txt = _c.text.trim();
                        if (txt.isEmpty) return;
                        setState(() => _busy = true);
                        try {
                          await widget.onSend(txt, _kind);
                          _c.clear();
                        } catch (e) {
                          if (context.mounted) {
                            snack(context, t('err_generic', {'e': '$e'}), color: danger);
                          }
                        }
                        if (mounted) setState(() => _busy = false);
                      },
                icon: const Icon(Icons.send),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ Client

/// Onglet « Contact » du client : messages, remarques et évaluation.
class ClientMessagesTab extends StatefulWidget {
  const ClientMessagesTab({super.key, required this.t, required this.me});
  final T t;
  final UserDoc me;
  @override
  State<ClientMessagesTab> createState() => _ClientMessagesTabState();
}

class _ClientMessagesTabState extends State<ClientMessagesTab> {
  late final Stream<QueryMap> _s =
      db.collection('messages').where('clientUid', isEqualTo: widget.me.id).snapshots();
  T get t => widget.t;
  UserDoc get me => widget.me;

  Map<String, dynamic> _base() => {
        'clientUid': me.id,
        'clientName': me.name,
        'siteId': me.siteId,
        'siteName': me.siteName,
        'from': 'client',
        'seenAdmin': false,
        'at': Timestamp.now(),
      };

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QueryMap>(
      stream: _s,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text(t('rules_needed'), style: const TextStyle(color: danger)));
        }
        final items = (snap.data?.docs ?? const [])
            .map((d) => Msg(d.id, d.data()))
            .toList()
          ..sort((a, b) => a.at.compareTo(b.at));
        // Réponses d'AMANE vues : on les marque lues.
        for (final m in items.where((m) => m.from == 'admin' && !m.seenClient)) {
          db.collection('messages').doc(m.id).update({'seenClient': true}).catchError((_) {});
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFA9812F),
                  minimumSize: const Size.fromHeight(46),
                ),
                icon: const Icon(Icons.star_rate),
                label: Text(t('rate_btn')),
                onPressed: () => _rate(context),
              ),
            ),
            Expanded(child: _Thread(t: t, items: items, mine: 'client')),
            _Composer(
              t: t,
              allowNote: true,
              onSend: (txt, kind) =>
                  db.collection('messages').add({..._base(), 'kind': kind, 'text': txt}),
            ),
          ],
        );
      },
    );
  }

  /// Évaluation du service et de chaque agent ayant travaillé sur le site
  /// pendant les 30 derniers jours.
  Future<void> _rate(BuildContext context) async {
    final guards = <String, String>{};
    final sid = me.siteId;
    if (sid != null) {
      try {
        final q = await db.collection('punches').where('siteId', isEqualTo: sid).get();
        final since = DateTime.now().subtract(const Duration(days: 30));
        for (final d in q.docs) {
          final p = PunchDoc(d.id, d.data());
          if (p.inAt.isAfter(since)) guards[p.uid] = p.name;
        }
      } catch (_) {}
    }
    if (!context.mounted) return;
    var service = 0;
    final per = {for (final g in guards.keys) g: 0};
    final comment = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(t('rate_title')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t('rate_service'), style: const TextStyle(fontWeight: FontWeight.w600)),
                _StarPicker(value: service, onChanged: (v) => setS(() => service = v)),
                if (guards.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(t('rate_guards'), style: const TextStyle(fontWeight: FontWeight.w600)),
                  for (final e in guards.entries) ...[
                    Text(e.value),
                    _StarPicker(
                        value: per[e.key] ?? 0, onChanged: (v) => setS(() => per[e.key] = v)),
                  ],
                ],
                const SizedBox(height: 8),
                TextField(
                  controller: comment,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(labelText: t('rate_comment')),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'))),
            FilledButton(
              onPressed: service == 0 ? null : () => Navigator.pop(ctx, true),
              child: Text(t('rate_send')),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await db.collection('messages').add({
        ..._base(),
        'kind': 'rating',
        'service': service,
        'guards': [
          for (final e in guards.entries)
            if ((per[e.key] ?? 0) > 0) {'uid': e.key, 'name': e.value, 'stars': per[e.key]},
        ],
        'text': comment.text.trim(),
      });
      if (context.mounted) snack(context, t('rate_thanks'), color: okGreen);
    } catch (e) {
      if (context.mounted) snack(context, t('err_generic', {'e': '$e'}), color: danger);
    }
  }
}

// ------------------------------------------------------------------ Administration

/// Onglet « Messages » de l'administration : fils par client, réponses,
/// et synthèse des évaluations (service et agents).
class AdminMessagesTab extends StatefulWidget {
  const AdminMessagesTab({super.key, required this.t});
  final T t;
  @override
  State<AdminMessagesTab> createState() => _AdminMessagesTabState();
}

class _AdminMessagesTabState extends State<AdminMessagesTab> {
  late final Stream<QueryMap> _s = db.collection('messages').snapshots();
  T get t => widget.t;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QueryMap>(
      stream: _s,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text(t('rules_needed'), style: const TextStyle(color: danger)));
        }
        final all = (snap.data?.docs ?? const []).map((d) => Msg(d.id, d.data())).toList();
        final threads = <String, List<Msg>>{};
        for (final m in all) {
          (threads[m.clientUid] ??= []).add(m);
        }
        for (final l in threads.values) {
          l.sort((a, b) => a.at.compareTo(b.at));
        }
        final order = threads.entries.toList()
          ..sort((a, b) => b.value.last.at.compareTo(a.value.last.at));

        // Synthèse des évaluations.
        final ratings = all.where((m) => m.kind == 'rating').toList();
        final svc = ratings.where((r) => r.service > 0).map((r) => r.service).toList();
        final per = <String, (String, List<int>)>{};
        for (final r in ratings) {
          for (final g in r.guards) {
            final cur = per[g.$1] ?? (g.$2, <int>[]);
            cur.$2.add(g.$3);
            per[g.$1] = cur;
          }
        }
        double avg(List<int> l) => l.isEmpty ? 0 : l.reduce((a, b) => a + b) / l.length;
        final perList = per.values.toList()..sort((a, b) => avg(b.$2).compareTo(avg(a.$2)));

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            PendingInstructions(t: t),
            Text(t('perf_title'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: ratings.isEmpty
                    ? Text(t('perf_none'), style: const TextStyle(color: muted))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(
                                child: Text(t('rate_service'),
                                    style: const TextStyle(fontWeight: FontWeight.w600))),
                            stars(avg(svc).round()),
                            const SizedBox(width: 6),
                            ltrText('${avg(svc).toStringAsFixed(1)} (${svc.length})'),
                          ]),
                          if (perList.isNotEmpty) const Divider(),
                          for (final g in perList)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(children: [
                                const Icon(Icons.badge, size: 16, color: navy),
                                const SizedBox(width: 6),
                                Expanded(child: Text(g.$1)),
                                stars(avg(g.$2).round(), size: 16),
                                const SizedBox(width: 6),
                                ltrText('${avg(g.$2).toStringAsFixed(1)} (${g.$2.length})',
                                    style: TextStyle(
                                        color: avg(g.$2) < 3 ? danger : null,
                                        fontWeight: FontWeight.w600)),
                              ]),
                            ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 18),
            Text(t('msg_threads'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            if (order.isEmpty) Text(t('msg_empty'), style: const TextStyle(color: muted)),
            for (final e in order)
              Builder(builder: (context) {
                final last = e.value.last;
                final unread = e.value.where((m) => m.from == 'client' && !m.seenAdmin).length;
                final name = e.value.firstWhere((m) => m.clientName.isNotEmpty, orElse: () => last).clientName;
                final site = e.value.firstWhere((m) => m.siteName.isNotEmpty, orElse: () => last).siteName;
                return Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: unread > 0 ? danger : navy,
                      child: unread > 0
                          ? Text('$unread', style: const TextStyle(color: Colors.white))
                          : const Icon(Icons.storefront, color: Colors.white, size: 20),
                    ),
                    title: Text(site.isEmpty ? name : '$name · $site'),
                    subtitle: Text(
                      last.kind == 'rating'
                          ? '⭐ ${t('rate_title')}'
                          : last.kind == 'service'
                              ? '🛒 ${t('sv_${last.svc}')}'
                              : last.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text('${dm(last.at)}\n${hm(last.at)}',
                        textAlign: TextAlign.end,
                        style: const TextStyle(fontSize: 11, color: muted)),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => _AdminThreadPage(t: t, clientUid: e.key, title: name, last: last),
                    )),
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}

class _AdminThreadPage extends StatelessWidget {
  const _AdminThreadPage(
      {required this.t, required this.clientUid, required this.title, required this.last});
  final T t;
  final String clientUid, title;
  final Msg last;

  @override
  Widget build(BuildContext context) {
    final stream =
        db.collection('messages').where('clientUid', isEqualTo: clientUid).snapshots();
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: StreamBuilder<QueryMap>(
        stream: stream,
        builder: (context, snap) {
          final items = (snap.data?.docs ?? const [])
              .map((d) => Msg(d.id, d.data()))
              .toList()
            ..sort((a, b) => a.at.compareTo(b.at));
          for (final m in items.where((m) => m.from == 'client' && !m.seenAdmin)) {
            db.collection('messages').doc(m.id).update({'seenAdmin': true}).catchError((_) {});
          }
          return Column(children: [
            Expanded(child: _Thread(t: t, items: items, mine: 'admin')),
            _Composer(
              t: t,
              onSend: (txt, kind) => db.collection('messages').add({
                'clientUid': clientUid,
                'clientName': last.clientName,
                'siteName': last.siteName,
                'from': 'admin',
                'kind': 'msg',
                'text': txt,
                'seenAdmin': true,
                'seenClient': false,
                'at': Timestamp.now(),
              }),
            ),
          ]);
        },
      ),
    );
  }
}


/// Le client demande une prestation supplémentaire (devis) depuis l'appli.
Future<void> requestService(BuildContext context, T t, UserDoc me, List<String> mine, {String initial = ''}) async {
  var pick = initial;
  final note = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text(t('request_service')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final x in services)
                  ChoiceChip(
                    avatar: Icon(serviceIcon(x), size: 16),
                    label: Text(t('sv_$x')),
                    selected: pick == x,
                    onSelected: (_) => setS(() => pick = x),
                  ),
              ]),
              const SizedBox(height: 8),
              TextField(
                controller: note,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(labelText: t('service_note'), hintText: t('service_note_hint')),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'))),
          FilledButton(
            onPressed: pick.isEmpty ? null : () => Navigator.pop(ctx, true),
            child: Text(t('send')),
          ),
        ],
      ),
    ),
  );
  if (ok != true) return;
  try {
    await db.collection('messages').add({
      'clientUid': me.id,
      'clientName': me.name,
      'siteId': me.siteId,
      'siteName': me.siteName,
      'from': 'client',
      'kind': 'service',
      'svc': pick,
      'text': note.text.trim(),
      'seenAdmin': false,
      'at': Timestamp.now(),
    });
    if (context.mounted) snack(context, t('service_sent'), color: okGreen);
  } catch (e) {
    if (context.mounted) snack(context, t('err_generic', {'e': '$e'}), color: danger);
  }
}
