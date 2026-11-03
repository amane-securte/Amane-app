import 'package:flutter/material.dart';

/// Couleurs de l'identité AMANE : bleu nuit et or sur fond crème.
const navy = Color(0xFF0F2A40);
const gold = Color(0xFFA9812F);
const cream = Color(0xFFF7F2E7);
const paper = Color(0xFFFFFCF5);
const ink = Color(0xFF0E2234);
const muted = Color(0xFF5C6670);
const danger = Color(0xFFBF3328);
const okGreen = Color(0xFF1D7F48);
const warn = Color(0xFFB25A00);

/// Numéro de réception des alertes SOS.
const controlPhone = '+22226511010';
const controlPhoneDisplay = '+222 26 51 10 10';

ThemeData amaneTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: navy,
    primary: navy,
    secondary: gold,
    surface: paper,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: cream,
    appBarTheme: const AppBarTheme(
      backgroundColor: navy,
      foregroundColor: Color(0xFFFBF6EA),
      centerTitle: false,
    ),
    cardTheme: const CardThemeData(
      color: paper,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        side: BorderSide(color: Color(0xFFDBD1BA)),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      filled: true,
      fillColor: paper,
    ),
  );
}
