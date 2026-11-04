import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'data.dart';
import 'i18n.dart';
import 'theme.dart';
import 'widgets.dart';

const logCategories = ['round', 'incident', 'visitor', 'keys', 'money', 'lost', 'files', 'instruction', 'other'];

class LogDoc {
  LogDoc(this.id, Map<String, dynamic> m)
      : uid = m['uid'] is String ? m['uid'] as String : '',
        name = m['name'] is String ? m['name'] as String : '',
        siteName = m['siteName'] is String ? m['siteName'] as String : '',
        category = m['category'] is String ? m['category'] as String : 'other',
        text = m['text'] is String ? m['text'] as String : '',
        photos = [
          if (m['photos'] is List)
            for (final p in m['photos'] as List)
              if (p is String) p,
        ],
        at = m['at'] is Timestamp ? (m['at'] as Timestamp).toDate() : DateTime.now();
  final String id, uid, name, siteName, category, text;
  /// Identifiants des photos jointes (collection « photos »).
  final List<String> photos;
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
            if (l.photos.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final id in l.photos) PhotoThumb(id: id),
              ]),
            ],
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
  final _shots = <Uint8List>[];
  static const _maxShots = 4;
  late final Stream<QueryMap> _mine =
      db.collection('logs').where('uid', isEqualTo: widget.me.id).snapshots();

  T get t => widget.t;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource src) async {
    if (_shots.length >= _maxShots) return;
    try {
      // Compression sur le téléphone : ~150 Ko par photo.
      final x = await ImagePicker().pickImage(
          source: src, maxWidth: 1280, maxHeight: 1280, imageQuality: 55);
      if (x == null) return;
      final b = await x.readAsBytes();
      if (b.length > 700000) {
        if (mounted) snack(context, t('photo_too_big'), color: danger);
        return;
      }
      setState(() => _shots.add(b));
    } catch (e) {
      if (mounted) snack(context, t('err_generic', {'e': '$e'}), color: danger);
    }
  }

  void _save() {
    final txt = _text.text.trim();
    if (txt.isEmpty && _shots.isEmpty) return;
    final now = Timestamp.now();
    // Photos d'abord, puis l'entrée qui les référence. Sans attendre :
    // Firestore garde tout et l'envoie au retour du réseau.
    final ids = <String>[];
    for (final b in _shots) {
      final ref = db.collection('photos').doc();
      ids.add(ref.id);
      ref.set({
        'uid': widget.me.id,
        'siteId': widget.me.siteId,
        'data': base64Encode(b),
        'at': now,
      });
    }
    db.collection('logs').add({
      'uid': widget.me.id,
      'name': widget.me.name,
      'siteId': widget.me.siteId,
      'siteName': widget.siteName,
      'category': _cat,
      'text': txt,
      if (ids.isNotEmpty) 'photos': ids,
      'at': now,
    });
    setState(_shots.clear);
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
                    avatar: Icon(logIcon(c), size: 16),
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
            const SizedBox(height: 8),
            Row(children: [
              OutlinedButton.icon(
                onPressed: _shots.length >= _maxShots ? null : () => _pick(ImageSource.camera),
                icon: const Icon(Icons.photo_camera),
                label: Text(t('photo_take')),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _shots.length >= _maxShots ? null : () => _pick(ImageSource.gallery),
                icon: const Icon(Icons.photo_library),
                label: Text(t('photo_pick')),
              ),
            ]),
            if (_shots.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (var i = 0; i < _shots.length; i++)
                  Stack(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(_shots[i], width: 84, height: 84, fit: BoxFit.cover),
                    ),
                    PositionedDirectional(
                      top: 0,
                      end: 0,
                      child: InkWell(
                        onTap: () => setState(() => _shots.removeAt(i)),
                        child: const CircleAvatar(
                          radius: 12,
                          backgroundColor: Colors.black54,
                          child: Icon(Icons.close, size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                  ]),
              ]),
            ],
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


/// Vignette d'une photo de la main courante ; touchée, elle s'affiche en grand.
class PhotoThumb extends StatelessWidget {
  const PhotoThumb({super.key, required this.id, this.size = 84});
  final String id;
  final double size;

  static final _cache = <String, Future<Uint8List?>>{};

  static Future<Uint8List?> load(String id) => _cache[id] ??= () async {
        try {
          final d = await db.collection('photos').doc(id).get();
          final s = d.data()?['data'];
          return s is String ? base64Decode(s) : null;
        } catch (_) {
          _cache.remove(id);
          return null;
        }
      }();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: load(id),
      builder: (context, snap) {
        final b = snap.data;
        final box = SizedBox(
          width: size,
          height: size,
          child: b == null
              ? Container(
                  color: const Color(0xFFEDE6D6),
                  child: Icon(
                      snap.connectionState == ConnectionState.done
                          ? Icons.broken_image
                          : Icons.photo,
                      color: muted),
                )
              : Image.memory(b, fit: BoxFit.cover),
        );
        return InkWell(
          onTap: b == null
              ? null
              : () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => Scaffold(
                      backgroundColor: Colors.black,
                      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
                      body: InteractiveViewer(child: Center(child: Image.memory(b))),
                    ),
                  )),
          child: ClipRRect(borderRadius: BorderRadius.circular(8), child: box),
        );
      },
    );
  }
}


IconData logIcon(String c) => switch (c) {
      'round' => Icons.directions_walk,
      'incident' => Icons.report,
      'visitor' => Icons.person_pin,
      'keys' => Icons.key,
      'money' => Icons.payments,
      'lost' => Icons.search,
      'files' => Icons.folder,
      'instruction' => Icons.assignment,
      _ => Icons.notes,
    };
