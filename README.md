# Amane-app

Application mobile de la société **AMANE Sécurité privée** (أمان للأمن الخصوصي).

## Version actuelle : application de l'agent (test)

- Inscription de l'agent : nom, téléphone, site de travail et coordonnées GPS du site
- Prise et fin de service avec position GPS, comparée au rayon autorisé du site
- Bouton **SOS** : type d'alerte, position GPS, message prêt vers la salle de contrôle (+222 26 51 10 10)
- Appel direct de la salle de contrôle
- Historique des dernières missions
- Interface en arabe et en français

Les données restent pour l'instant sur le téléphone. La prochaine étape relie l'application
au serveur Firebase (connexion des agents, tableau de bord de l'administrateur, envoi automatique des alertes).

## Télécharger la version de test

Chaque modification envoyée sur `main` construit automatiquement l'APK
(onglet **Actions**). Le fichier `Amane.apk` est publié dans **Releases → test-build**.

## Structure

| Fichier | Rôle |
|---|---|
| `lib/main.dart` | Démarrage, langue, thème |
| `lib/home.dart` | Écran principal : pointage, SOS, historique |
| `lib/setup.dart` | Inscription et réglages |
| `lib/store.dart` | Données enregistrées sur le téléphone |
| `lib/geo.dart` | Localisation GPS |
| `lib/i18n.dart` | Textes arabe / français |
| `tool/patch_android.py` | Réglages Android (nom, permissions, identifiant `mr.amane.securite`) |
| `.github/workflows/android.yml` | Construction automatique de l'APK |
