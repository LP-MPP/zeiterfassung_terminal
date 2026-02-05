import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'firebase_options.dart';
import 'ui/app_theme.dart';
import 'ui/screens/terminal_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('de_DE', null);

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 🔴 WICHTIG: Web-Admin → KEIN Offline Cache
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: false,
  );

  runApp(const TimeTerminalApp());
}

class TimeTerminalApp extends StatelessWidget {
  const TimeTerminalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zeiterfassung Terminal (Web)',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const TerminalShell(),
    );
  }
}