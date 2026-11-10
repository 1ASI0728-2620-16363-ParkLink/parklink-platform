import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../domain/models/parking_space.dart';
import '../../../core/app_theme.dart';

String parkingMoney(Object? cents) =>
    'S/ ${(num.parse('$cents') / 100).toStringAsFixed(2)}';
String parkingDistance(double meters) => meters < 1000
    ? '${meters.round()} m'
    : '${(meters / 1000).toStringAsFixed(1)} km';

class ParkingControl extends StatelessWidget {
  const ParkingControl({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.primary = false,
    this.busy = false,
    this.size = 56,
    super.key,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool primary, busy;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: IconButton.filled(
      tooltip: label,
      onPressed: busy || onPressed == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onPressed!();
            },
      style: IconButton.styleFrom(
        backgroundColor: primary ? appLime : appWhite,
        disabledBackgroundColor: primary ? appLime : appWhite,
        foregroundColor: appBlack,
        disabledForegroundColor: appBlack,
        shape: const CircleBorder(),
        elevation: 3,
        shadowColor: Colors.black26,
      ),
      icon: busy
          ? const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2, color: appBlack),
            )
          : Icon(icon, size: 25),
    ),
  );
}

class ParkingSectionTitle extends StatelessWidget {
  const ParkingSectionTitle(
    this.title, {
    this.subtitle,
    this.trailing,
    super.key,
  });
  final String title;
  final String? subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            ?trailing,
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(
            subtitle!,
            style: const TextStyle(color: appDashboardTextMuted, height: 1.5),
          ),
        ],
      ],
    ),
  );
}

class ParkingEmptyState extends StatelessWidget {
  const ParkingEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    super.key,
  });
  final IconData icon;
  final String title, message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32),
    child: Column(
      children: [
        Icon(
          icon,
          size: 32,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        if (action != null) ...[const SizedBox(height: 24), action!],
      ],
    ),
  );
}

class ParkingPhoto extends StatelessWidget {
  const ParkingPhoto({
    required this.space,
    this.width,
    this.height = 160,
    super.key,
  });
  final ParkingSpace space;
  final double? width;
  final double height;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(20),
    child: SizedBox(
      width: width,
      height: height,
      child: space.photoUrl == null
          ? _placeholder()
          : Image.network(
              space.photoUrl!,
              fit: BoxFit.cover,
              semanticLabel: 'Fotografía de ${space.title}',
              loadingBuilder: (context, child, progress) => progress == null
                  ? child
                  : const ColoredBox(
                      color: Color(0xFFF2F3F3),
                      child: Center(
                        child: SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: appBlack,
                          ),
                        ),
                      ),
                    ),
              errorBuilder: (_, _, _) => _placeholder(),
            ),
    ),
  );
  Widget _placeholder() => const ColoredBox(
    color: Color(0xFFF2F3F3),
    child: Center(
      child: Padding(
        padding: EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.local_parking_outlined,
              color: Color(0xFF727979),
              size: 28,
            ),
            SizedBox(height: 8),
            Text(
              'Sin foto',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF5C6464), fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
}

class ParkingResultCard extends StatelessWidget {
  const ParkingResultCard({
    required this.space,
    required this.onReserve,
    this.fromDevice = true,
    this.verified = false,
    this.distanceMeters,
    super.key,
  });
  final ParkingSpace space;
  final VoidCallback onReserve;
  final bool fromDevice, verified;
  final double? distanceMeters;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final distance = distanceMeters ?? space.distanceMeters;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ParkingPhoto(
                space: space,
                width: (constraints.maxWidth * .30).clamp(64, 144),
                height: 176,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      space.title,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                        color: appBlack,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      space.address,
                      style: const TextStyle(
                        color: Color(0xFF5C6464),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    if (distance != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        '${parkingDistance(distance)} ${fromDevice ? 'de ti' : 'del punto del mapa'}',
                        style: const TextStyle(
                          color: Color(0xFF5C6464),
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      '${parkingMoney(space.hourlyRate)} / hora',
                      style: const TextStyle(
                        color: appBlack,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      verified
                          ? 'Disponible · 1 hora'
                          : 'Disponibilidad al reservar',
                      style: const TextStyle(
                        color: Color(0xFF375A55),
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              onReserve();
            },
            child: const Text('Reservar'),
          ),
        ],
      );
    },
  );
}

class ParkingNotice extends StatelessWidget {
  const ParkingNotice(this.message, {this.onRetry, super.key});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(message),
          if (onRetry != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onRetry,
                child: const Text('Reintentar'),
              ),
            ),
        ],
      ),
    ),
  );
}
