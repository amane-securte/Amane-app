import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'data.dart';
import 'i18n.dart';
import 'theme.dart';
import 'widgets.dart';

const logCategories = ['round', 'incident', 'visitor', 'keys', 'instruction', 'other'];

class LogDoc {
  LogDoc(this.id, Map<String, dynamic> m)
      : uid = m['uid'] is String ? m['uid'] as String : '',
        name = m['name'] is String ? m['name'] as String : '',
        siteName = m['siteName'] is String ? m['siteName'] as String : '',
        category = m['category'] is String ? m['category'] as String : 'other',
        text = m['text'] is String ? m['text'] as String : '',
        at = m['at'] is Timestamp ? (m['at'] as Timestamp).toDate() : DateTime.now();
  final String id, uid, name, siteName, category, text;
  final DateTime at;
}

class LogTile extends StatelessWidget {
  const LogTile({super.key, required this.t, required this.l, this.showName = true});
  final T t;
  final LogDoc l;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final hot = l.category == 'incident';
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                pill(t('cat_${l.category}'), hot ? danger : navy),
                const SizedBox(width: 8),
                if (showName)
                  Expanded(
                    child: Text('${l.name} · ${l.siteName}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis),
                  )
                else
                  const Spacer(),
                ltrText('${dm(l.at)} ${hm(l.at)}',
                    style: const TextStyle(color: muted, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 6),
            Text(l.text),
          ],
        ),
      ),
    );
  }
}

/// Main courante de l'agent : ajouter une entrée et voir les siennes.
class LogbookScreen extends StatefulWidget {
  const LogbookScreen(
      {super.key, required this.t, required this.me, required this.siteName});
  final T t;
  final UserDoc me;
  final String siteName;

  @override
  State<LogbookScreen> createState() => _LogbookScreenState();
}

class _LogbookScreenState extends State<LogbookScreen> {
  final _text = TextEditingController();
  String _cat = 'round';
  late final Stream<QueryMap> _mine =
      db.collection('logs').where('uid', isEqualTo: widget.me.id).snapshots();

  T get t => widget.t;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() {
    final txt = _text.text.trim();
    if (txt.isEmpty) return;
    // Sans attendre : enregistré même hors connexion.
    db.collection('logs').add({
      'uid': widget.me.id,
      'name': widget.me.name,
      'siteId': widget.me.siteId,
      'siteName': widget.siteName,
      'category': _cat,
      'text': txt,
      'at': Timestamp.now(),
    });
    _text.clear();
    FocusScope.of(context).unfocus();
    snack(context, t('saved'), color: okGreen);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('logbook'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in logCategories)
                  ChoiceChip(
                    label: Text(t('cat_$c')),
                    selected: _cat == c,
                    onSelected: (_) => setState(() => _cat = c),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              minLines: 3,
              maxLines: 6,
              decoration: InputDecoration(hintText: t('log_hint')),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: Text(t('save')),
            ),
            const SizedBox(height: 6),
            Text(t('log_note'), style: const TextStyle(color: muted, fontSize: 12)),
            const SizedBox(height: 20),
            StreamBuilder<QueryMap>(
              stream: _mine,
              builder: (context, snap) {
                final logs = (snap.data?.docs ?? const [])
                    .map((d) => LogDoc(d.id, d.data()))
                    .toList()
                  ..sort((a, b) => b.at.compareTo(a.at));
                return Column(
                  children: logs
                      .take(30)
                      .map((l) => LogTile(t: t, l: l, showName: false))
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
