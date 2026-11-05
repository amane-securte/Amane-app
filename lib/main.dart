import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'accounting.dart';
import 'admin_home.dart';
import 'auth_screen.dart';
import 'client_home.dart';
import 'consent.dart';
import 'data.dart';
import 'guard_home.dart';
import 'i18n.dart';
import 'push.dart';
import 'theme.dart';
import 'widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: firebaseOptions);
  final prefs = Prefs();
  await prefs.load();
  runApp(AmaneApp(prefs: prefs));
}

class AmaneApp extends StatelessWidget {
  const AmaneApp({super.key, required this.prefs});
  final Prefs prefs;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) => MaterialApp(
        title: 'Amane',
        debugShowCheckedModeBanner: false,
        theme: amaneTheme(),
        locale: Locale(prefs.lang),
        supportedLocales: const [Locale('ar'), Locale('fr')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const LoadingScreen();
            }
            final user = snap.data;
            if (user == null) return AuthScreen(prefs: prefs);
            return RoleGate(prefs: prefs, user: user);
          },
        ),
      ),
    );
  }
}

/// Choisit l'écran selon le rôle enregistré dans users/{uid}.
class RoleGate extends StatelessWidget {
  const RoleGate({super.key, required this.prefs, required this.user});
  final Prefs prefs;
  final User user;

  @override
  Widget build(BuildContext context) {
    final isOwner = user.email == ownerEmail;
    return StreamBuilder<DocumentSnapshotMap>(
      stream: db.collection('users').doc(user.uid).snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          // Le plus souvent : règles Firestore pas encore publiées.
          return PendingScreen(prefs: prefs, disabled: false, error: '${snap.error}');
        }
        if (!snap.hasData) return const LoadingScreen();
        final doc = snap.data!;
        final me = UserDoc(user.uid, doc.data() ?? const {});
        if (!doc.exists && isOwner) {
          // Premier lancement du gérant : on crée son profil administrateur.
          db.collection('users').doc(user.uid).set({
            'name': user.displayName ?? 'Admin',
            'phone': '',
            'role': 'admin',
            'createdAt': Timestamp.now(),
          });
          return const LoadingScreen();
        }
        if (doc.exists && me.role != 'pending' && me.role != 'disabled') {
          Push.register(user.uid);
        }
        if (doc.exists && needsConsent(doc.data() ?? const {}, owner: isOwner)) {
          return ConsentScreen(prefs: prefs, me: me);
        }
        if (!isOwner && me.role == 'admin' && me.job == 'accountant') {
          return AccountantHome(prefs: prefs, me: me);
        }
        if (isOwner || me.role == 'admin') {
          return AdminHome(prefs: prefs, me: me, director: isOwner || me.job != 'operator');
        }
        if (me.role == 'guard') return GuardHome(prefs: prefs, me: me);
        if (me.role == 'client') return ClientHome(prefs: prefs, me: me);
        return PendingScreen(prefs: prefs, disabled: me.role == 'disabled');
      },
    );
  }
}

class PendingScreen extends StatelessWidget {
  const PendingScreen(
      {super.key, required this.prefs, required this.disabled, this.error});
  final Prefs prefs;
  final bool disabled;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final t = T(prefs.lang);
    return Scaffold(
      appBar: amaneAppBar(context, prefs),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(disabled ? Icons.block : Icons.hourglass_top,
                  size: 64, color: disabled ? danger : gold),
              const SizedBox(height: 16),
              Text(disabled ? t('disabled') : t('pending_title'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w600)),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(t('db_error'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: danger)),
                const SizedBox(height: 6),
                Text(error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: muted, fontSize: 11)),
              ] else if (!disabled) ...[
                const SizedBox(height: 8),
                Text(t('pending_sub'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: muted)),
              ],
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () => FirebaseAuth.instance.signOut(),
                icon: const Icon(Icons.logout),
                label: Text(t('logout')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
