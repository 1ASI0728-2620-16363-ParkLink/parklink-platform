import 'package:flutter/material.dart';

import '../../../../../domain/models/admin_records.dart';
import '../../../../core/app_theme.dart';

class QuickAccessGrid extends StatelessWidget {
  const QuickAccessGrid({
    required this.drivers,
    required this.activeServices,
    required this.completedServices,
    required this.cancelledServices,
    required this.onOpenDrivers,
    this.onInviteDriver,
    super.key,
  });

  final List<DriverRecord> drivers;
  final int activeServices;
  final int completedServices;
  final int cancelledServices;
  final VoidCallback onOpenDrivers;

  /// Ausente para el observador: no invita conductores.
  final VoidCallback? onInviteDriver;

  @override
  Widget build(BuildContext context) {
    final operability = _operabilityPercentage(
      drivers: drivers,
      activeServices: activeServices,
      completedServices: completedServices,
      cancelledServices: cancelledServices,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 340 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.3;
        final driverCardWidth = (constraints.maxWidth - 20) * 5 / 11;
        final avatarWidth =
            ((stacked ? constraints.maxWidth : driverCardWidth) - 92)
                .clamp(28.0, 76.0)
                .toDouble();
        final driversCard = _DriversQuickCard(
          drivers: drivers,
          avatarWidth: avatarWidth,
          onOpenDrivers: onOpenDrivers,
          onInviteDriver: onInviteDriver,
        );
        final servicesCard = _ServicesQuickCard(
          active: activeServices,
          completed: completedServices,
          cancelled: cancelledServices,
          operability: operability,
        );

        if (stacked) {
          return Column(
            children: [driversCard, const SizedBox(height: 12), servicesCard],
          );
        }

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 5,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: driversCard,
                ),
              ),
              const SizedBox(width: 20),
              Expanded(flex: 6, child: servicesCard),
            ],
          ),
        );
      },
    );
  }
}

class _DriversQuickCard extends StatelessWidget {
  const _DriversQuickCard({
    required this.drivers,
    required this.avatarWidth,
    required this.onOpenDrivers,
    this.onInviteDriver,
  });

