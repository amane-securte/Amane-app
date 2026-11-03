# Clé de signature AMANE

`amane-upload.p12` signe les versions de l'application (clé d'importation Google Play).
Le fichier est inutilisable sans son mot de passe, conservé uniquement dans le secret
GitHub **AMANE_KEY_PASSWORD** (Settings → Secrets and variables → Actions).

Ne jamais publier ce mot de passe. En cas de perte, la clé d'importation peut être
réinitialisée depuis la Play Console (Intégrité de l'application → Signature de l'application).
