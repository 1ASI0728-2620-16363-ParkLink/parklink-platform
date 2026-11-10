import 'package:flutter/material.dart';

import '../../../../../domain/models/transport_service.dart';
import '../../../../core/app_theme.dart';
import '../../../../core/date_formats.dart';
import '../../../../core/status_styles.dart';
import 'dashboard_common.dart';

class ActiveServicesCard extends StatelessWidget {
  const ActiveServicesCard({
    required this.services,
    required this.onOpenServices,
    required this.onServiceTap,
    required this.onDownloadReport,
    super.key,
  });

  final List<TransportService> services;
  final VoidCallback onOpenServices;
  final ValueChanged<TransportService> onServiceTap;
  final VoidCallback onDownloadReport;

  @override
  Widget build(BuildContext context) {
    final visibleServices = services.take(4).toList();

    return Material(
      color: appDashboardCard,
      shape: _cardShape(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpenServices,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Servicios activos',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Próximos servicios programados y en curso',
                            style: TextStyle(
                              color: appDashboardTextMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      key: const Key('download-services-report'),
                      tooltip: 'Descargar reporte PDF',
                      onPressed: onDownloadReport,
                      style: IconButton.styleFrom(
                        backgroundColor: appWhite,
                        foregroundColor: appBlack,
                        minimumSize: const Size.square(48),
                        shape: const CircleBorder(),
                      ),
                      icon: const Icon(Icons.download_rounded, size: 24),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (visibleServices.isEmpty)
                const DashboardEmptyState(
                  message: 'No hay servicios activos.',
                  embedded: true,
                )
              else
                for (
                  var index = 0;
                  index < visibleServices.length;
                  index++
                ) ...[
                  _ActiveServiceRow(
                    service: visibleServices[index],
                    onTap: () => onServiceTap(visibleServices[index]),
                  ),
                  if (index != visibleServices.length - 1)
                    const Divider(
                      height: 1,
                      indent: 64,
                      color: appDashboardBorder,
                    ),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveServiceRow extends StatelessWidget {
  const _ActiveServiceRow({required this.service, required this.onTap});

  final TransportService service;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scaledText = MediaQuery.textScalerOf(context).scale(1) > 1.25;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 390 || scaledText;

        return Semantics(
          button: true,
          label:
              '${service.code}, ${statusLabel(service.currentStatus)}, '
              '${service.destinationAddress}',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(22),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 88),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: appDashboardCardSoft,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.route_rounded,
                          color: appWhite,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${service.code}  ·  ${formatDateTime(service.scheduledAt)}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: appWhite,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              service.destinationAddress,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: appDashboardTextMuted,
                                fontSize: 12,
                                height: 1.3,
                              ),
                            ),
                            if (compact) ...[
                              const SizedBox(height: 7),
                              _ServiceStatus(status: service.currentStatus),
                            ],
                          ],
                        ),
                      ),
                      if (!compact) ...[
                        const SizedBox(width: 12),
                        Flexible(
                          child: _ServiceStatus(
                            status: service.currentStatus,
                            alignEnd: true,
                          ),
                        ),
                      ],
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: appDashboardTextSubtle,
                        size: 24,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ServiceStatus extends StatelessWidget {
  const _ServiceStatus({required this.status, this.alignEnd = false});

  final String status;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: alignEnd
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: appLime,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            statusLabel(status),
            softWrap: true,
            style: const TextStyle(
              color: appLime,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

RoundedRectangleBorder _cardShape() {
  return RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(30),
    side: const BorderSide(color: appDashboardBorder),
  );
}
