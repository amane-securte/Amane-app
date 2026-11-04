import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'data.dart';
import 'i18n.dart';
import 'pdf_docs.dart';
import 'theme.dart';
import 'widgets.dart';

/// Catégories de dépenses de la société.
const expenseCats = [
  'fuel', // carburant des véhicules
  'transport', // transport / déplacements
  'food', // nourriture des agents
  'vehicle', // entretien et réparation des véhicules
  'office', // entretien des bureaux
  'works', // travaux de rénovation
  'electricity', // électricité
  'water', // eau
  'phone', // téléphone et internet
  'equipment', // uniformes et équipements
  'rent', // loyer
  'other', // autres dépenses
];

const expenseCatsFr = {
  'fuel': 'Carburant',
  'transport': 'Transport',
  'food': 'Nourriture',
  'vehicle': 'Entretien véhicules',
  'office': 'Entretien bureaux',
  'works': 'Travaux de rénovation',
  'electricity': 'Électricité',
  'water': 'Eau',
  'phone': 'Téléphone / Internet',
  'equipment': 'Uniformes / équipements',
  'rent': 'Loyer',
  'other': 'Autres dépenses',
};

IconData expenseIcon(String c) => switch (c) {
      'fuel' => Icons.local_gas_station,
      'transport' => Icons.directions_bus,
      'food' => Icons.restaurant,
      'vehicle' => Icons.car_repair,
      'office' => Icons.business,
      'works' => Icons.construction,
      'electricity' => Icons.bolt,
      'water' => Icons.water_drop,
      'phone' => Icons.phone_android,
      'equipment' => Icons.checkroom,
      'rent' => Icons.home_work,
      _ => Icons.receipt,
    };

/// Une dépense, rangée dans la collection « rates » (réservée à
/// l'administration par les règles de sécurité) avec `exp: true`.
class Expense {
  Expense(this.id, Map<String, dynamic> m)
      : cat = m['cat'] is String ? m['cat'] as String : 'other',
        label = m['label'] is String ? m['label'] as String : '',
        month = m['month'] is String ? m['month'] as String : '',
        siteName = m['siteName'] is String ? m['siteName'] as String : '',
        amount = m['amount'] is num ? (m['amount'] as num).toDouble() : 0,
        date = m['date'] is Timestamp ? (m['date'] as Timestamp).toDate() : DateTime.now();
  final String id, cat, label, month, siteName;
  final double amount;
  final DateTime date;
}

String _money(num v) {
  final s = v.round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return b.toString();
}

/// Section « Dépenses » de l'onglet Comptabilité.
class ExpensesSection extends StatelessWidget {
  const ExpensesSection({
    super.key,
    required this.t,
    required this.month,
    required this.items,
    required this.sites,
  });
  final T t;
  final DateTime month;
  final List<Expense> items;
  final List<Site> sites;

  String get _monthKey => '${month.year}-${two(month.month)}';