  final List<DriverRecord> drivers;
  final double avatarWidth;
  final VoidCallback onOpenDrivers;
  final VoidCallback? onInviteDriver;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: '${drivers.length} drivers registrados',
      child: Material(
        color: appDashboardCard,
        shape: _quickCardShape(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpenDrivers,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 220),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    alignment: Alignment.centerLeft,
                    fit: BoxFit.scaleDown,
                    child: _ExtraBoldNumber(
                      value: '${drivers.length}',
                      color: appLime,
                      fontSize: 88,
                      height: 0.9,
                      strokeWidth: 1.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Drivers',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: drivers.isEmpty
                              ? const Text(
                                  'Sin registros',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: appDashboardLight,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                )
                              : _InitialAvatarStack(
                                  drivers: drivers,
                                  width: avatarWidth,
                                ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      // Sin invitación para el observador.
                      if (onInviteDriver != null)
                        Semantics(
                          button: true,
                          label: 'Invitar driver',
                          child: Tooltip(
                            message: 'Mandar invitación',
                            child: SizedBox.square(
                              dimension: 48,
                              child: IconButton(
                                onPressed: onInviteDriver,
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints.expand(),
                                style: IconButton.styleFrom(
                                  shape: const CircleBorder(),
                                ),
                                icon: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: const BoxDecoration(
                                    color: appLime,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.add_rounded,
                                    color: appBlack,
                                    size: 25,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
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

class _ServicesQuickCard extends StatelessWidget {
  const _ServicesQuickCard({
    required this.active,
    required this.completed,
    required this.cancelled,
    required this.operability,
  });

  final int active;
  final int completed;
  final int cancelled;
  final int operability;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          '$active activos, $completed completados, '
          '$cancelled cancelados. Nivel de operatividad: '
          '$operability por ciento.',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Expanded(
                  child: _ServiceMetric(
                    value: active,
                    label: 'Activos',
                    accented: true,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ServiceMetric(value: completed, label: 'Completados'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _ServiceMetric(value: cancelled, label: 'Cancelados'),
                ),
                const SizedBox(width: 8),
                Expanded(child: _OperabilityRing(percentage: operability)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

int _operabilityPercentage({
  required List<DriverRecord> drivers,
  required int activeServices,
  required int completedServices,
  required int cancelledServices,
}) {
  final scores = <double>[];
  if (drivers.isNotEmpty) {
    const operationalStatuses = {
      'DISPONIBLE',
      'RESERVADO',
      'ASIGNADO',
      'EN_SERVICIO',
    };
    final operationalDrivers = drivers.where((driver) {
      return operationalStatuses.contains(driver.normalizedAvailabilityStatus);
    }).length;
    scores.add(operationalDrivers / drivers.length);
  }

  final serviceTotal = activeServices + completedServices + cancelledServices;
  if (serviceTotal > 0) {
    scores.add((activeServices + completedServices) / serviceTotal);
  }

  if (scores.isEmpty) return 0;
  final average =
      scores.reduce((total, score) => total + score) / scores.length;
  return (average * 100).round().clamp(0, 100).toInt();
}

class _ExtraBoldNumber extends StatelessWidget {
  const _ExtraBoldNumber({
    required this.value,
    required this.color,
    required this.fontSize,
    this.height,
    this.strokeWidth = 1,
  });

  final String value;
  final Color color;
  final double fontSize;
  final double? height;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: color,
      fontSize: fontSize,
      fontWeight: FontWeight.w900,
      height: height,
    );

    return Stack(
      alignment: Alignment.center,
      children: [
        ExcludeSemantics(
          child: Text(
            value,
            style: style.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = strokeWidth
                ..color = color,
            ),
          ),
        ),
        Text(value, style: style),
      ],
    );
  }
}

class _ServiceMetric extends StatelessWidget {
  const _ServiceMetric({
    required this.value,
    required this.label,
    this.accented = false,
  });

  final int value;
  final String label;
  final bool accented;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $value',
      child: Column(
        children: [
          Container(
            width: 84,
            height: 84,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accented ? appLime : appDashboardCardSoft,
              shape: BoxShape.circle,
              border: Border.all(
                color: accented ? appLime : appDashboardBorder,
                width: 2,
              ),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: _ExtraBoldNumber(
                value: '$value',
                color: accented ? appBlack : appWhite,
                fontSize: 36,
                strokeWidth: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 28,
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: appDashboardTextMuted,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OperabilityRing extends StatelessWidget {
  const _OperabilityRing({required this.percentage});

  final int percentage;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Operatividad: $percentage por ciento',
      child: SizedBox(
        width: 88,
        child: Column(
          children: [
            SizedBox.square(
              dimension: 84,
              child: Center(
                child: SizedBox.square(
                  dimension: 70,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: CircularProgressIndicator(
                          value: percentage / 100,
                          strokeWidth: 8,
                          strokeCap: StrokeCap.round,
                          color: appLime,
                          backgroundColor: appDashboardTrack,
                        ),
                      ),
                      _ExtraBoldNumber(
                        value: '$percentage%',
                        color: appWhite,
                        fontSize: 17,
                        strokeWidth: 0.7,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            const SizedBox(
              height: 28,
              child: Text(
                'Operatividad',
                maxLines: 1,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: appDashboardTextMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InitialAvatarStack extends StatelessWidget {
  const _InitialAvatarStack({required this.drivers, required this.width});

  final List<DriverRecord> drivers;
  final double width;

  @override
  Widget build(BuildContext context) {
    final visibleDrivers = drivers.take(width < 35 ? 1 : (width < 52 ? 2 : 4));
    final driverList = visibleDrivers.toList();
    const avatarSize = 40.0;
    final step =
        (driverList.length <= 1
                ? 0.0
                : ((width - avatarSize) / (driverList.length - 1)).clamp(
                    7.0,
                    15.0,
                  ))
            .toDouble();
    final stackWidth = avatarSize + step * (driverList.length - 1);

    return SizedBox(
      width: stackWidth,
      height: avatarSize,
      child: Stack(
        children: [
          for (var index = 0; index < driverList.length; index++)
            Positioned(
              left: index * step,
              child: Container(
                width: avatarSize,
                height: avatarSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: index.isEven
                      ? appDashboardTextSubtle
                      : appDashboardTrack,
                  shape: BoxShape.circle,
                  border: Border.all(color: appDashboardBorder, width: 2),
                ),
                child: Text(
                  _initials(driverList[index].fullName),
                  style: const TextStyle(
                    color: appWhite,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

RoundedRectangleBorder _quickCardShape() {
  return RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(30),
    side: const BorderSide(color: appDashboardBorder),
  );
}

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '—';

  String firstCharacter(String value) => String.fromCharCode(value.runes.first);
  final first = firstCharacter(parts.first);
  final last = parts.length > 1 ? firstCharacter(parts.last) : '';
  return '$first$last'.toUpperCase();
}
