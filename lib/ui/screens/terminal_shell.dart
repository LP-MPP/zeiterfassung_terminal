import 'package:flutter/material.dart';

import 'punch_screen.dart';
// Admin panel moved to React web app: https://zeiterfassung-admin.vercel.app
// import 'admin_login_screen.dart';

class TerminalShell extends StatelessWidget {
  const TerminalShell({super.key});

  @override
  Widget build(BuildContext context) {
    // Admin hotspot removed — admin panel is now a separate React web app
    return const PunchScreen();
  }
}
