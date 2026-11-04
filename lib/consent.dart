import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'data.dart';
import 'i18n.dart';
import 'theme.dart';
import 'widgets.dart';

/// Version du texte de consentement : l'augmenter oblige chacun à accepter
/// de nouveau à sa prochaine connexion.
const consentVersion = 1;

/// Un paragraphe du consentement : titre + lignes.
typedef ConsentPart = (String title, List<String> lines);

const _staffAr = <ConsentPart>[
  ('1. الغرض', ['يُستعمل التطبيق في تنظيم العمل وسلامة الموظفين والزبائن: الحضور والانصراف، والنجدة السريعة، والسجل اليومي، والرواتب.']),
  ('2. البيانات المجمّعة', [
    'الموقع (GPS) عند الحضور والانصراف، وطوال المناوبة فقط، وعند إنذار SOS، مع إشعار ظاهر. لا يُجمع الموقع خارج أوقات العمل.',
    'الصور التي يلتقطها الموظف بنفسه دليلًا في السجل اليومي.',
    'السجل اليومي، وبيانات الحساب والعمل: الاسم، الهاتف، الوظيفة، ساعات العمل، الراتب والسلف والخصومات.',
  ]),
  ('3. من يطّلع عليها', [
    'إدارة أمان وغرفة العمليات.',
    'زبون الموقع: الحراس في موقعه وسجل موقعه فقط، دون الرواتب.',
    'الزملاء في نفس الموقع: سجل الموقع.',
    'الشرطة والدرك والحماية المدنية عند الخطر فقط.',
    'لا تُباع البيانات، وتُستضاف لدى Google Firebase باتصال مشفّر.',
  ]),
  ('4. مدة الحفظ', ['طوال العقد، ثم حتى 5 سنوات للالتزامات المحاسبية والقانونية.']),
  ('5. التزامات الموظف', [
    'تسجيل الحضور والانصراف في كل مناوبة، وعدم إيقاف إذن الموقع أثناء العمل.',
    'عدم مشاركة رقم الدخول وكلمة السر.',
    'الحفاظ على سرية السجل والصور والتعليمات، واستعمال SOS للحالات الحقيقية فقط.',
  ]),
  ('6. الحقوق', ['الاطلاع على البيانات وتصحيحها وطلب حذفها بعد انتهاء العقد في حدود مدة الحفظ: amane.services.securite@gmail.com']),
];

const _staffFr = <ConsentPart>[
  ('1. Objet', ["L'application sert à organiser le travail et à assurer la sécurité des employés et des clients : pointage, secours rapides, main courante, paie."]),
  ('2. Données collectées', [
    "Localisation (GPS) au pointage, pendant la mission uniquement et lors d'une alerte SOS, avec notification visible. Aucune localisation hors des heures de travail.",
    "Photos prises par l'employé lui-même comme preuve dans la main courante.",
    'Main courante, données de compte et de travail : nom, téléphone, poste, heures, salaire, avances et retenues.',
  ]),
  ('3. Qui les consulte', [
    "L'administration d'AMANE et la salle de contrôle.",
    'Le client du site : agents de son site et main courante de ce site, jamais la paie.',
    'Les collègues du même site : main courante du site.',
    'Police, gendarmerie, protection civile : en cas de danger seulement.',
    'Données ni vendues ni cédées ; hébergées par Google Firebase, connexion chiffrée.',
  ]),
  ('4. Conservation', ["Pendant le contrat, puis jusqu'à 5 ans pour les obligations comptables et légales."]),
  ("5. Engagements de l'employé", [
    'Pointer à chaque mission, sans désactiver la localisation pendant le service.',
    'Ne communiquer ni son identifiant ni son mot de passe.',
    'Garder confidentiels la main courante, les photos et les consignes ; SOS pour de vraies urgences.',
  ]),
  ('6. Droits', ['Accès, correction et suppression après le contrat dans la limite légale : amane.services.securite@gmail.com']),
];

const _clientAr = <ConsentPart>[
  ('1. الخدمات في التطبيق', ['زر SOS مع الموقع ومتابعة الطلب، ومتابعة الحراس والسجل اليومي، والتقارير والفواتير، والتعليمات والرسائل والتقييم وطلب الخدمات.']),
  ('2. حدود زر SOS', [
    'لا يُغني عن الاتصال المباشر بالشرطة 117 أو المطافئ 118 أو الدرك 116 في الخطر الداهم.',
    'يحتاج الإنترنت والموقع؛ عند انقطاع الشبكة يُقترح إرسال SMS.',
    'خارج نواكشوط تنسّق أمان مع السلطات المحلية ولا تضمن دورية خاصة إلا إذا نصّ العقد على ذلك.',
    'يُستعمل للحالات الحقيقية فقط.',
  ]),
  ('3. البيانات والسرية', [
    'يجمع التطبيق: الاسم والهاتف، وموقع الحراسة، والموقع الجغرافي عند SOS فقط، والرسائل والتقييمات.',
    'يرى الزبون موقعه فقط. السجل اليومي والتعليمات سرية بين أمان والزبون وحراس الموقع، ولا تُنشر خارج التطبيق.',
    'لا تُباع البيانات، وتُستضاف لدى Google Firebase باتصال مشفّر.',
  ]),
  ('4. تعليمات الموقع', ['يقترحها الزبون، ولا تصبح نافذة إلا بعد موافقة أمان التي لها تعديلها أو رفضها. التعليمات المقبولة في التطبيق هي مرجع الحراس.']),
  ('5. التزامات الزبون', ['سرية رقم الدخول وكلمة السر، وإبلاغ أمان بأي خطر أو تغيير، واحترام كرامة الحراس والتقييم بموضوعية.']),
  ('6. الحقوق', ['الاطلاع على البيانات وتصحيحها وحذف الحساب عند انتهاء العقد، مع حفظ ما يفرضه القانون: amane.services.securite@gmail.com']),
];