  @override
  Widget build(BuildContext context) {
    final byCat = <String, double>{};
    for (final e in items) {
      byCat[e.cat] = (byCat[e.cat] ?? 0) + e.amount;
    }
    final total = items.fold<double>(0, (s, e) => s + e.amount);
    final sorted = [...items]..sort((a, b) => b.date.compareTo(a.date));
    final cats = byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(t('expenses'),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            ),
            if (items.isNotEmpty)
              IconButton(
                tooltip: t('exp_pdf'),
                icon: const Icon(Icons.picture_as_pdf, color: danger),
                onPressed: () async {
                  try {
                    await printExpenses(
                      month: '${two(month.month)}/${month.year}',
                      byCat: [for (final c in cats) (expenseCatsFr[c.key] ?? c.key, c.value)],
                      lines: [
                        for (final e in sorted.reversed)
                          (
                            '${two(e.date.day)}/${two(e.date.month)}',
                            expenseCatsFr[e.cat] ?? e.cat,
                            [e.label, if (e.siteName.isNotEmpty) e.siteName].join(' · '),
                            e.amount,
                          ),
                      ],
                      total: total,
                    );
                  } catch (err) {
                    if (context.mounted) {
                      snack(context, t('err_generic', {'e': '$err'}), color: danger);
                    }
                  }
                },
              ),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: Text(t('exp_add')),
              onPressed: () => addExpense(context, t, month, sites),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (items.isEmpty)
          Text(t('exp_none'), style: const TextStyle(color: muted))
        else ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Column(
                children: [
                  for (final c in cats)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(children: [
                        Icon(expenseIcon(c.key), size: 18, color: navy),
                        const SizedBox(width: 8),
                        Expanded(child: Text(t('ec_${c.key}'))),
                        ltrText('${_money(c.value)} MRU',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  const Divider(),
                  Row(children: [
                    Expanded(
                      child: Text(t('total_expenses'),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    ltrText('${_money(total)} MRU',
                        style: const TextStyle(fontWeight: FontWeight.w700, color: danger)),
                  ]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(t('exp_hint'), style: const TextStyle(color: muted, fontSize: 12)),
          for (final e in sorted)
            Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                leading: Icon(expenseIcon(e.cat), color: navy),
                title: Text(e.label.isEmpty ? t('ec_${e.cat}') : e.label),
                subtitle: Text([
                  '${two(e.date.day)}/${two(e.date.month)}',
                  t('ec_${e.cat}'),
                  if (e.siteName.isNotEmpty) e.siteName,
                ].join(' · ')),
                trailing: ltrText('${_money(e.amount)} MRU',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                onLongPress: () => _delete(context, e),
              ),
            ),
        ],
      ],
    );
  }

  Future<void> _delete(BuildContext context, Expense e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(t('exp_delete_q', {'a': _money(e.amount)})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('delete')),
          ),
        ],
      ),
    );
    if (ok == true) await db.collection('rates').doc(e.id).delete();
  }

  String get monthKey => _monthKey;
}

/// Saisie d'une dépense.
Future<void> addExpense(BuildContext context, T t, DateTime month, List<Site> sites) async {
  var cat = 'fuel';
  String? siteId;
  final amount = TextEditingController();
  final label = TextEditingController();
  final now = DateTime.now();
  var date = (now.year == month.year && now.month == month.month)
      ? DateTime(now.year, now.month, now.day)
      : DateTime(month.year, month.month, 1);
  String? error;

  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text(t('exp_add')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in expenseCats)
                    ChoiceChip(
                      avatar: Icon(expenseIcon(c), size: 16),
                      label: Text(t('ec_$c')),
                      selected: cat == c,
                      onSelected: (_) => setS(() => cat = c),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: t('exp_amount'), suffixText: 'MRU'),
              ),
              TextField(
                controller: label,
                decoration: InputDecoration(
                    labelText: t('exp_label'), hintText: t('exp_label_hint')),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                initialValue: siteId,
                isExpanded: true,
                decoration: InputDecoration(labelText: t('exp_site')),
                items: [
                  DropdownMenuItem(value: null, child: Text(t('exp_general'))),
                  for (final s in sites) DropdownMenuItem(value: s.id, child: Text(s.name)),
                ],
                onChanged: (v) => setS(() => siteId = v),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.event),
                label: Text('${two(date.day)}/${two(date.month)}/${date.year}'),
                onPressed: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: date,
                    firstDate: DateTime(2024),
                    lastDate: DateTime(now.year + 1, 12, 31),
                  );
                  if (d != null) setS(() => date = d);
                },
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: const TextStyle(color: danger)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'))),
          FilledButton(
            onPressed: () async {
              final a = double.tryParse(amount.text.replaceAll(RegExp(r'[^0-9.]'), ''));
              if (a == null || a <= 0) {
                setS(() => error = t('exp_err_amount'));
                return;
              }
              final s = sites.where((s) => s.id == siteId).firstOrNull;
              await db.collection('rates').add({
                'exp': true,
                'cat': cat,
                'amount': a,
                'label': label.text.trim(),
                'siteId': siteId,
                'siteName': s?.name ?? '',
                'date': Timestamp.fromDate(date),
                'month': '${date.year}-${two(date.month)}',
                'createdAt': Timestamp.now(),
              });
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
            child: Text(t('save')),
          ),
        ],
      ),
    ),
  );
  if (saved == true && context.mounted) snack(context, t('saved'), color: okGreen);
}
