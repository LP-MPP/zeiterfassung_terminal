import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options.dart';
import 'ui/app_theme.dart';
import 'ui/screens/terminal_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('de_DE', null);

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Immersive / Fullscreen (Android: hide nav + status bars)
  await SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.immersiveSticky,
  );

  // Optional: force portrait (comment out if you want rotation)
  // await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final auth = FirebaseAuth.instance;
  if (auth.currentUser == null) {
    await auth.signInAnonymously();
  } else {
    await auth.currentUser!.getIdToken(true);
  }

  runApp(const TimeTerminalApp());
}

class TimeTerminalApp extends StatelessWidget {
  const TimeTerminalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zeiterfassung Terminal',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const TerminalShell(),
    );
  }
}