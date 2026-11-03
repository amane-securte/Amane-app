import 'package:flutter/material.dart';

import 'i18n.dart';
import 'theme.dart';
import 'widgets.dart';

/// Numéros d'urgence de Mauritanie (Nouakchott), fournis par AMANE.
const policeNumber = '117'; // Police secours – شرطة النجدة
const fireNumber = '118'; // Sapeurs-pompiers – المطافئ
const gendarmerieNumber = '116'; // Gendarmerie nationale – الدرك الوطني

class EmergencyEntry {
  const EmergencyEntry(this.ar, this.fr, this.number);
  final String ar, fr, number;
}

class EmergencySection {
  const EmergencySection(this.ar, this.fr, this.entries);
  final String ar, fr;
  final List<EmergencyEntry> entries;
}

const emergencySections = <EmergencySection>[
  EmergencySection('أرقام النجدة', 'Urgences', [
    EmergencyEntry('شرطة النجدة', 'Police secours', '117'),
    EmergencyEntry('المطافئ', 'Sapeurs-pompiers', '118'),
    EmergencyEntry('الدرك الوطني', 'Gendarmerie nationale', '116'),
    EmergencyEntry('الحرس الوطني', 'Garde nationale', '102'),
    EmergencyEntry('التجمع العام لأمن الطرق', 'Groupement général de la sécurité routière', '119'),
  ]),
  EmergencySection('الدرك', 'Gendarmerie', [
    EmergencyEntry('الدرك البحري', 'Gendarmerie maritime', '45253990'),
    EmergencyEntry('فرقة الدرك المختلطة', 'Brigade mixte de gendarmerie', '45252518'),
  ]),
  EmergencySection('المفوضيات – نواكشوط', 'Commissariats – Nouakchott', [
    EmergencyEntry('مفوضية تفرغ زينه 1', 'Commissariat Tevragh Zeina 1', '45252310'),
    EmergencyEntry('مفوضية تفرغ زينه 2', 'Commissariat Tevragh Zeina 2', '45242952'),
    EmergencyEntry('مفوضية لكصر 1', 'Commissariat Ksar 1', '45252166'),
    EmergencyEntry('مفوضية لكصر 2', 'Commissariat Ksar 2', '45252738'),
    EmergencyEntry('مفوضية الميناء 1', 'Commissariat El Mina 1', '45251297'),
    EmergencyEntry('مفوضية الميناء 2', 'Commissariat El Mina 2', '45242524'),
    EmergencyEntry('مفوضية السبخة 1', 'Commissariat Sebkha 1', '45253821'),
    EmergencyEntry('مفوضية السبخة 2', 'Commissariat Sebkha 2', '45242982'),
    EmergencyEntry('مفوضية الرياض 1', 'Commissariat Riyad 1', '45242935'),
    EmergencyEntry('مفوضية الرياض 2', 'Commissariat Riyad 2', '45242950'),
    EmergencyEntry('مفوضية عرفات 1', 'Commissariat Arafat 1', '45251013'),
    EmergencyEntry('مفوضية توجنين 1', 'Commissariat Toujounine 1', '45252930'),
    EmergencyEntry('مفوضية دار النعيم 1', 'Commissariat Dar Naïm 1', '45242956'),
    EmergencyEntry('مفوضية دار النعيم 2', 'Commissariat Dar Naïm 2', '45242938'),
    EmergencyEntry('مفوضية تيارات 1', 'Commissariat Teyarett 1', '45252471'),
    EmergencyEntry('مفوضية تيارات 2', 'Commissariat Teyarett 2', '45242951'),
  ]),
  EmergencySection('مصالح أخرى', 'Autres services', [
    EmergencyEntry('شرطة المطار', "Police de l'aéroport", '45252183'),
    EmergencyEntry('الإدارة العامة للأمن', 'Direction générale de la sûreté', '45252159'),
    EmergencyEntry('الشرطة القضائية', 'Police judiciaire', '45255449'),
  ]),
];

/// Annuaire d'urgence : chaque ligne appelle directement le numéro.
class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({super.key, required this.t});
  final T t;

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final ar = t.lang == 'ar';
    final q = _q.trim().toLowerCase();
    bool match(EmergencyEntry e) =>
        q.isEmpty ||
        e.ar.contains(q) ||
        e.fr.toLowerCase().contains(q) ||
        e.number.contains(q);
    return Scaffold(
      appBar: AppBar(title: Text(t('emergency_dir'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: navy,
              child: ListTile(
                leading: const Icon(Icons.shield, color: gold),
                title: Text(t('call_amane'),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                trailing: ltrText(controlPhoneDisplay,
                    style: const TextStyle(color: Color(0xFFD1A850), fontWeight: FontWeight.w700)),
                onTap: () => openUrl('tel:$controlPhone'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: t('emergency_search'),
              ),
              onChanged: (v) => setState(() => _q = v),
            ),
            for (final s in emergencySections)
              if (s.entries.any(match)) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 18, bottom: 6),
                  child: Text(ar ? s.ar : s.fr,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
                for (final e in s.entries.where(match))
                  Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.phone_in_talk,
                          color: e.number.length <= 3 ? danger : navy),
                      title: Text(ar ? e.ar : e.fr),
                      trailing: ltrText(e.number,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: e.number.length <= 3 ? danger : ink)),
                      onTap: () => openUrl('tel:${e.number}'),
                    ),
                  ),
              ],
          ],
        ),
      ),
    );
  }
}

/// Bouton qui ouvre l'annuaire d'urgence.
Widget emergencyButton(BuildContext context, T t) => OutlinedButton.icon(
      onPressed: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => EmergencyScreen(t: t))),
      icon: const Icon(Icons.contact_phone),
      label: Text(t('emergency_dir')),
    );
