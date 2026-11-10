import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../data/services/parking_location_service.dart';
import '../../../core/app_theme.dart';
import '../view_models/nearby_search_view_model.dart';
import 'parking_widgets.dart';

class NearbySearchSheet extends StatefulWidget {
  const NearbySearchSheet({required this.viewModel, super.key});
  final NearbySearchViewModel viewModel;
  @override
  State<NearbySearchSheet> createState() => _NearbySearchSheetState();
}

class _NearbySearchSheetState extends State<NearbySearchSheet>
    with WidgetsBindingObserver {
  bool _awaitingSettings = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(widget.viewModel.search());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingSettings) {
      _awaitingSettings = false;
      unawaited(widget.viewModel.search());
    }
  }

  Future<void> settings() async {
    _awaitingSettings = true;
    final opened = await widget.viewModel.openSettings();
    if (!mounted) return;
    if (!opened) {
      _awaitingSettings = false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Abre los ajustes del teléfono para habilitar la ubicación.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.viewModel,
    builder: (context, _) {
      final vm = widget.viewModel;
      final reduceMotion = MediaQuery.disableAnimationsOf(context);
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    vm.state == NearbySearchState.found
                        ? 'Tu próximo lugar'
                        : 'Encuentra tu espacio',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.5,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  tooltip: 'Cerrar búsqueda',
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 20),
            AnimatedSize(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: AnimatedSwitcher(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                child: KeyedSubtree(
                  key: ValueKey(vm.state),
                  child: content(vm),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
  Widget content(NearbySearchViewModel vm) => switch (vm.state) {
    NearbySearchState.searching => Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Semantics(
        liveRegion: true,
        child: const Column(
          children: [
            SizedBox.square(
              dimension: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: appBlack,
              ),
            ),
            SizedBox(height: 24),
            Text(
              'Buscando el estacionamiento más cercano...',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Comprobamos precio y disponibilidad.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF5C6464)),
            ),
          ],
        ),
      ),
    ),
    NearbySearchState.found => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ParkingResultCard(
          space: vm.result!.space,
          verified: true,
          fromDevice: vm.fromDevice,
          onReserve: () => Navigator.pop(context, vm.result),
        ),
        const SizedBox(height: 24),
        Text(
          'Para la próxima hora, desde ${_time(vm.result!.start)} hasta ${_time(vm.result!.end)} (Lima). Se vuelve a validar al reservar. Distancia en línea recta.',
          style: const TextStyle(
            color: Color(0xFF5C6464),
            fontSize: 12,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => vm.search(useMapCenter: !vm.fromDevice),
          child: const Text('Actualizar búsqueda'),
        ),
      ],
    ),
    NearbySearchState.locationRequired => ParkingEmptyState(
      icon: Icons.location_on_outlined,
      title: 'Encuentra lugares cerca de ti',
      message: switch (vm.locationIssue) {
        ParkingLocationIssue.blocked =>
          'El permiso de ubicación está desactivado. Puedes habilitarlo en Ajustes o buscar desde el mapa.',
        ParkingLocationIssue.disabled =>
          'Activa la ubicación del teléfono para encontrar el estacionamiento más cercano.',
        ParkingLocationIssue.unavailable =>
          'No pudimos obtener tu ubicación. Inténtalo de nuevo o elige una zona en el mapa.',
        _ =>
          'Usamos tu ubicación solo mientras utilizas la aplicación para encontrar estacionamientos cercanos. También puedes explorar el mapa sin dar permiso.',
      },
      action: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(
            onPressed:
                vm.locationIssue == ParkingLocationIssue.blocked ||
                    vm.locationIssue == ParkingLocationIssue.disabled
                ? settings
                : () => vm.search(requestPermission: true),
            child: Text(
              vm.locationIssue == ParkingLocationIssue.blocked ||
                      vm.locationIssue == ParkingLocationIssue.disabled
                  ? 'Abrir ajustes'
                  : 'Usar mi ubicación',
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => vm.search(useMapCenter: true),
            child: const Text('Buscar desde el mapa'),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Elegir otra zona en el mapa'),
          ),
        ],
      ),
    ),
    NearbySearchState.empty => ParkingEmptyState(
      icon: Icons.local_parking_outlined,
      title: 'No hay espacios disponibles',
      message:
          'No encontramos un espacio libre para la próxima hora en ${(vm.radius / 1000).toStringAsFixed(1)} km. Prueba otra zona o ajusta los filtros.',
      action: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(
            onPressed: () => vm.search(useMapCenter: !vm.fromDevice),
            child: const Text('Volver a buscar'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Explorar el mapa'),
          ),
        ],
      ),
    ),
    NearbySearchState.error => ParkingEmptyState(
      icon: Icons.wifi_off_outlined,
      title: 'No pudimos completar la búsqueda',
      message:
          'Revisa tu conexión y vuelve a intentarlo. No se ha realizado ninguna reserva.',
      action: FilledButton(
        onPressed: () => vm.search(useMapCenter: !vm.fromDevice),
        child: const Text('Reintentar'),
      ),
    ),
  };
  String _time(DateTime value) {
    final time = value.toUtc().subtract(const Duration(hours: 5));
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
