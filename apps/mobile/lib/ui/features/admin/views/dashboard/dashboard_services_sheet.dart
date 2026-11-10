import 'package:flutter/material.dart';

import '../../../../../domain/models/transport_service.dart';
import '../../../../core/app_theme.dart';
import '../../../../core/date_formats.dart';
import '../../../../core/status_styles.dart';

class ServicesListSheet extends StatefulWidget {
  const ServicesListSheet({
    required this.services,
    required this.onViewService,
    required this.onCancelService,
    required this.onAssignService,
    super.key,
  });

  final List<TransportService> services;
  final ValueChanged<TransportService> onViewService;
  final ValueChanged<TransportService> onCancelService;
  final ValueChanged<TransportService> onAssignService;

  @override
  State<ServicesListSheet> createState() => _ServicesListSheetState();
}

class _ServicesListSheetState extends State<ServicesListSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final services = query.isEmpty
        ? widget.services
        : widget.services.where((service) {
            return service.code.toLowerCase().contains(query) ||
                service.destinationAddress.toLowerCase().contains(query) ||
                (service.driverName ?? '').toLowerCase().contains(query) ||
                (service.vehiclePlate ?? '').toLowerCase().contains(query);
          }).toList();

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.82,
      child: ColoredBox(
        color: appWhite,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // La barra de arrastre la dibuja showAppBottomSheet; dibujarla
                // aquí también dejaba dos, una encima de la otra.
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Servicios',
                            style: TextStyle(
                              color: appBlack,
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${widget.services.length} registrados',
                            style: const TextStyle(
                              color: Color(0xFF666662),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      onPressed: () => Navigator.of(context).maybePop(),
                      style: IconButton.styleFrom(
                        foregroundColor: appBlack,
                        minimumSize: const Size.square(48),
                      ),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _query = value),
                  cursorColor: appBlack,
                  style: const TextStyle(
                    color: appBlack,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Buscar por código, destino, driver o placa',
                    hintStyle: const TextStyle(color: Color(0xFF777773)),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: appBlack,
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF0F0EC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: const BorderSide(color: appBlack, width: 1.4),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: services.isEmpty
                      ? const Center(
                          child: Text(
                            'No se encontraron servicios',
                            style: TextStyle(
                              color: Color(0xFF666662),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        )
                      : ListView.separated(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          itemCount: services.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final service = services[index];
                            final canCancel = !const {
                              'FINALIZADO',
                              'CANCELADO',
                            }.contains(service.currentStatus);
                            final canAssign =
                                const {
                                  'PROGRAMADO',
                                  'BUSCANDO_CONDUCTOR',
                                  'SEARCHING',
                                }.contains(service.normalizedStatus) &&
                                service.assignment?.driverId == null &&
                                service.driverName == null;
                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF0F0EC),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFFE3E3DE),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.route_rounded,
                                          color: appBlack,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              service.code,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: appBlack,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                            Text(
                                              '${formatDateTime(service.scheduledAt)} · '
                                              '${statusLabel(service.currentStatus)}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Color(0xFF666662),
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        tooltip: 'Ver servicio',
                                        onPressed: () =>
                                            widget.onViewService(service),
                                        padding: const EdgeInsets.all(5),
                                        constraints:
                                            const BoxConstraints.tightFor(
                                              width: 48,
                                              height: 48,
                                            ),
                                        icon: Container(
                                          width: 38,
                                          height: 38,
                                          decoration: const BoxDecoration(
                                            color: appLime,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.visibility_outlined,
                                            color: appBlack,
                                            size: 20,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 2),
                                      IconButton(
                                        tooltip: canCancel
                                            ? 'Cancelar servicio'
                                            : 'Servicio finalizado',
                                        onPressed: canCancel
                                            ? () => widget.onCancelService(
                                                service,
                                              )
                                            : null,
                                        padding: const EdgeInsets.all(5),
                                        constraints:
                                            const BoxConstraints.tightFor(
                                              width: 48,
                                              height: 48,
                                            ),
                                        icon: Container(
                                          width: 38,
                                          height: 38,
                                          decoration: BoxDecoration(
                                            color: canCancel
                                                ? appBlack
                                                : const Color(0xFFD2D2CE),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            canCancel
                                                ? Icons.close_rounded
                                                : Icons.check_rounded,
                                            color: canCancel
                                                ? appWhite
                                                : const Color(0xFF777773),
                                            size: 20,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (canAssign) ...[
                                    const SizedBox(height: 10),
                                    SizedBox(
                                      width: double.infinity,
                                      child: TextButton.icon(
                                        onPressed: () =>
                                            widget.onAssignService(service),
                                        style: TextButton.styleFrom(
                                          backgroundColor: appBlack,
                                          foregroundColor: appWhite,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                        ),
                                        icon: const Icon(
                                          Icons.person_add_alt_1_rounded,
                                          size: 20,
                                        ),
                                        label: const Text(
                                          'Asignar',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
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
