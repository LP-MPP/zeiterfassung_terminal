import 'package:flutter/material.dart';

import 'punch_screen.dart';
import 'admin_login_screen.dart';

class TerminalShell extends StatelessWidget {
  const TerminalShell({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const PunchScreen(),

        // Hidden admin hotspot (top-left corner)
        Positioned(
          left: 0,
          top: 0,
          width: 140,
          height: 140,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onLongPress: () {
              debugPrint('ADMIN HOTSPOT LONG PRESS');
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AdminLoginScreen()),
              );
            },
            child: const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}