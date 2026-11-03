import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'home.dart';
import 'setup.dart';
import 'store.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final app = AppState();
  await app.load();
  runApp(AmaneApp(app: app));
}

class AmaneApp extends StatelessWidget {
  const AmaneApp({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => MaterialApp(
        title: 'Amane',
        debugShowCheckedModeBanner: false,
        theme: amaneTheme(),
        locale: Locale(app.lang),
        supportedLocales: const [Locale('ar'), Locale('fr')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: app.configured
            ? HomeScreen(app: app)
            : SetupScreen(app: app, first: true),
      ),
    );
  }
}
