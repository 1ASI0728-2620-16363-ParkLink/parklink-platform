import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../../domain/models/admin_records.dart';
import '../../../../core/app_theme.dart';

class DriversListSheet extends StatefulWidget {
  const DriversListSheet({
    required this.drivers,
    this.onToggleDriverStatus,
    this.liveLocations = const [],
    this.onRequestLocation,
    this.requestingDriver,
    super.key,
  });

  final List<DriverRecord> drivers;
  final ValueChanged<DriverRecord>? onToggleDriverStatus;
  final List<DriverLiveLocation> liveLocations;
  final Future<void> Function(DriverRecord driver)? onRequestLocation;
  final bool Function(String driverId)? requestingDriver;

  @override
  State<DriversListSheet> createState() => _DriversListSheetState();
}

class _DriversListSheetState extends State<DriversListSheet> {
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
    final drivers = query.isEmpty
        ? widget.drivers
        : widget.drivers.where((driver) {
            return driver.fullName.toLowerCase().contains(query) ||
                driver.documentNumber.toLowerCase().contains(query) ||
                driver.status.toLowerCase().contains(query);
          }).toList();
    final liveByDriver = {
      for (final location in widget.liveLocations) location.driverId: location,
    };

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.76,
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
                            'Drivers',
                            style: TextStyle(
                              color: appBlack,
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${widget.drivers.length} registrados',
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
                    hintText: 'Buscar por nombre, documento o estado',
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
                const SizedBox(height: 16),
                Expanded(
                  child: drivers.isEmpty
                      ? const Center(
                          child: Text(
                            'No se encontraron drivers',
                            style: TextStyle(
                              color: Color(0xFF666662),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        )
                      : ListView.separated(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          itemCount: drivers.length,
                          separatorBuilder: (_, _) => const Divider(
                            height: 1,
                            color: Color(0xFFE1E1DD),
                          ),
                          itemBuilder: (context, index) {
                            final driver = drivers[index];
                            final isActive =
                                driver.status.toUpperCase() == 'ACTIVE';
                            final live = liveByDriver[driver.id];
                            final requesting =
                                widget.requestingDriver?.call(driver.id) ??
                                false;
                            return ListTile(
                              isThreeLine: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 8,
                              ),
                              leading: Container(
                                width: 48,
                                height: 48,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFE9E9E5),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.person_outline_rounded,
                                  color: appBlack,
                                ),
                              ),
                              title: Text(
                                driver.fullName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: appBlack,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              subtitle: Text(
                                '${driver.documentNumber} · ${driver.status}\n'
                                '${_locationStatus(live)}',
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF666662),
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (driver.phone != null &&
                                      driver.phone!.trim().isNotEmpty)
                                    IconButton(
                                      tooltip: 'Llamar a ${driver.fullName}',
                                      onPressed: () => launchUrl(
                                        Uri(
                                          scheme: 'tel',
                                          path: driver.phone!.trim(),
                                        ),
                                      ),
                                      constraints:
                                          const BoxConstraints.tightFor(
                                            width: 48,
                                            height: 48,
                                          ),
                                      style: IconButton.styleFrom(
                                        backgroundColor: appLime,
                                      ),
                                      icon: const Icon(
                                        Icons.call_rounded,
                                        color: appWhite,
                                      ),
                                    ),
                                  if (widget.onRequestLocation != null)
                                    IconButton(
                                      tooltip:
                                          'Solicitar ubicación de ${driver.fullName}',
                                      onPressed: requesting
                                          ? null
                                          : () => widget.onRequestLocation!(
                                              driver,
                                            ),
                                      constraints:
                                          const BoxConstraints.tightFor(
                                            width: 48,
                                            height: 48,
                                          ),
                                      icon: requesting
                                          ? const SizedBox.square(
                                              dimension: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: appBlack,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.my_location_rounded,
                                              color: appBlack,
                                            ),
                                    ),
                                  if (widget.onToggleDriverStatus != null)
                                    IconButton(
                                      tooltip: isActive
                                          ? 'Desactivar driver'
                                          : 'Activar driver',
                                      onPressed: () =>
                                          widget.onToggleDriverStatus!(driver),
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
                                          color: isActive ? appBlack : appLime,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          isActive
                                              ? Icons.person_off_outlined
                                              : Icons.person_add_alt_1_rounded,
                                          color: isActive ? appWhite : appBlack,
                                          size: 20,
                                        ),
                                      ),
                                    ),
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

  /// Solo la disponibilidad: nada sobre la senal del equipo.
  String _locationStatus(DriverLiveLocation? live) {
    if (live == null) return 'Sin disponibilidad';
    return live.available ? 'Disponible' : 'No disponible';
  }
}
