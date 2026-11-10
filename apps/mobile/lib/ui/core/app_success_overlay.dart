import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'app_theme.dart';

Future<void> showAppSuccessOverlay(
  BuildContext context, {
  required String title,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    builder: (dialogContext) {
      Future<void>.delayed(const Duration(milliseconds: 2200), () {
        if (dialogContext.mounted) Navigator.of(dialogContext).pop();
      });
      return _AppSuccessOverlay(title: title);
    },
  );
}

class _AppSuccessOverlay extends StatelessWidget {
  const _AppSuccessOverlay({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.55),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 104,
                  height: 104,
                  decoration: const BoxDecoration(
                    color: appLime,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: appWhite,
                    size: 60,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  title,
                  style: const TextStyle(
                    color: appWhite,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
