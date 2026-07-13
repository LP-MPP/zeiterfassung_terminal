import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// A placeholder for empty lists/sections.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTokens.primarySubtle,
              ),
              child: Icon(icon, size: 30, color: AppTokens.onSurfaceFaint),
            ),
            const SizedBox(height: AppTokens.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppTokens.onSurfaceMuted,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: AppTokens.sm),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTokens.onSurfaceFaint,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
