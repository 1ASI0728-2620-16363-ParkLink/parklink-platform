import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../../core/app_theme.dart';

class ControlCenterHeader extends StatelessWidget {
  const ControlCenterHeader({required this.adminName, super.key});

  final String adminName;

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = MediaQuery.sizeOf(context).width < 360
        ? 18.0
        : 24.0;

    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [appWhite, appWhite, Colors.transparent],
        stops: [0, 0.7, 1],
      ).createShader(bounds),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  appBlack.withValues(alpha: 0.98),
                  appBlack.withValues(alpha: 0.94),
                  appBlack.withValues(alpha: 0.72),
                  Colors.transparent,
                ],
                stops: const [0, 0.5, 0.8, 1],
              ),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                10,
                horizontalPadding,
                44,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      'Centro de control',
                      style: Theme.of(context).textTheme.headlineLarge
                          ?.copyWith(
                            color: appWhite,
                            fontSize: 33,
                            fontWeight: FontWeight.w900,
                            height: 1.1,
                          ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Hola, $adminName.',
                    style: const TextStyle(
                      color: appDashboardTextMuted,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DashboardEmptyState extends StatelessWidget {
  const DashboardEmptyState({
    required this.message,
    this.embedded = false,
    super.key,
  });

  final String message;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(embedded ? 14 : 18),
      decoration: BoxDecoration(
        color: embedded ? appDashboardCardSoft : appDashboardCard,
        borderRadius: BorderRadius.circular(28),
        border: embedded ? null : Border.all(color: appDashboardBorder),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.inbox_outlined,
            color: appDashboardTextSubtle,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: appDashboardTextMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class DashboardErrorCard extends StatelessWidget {
  const DashboardErrorCard({
    required this.message,
    required this.onRetry,
    this.expanded = false,
    super.key,
  });

  final String message;
  final Future<void> Function() onRetry;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final retryButton = TextButton.icon(
      onPressed: onRetry,
      style: TextButton.styleFrom(
        foregroundColor: appLime,
        minimumSize: const Size(0, 48),
      ),
      icon: const Icon(Icons.refresh_rounded),
      label: const Text('Reintentar'),
    );

    if (expanded) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: _cardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: appDashboardCardSoft,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.cloud_off_outlined, color: appWhite),
            ),
            const SizedBox(height: 20),
            Text(
              'No pudimos cargar el panel',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: const TextStyle(color: appDashboardTextMuted, height: 1.4),
            ),
            const SizedBox(height: 12),
            retryButton,
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < 340 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.25;
        final messageRow = Row(
          children: [
            const SizedBox(
              width: 48,
              height: 48,
              child: Icon(Icons.cloud_off_outlined, color: appWhite),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                maxLines: compact ? 4 : 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: appDashboardTextMuted),
              ),
            ),
          ],
        );

        return Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
          decoration: BoxDecoration(
            color: appDashboardCard,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: appDashboardBorder),
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [messageRow, retryButton],
                )
              : Row(
                  children: [
                    Expanded(child: messageRow),
                    retryButton,
                  ],
                ),
        );
      },
    );
  }
}

BoxDecoration _cardDecoration() {
  return BoxDecoration(
    color: appDashboardCard,
    borderRadius: BorderRadius.circular(30),
    border: Border.all(color: appDashboardBorder),
  );
}