const _clientFr = <ConsentPart>[
  ("1. Services de l'application", ['Bouton SOS avec position et suivi, agents en service et main courante, rapports et factures, consignes, messages, évaluation et demandes de prestations.']),
  ('2. Limites du bouton SOS', [
    "Il ne remplace pas l'appel direct à la police (117), aux pompiers (118) ou à la gendarmerie (116) en cas de danger immédiat.",
    "Il nécessite Internet et la localisation ; sans réseau, l'envoi par SMS est proposé.",
    "Hors de Nouakchott, AMANE se coordonne avec les autorités locales et ne garantit pas sa propre patrouille, sauf clause du contrat.",
    'À utiliser uniquement en cas réel.',
  ]),
  ('3. Données et confidentialité', [
    "Collectées : nom, téléphone, site protégé, position lors d'une alerte SOS seulement, messages et évaluations.",
    "Le client ne voit que son site. Main courante et consignes sont confidentielles entre AMANE, le client et les agents du site, et ne sont pas diffusées hors de l'application.",
    'Données ni vendues ni cédées ; hébergées par Google Firebase, connexion chiffrée.',
  ]),
  ('4. Consignes du site', ["Proposées par le client, elles ne s'appliquent qu'après validation par AMANE, qui peut les modifier ou les refuser. Les consignes validées dans l'application font foi pour les agents."]),
  ('5. Engagements du client', ['Confidentialité des identifiants, information d\'AMANE en cas de risque ou de changement, respect des agents et évaluation objective.']),
  ('6. Droits', ['Accès, correction et suppression du compte en fin de contrat, sous réserve des pièces à conserver légalement : amane.services.securite@gmail.com']),
];

List<ConsentPart> consentText({required bool client, required String lang}) => client
    ? (lang == 'fr' ? _clientFr : _clientAr)
    : (lang == 'fr' ? _staffFr : _staffAr);

/// Pour le PDF (toujours bilingue).
List<ConsentPart> consentTextAr(bool client) => client ? _clientAr : _staffAr;
List<ConsentPart> consentTextFr(bool client) => client ? _clientFr : _staffFr;

/// Tous les employés (agents, chauffeurs, comptables, directeurs…) et tous
/// les clients acceptent ; seul le compte du gérant en est dispensé.
bool needsConsent(Map<String, dynamic> m, {bool owner = false}) {
  if (owner) return false;
  final role = m['role'];
  if (role != 'guard' && role != 'client' && role != 'admin') return false;
  final v = m['consentVer'];
  return v is! num || v < consentVersion;
}

/// Écran d'acceptation affiché avant d'utiliser l'application.
class ConsentScreen extends StatefulWidget {
  const ConsentScreen({super.key, required this.prefs, required this.me});
  final Prefs prefs;
  final UserDoc me;
  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  var _ok = false;
  var _busy = false;

  @override
  Widget build(BuildContext context) {
    final t = T(widget.prefs.lang);
    final client = widget.me.role == 'client';
    final parts = consentText(client: client, lang: widget.prefs.lang);
    return Scaffold(
      appBar: amaneAppBar(context, widget.prefs),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(t(client ? 'consent_title_client' : 'consent_title_staff'),
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: navy)),
                const SizedBox(height: 4),
                Text(t('consent_intro', {'n': widget.me.name}), style: const TextStyle(color: muted)),
                const SizedBox(height: 10),
                for (final p in parts) ...[
                  Text(p.$1, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  for (final l in p.$2)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 8, top: 3),
                      child: Text('• $l'),
                    ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
            decoration: const BoxDecoration(
              color: Color(0xFFFFFCF5),
              border: Border(top: BorderSide(color: Color(0xFFDBD1BA))),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              CheckboxListTile(
                value: _ok,
                onChanged: (v) => setState(() => _ok = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: Text(t('consent_check')),
              ),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: !_ok || _busy
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        try {
                          await db.collection('users').doc(widget.me.id).update({
                            'consentVer': consentVersion,
                            'consentAt': Timestamp.now(),
                            'consentLang': widget.prefs.lang,
                          });
                        } catch (e) {
                          if (context.mounted) {
                            snack(context, t('err_generic', {'e': '$e'}), color: danger);
                          }
                          if (mounted) setState(() => _busy = false);
                        }
                      },
                child: Text(t('consent_accept')),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
