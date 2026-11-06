import 'package:flutter/material.dart';

import 'data.dart';
import 'i18n.dart';
import 'messages.dart';
import 'services.dart';
import 'theme.dart';
import 'widgets.dart';

/// Catalogue des prestations d'AMANE, visible par tous (même avant connexion).
/// Un client connecté peut demander une prestation directement.
class ServicesCatalog extends StatelessWidget {
  const ServicesCatalog({super.key, required this.t, this.me, this.mine = const []});
  final T t;
  final UserDoc? me;
  final List<String> mine;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('catalog_title'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(t('catalog_intro'), style: const TextStyle(color: muted)),
          const SizedBox(height: 10),
          for (final x in services)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFF3EBD9),
                  child: Icon(serviceIcon(x), color: navy),
                ),
                title: Text(t('sv_$x'), style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(t('svd_$x')),
                trailing: mine.contains(x)
                    ? const Icon(Icons.check_circle, color: okGreen)
                    : me == null
                        ? null
                        : TextButton(
                            onPressed: () => requestService(context, t, me!, mine, initial: x),
                            child: Text(t('catalog_ask')),
                          ),
              ),
            ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
            FilledButton.icon(
              onPressed: () => openUrl('tel:$controlPhone'),
              icon: const Icon(Icons.phone),
              label: Text(t('catalog_call')),
            ),
            OutlinedButton.icon(
              onPressed: () => openUrl('https://wa.me/${controlPhone.replaceAll('+', '')}'),
              icon: const Icon(Icons.chat, color: okGreen),
              label: const Text('WhatsApp'),
            ),
          ]),
        ],
      ),
    );
  }
}
