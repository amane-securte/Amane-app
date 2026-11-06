import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'data.dart';
import 'i18n.dart';
import 'theme.dart';

/// Nom de la personne connectée (renseigné à la connexion), pour le journal.
String auditName = '';

/// Journal d'activité de l'encadrement : qui a fait quoi, et quand.
/// Lisible par le Directeur Général (fondateur) uniquement ; jamais modifiable.
void audit(String action, String detail) {
  final u = FirebaseAuth.instance.currentUser;
  if (u == null) return;
  db.collection('audit').add({
    'by': u.uid,
    'byName': auditName,
    'action': action,
    'detail': detail,
    'at': Timestamp.now(),
  }).ignore();
}

class AuditScreen extends StatelessWidget {
  const AuditScreen({super.key, required this.t});
  final T t;

  @override
  Widget build(BuildContext context) {
    final since = Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 30)));
    return Scaffold(
      appBar: AppBar(title: Text(t('audit_title'))),
      body: StreamBuilder<QueryMap>(
        stream: db.collection('audit').where('at', isGreaterThan: since).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text(t('err_generic').replaceAll('{e}', '${snap.error}'), style: const TextStyle(color: danger)));
          }
          final rows = (snap.data?.docs ?? const []).map((d) => d.data()).toList()
            ..sort((a, b) => (b['at'] as Timestamp).compareTo(a['at'] as Timestamp));
          if (rows.isEmpty) {
            return Center(child: Text(t('audit_none'), style: const TextStyle(color: muted)));
          }
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Text(t('audit_hint'), style: const TextStyle(color: muted, fontSize: 12)),
              const SizedBox(height: 6),
              for (final r in rows)
                Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.history, color: navy),
                    title: Text('${r['byName'] ?? ''} · ${t('au_${r['action']}')}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${r['detail'] ?? ''}'),
                    trailing: Text(
                      () {
                        final d = (r['at'] as Timestamp).toDate();
                        return '${two(d.day)}/${two(d.month)}\n${two(d.hour)}:${two(d.minute)}';
                      }(),
                      textAlign: TextAlign.end,
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
