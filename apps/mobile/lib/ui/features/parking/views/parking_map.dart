import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../domain/models/location_point.dart';
import '../../../../domain/models/parking_space.dart';
import '../../../core/app_theme.dart';
import '../../../core/map_theme.dart';
import '../view_models/parking_view_model.dart';
import 'parking_widgets.dart';

class ParkingMap extends StatefulWidget {
  const ParkingMap({
    required this.viewModel,
    required this.onSelect,
    required this.onLocate,
    required this.onFilters,
    required this.onCopilot,
    required this.controller,
    this.userLocation,
    this.locating = false,
    super.key,
  });
  final ParkingViewModel viewModel;
  final MapController controller;
  final ValueChanged<ParkingSpace> onSelect;
  final VoidCallback onLocate, onFilters, onCopilot;
  final LocationPoint? userLocation;
  final bool locating;
  @override
  State<ParkingMap> createState() => _ParkingMapState();
}

class _ParkingMapState extends State<ParkingMap> {
  Timer? _searchDebounce;
  final _reset = StreamController<void>.broadcast();
  bool _tileError = false;
  late final _tileProvider = NetworkTileProvider(
    // Identifiable traffic, cancellable viewport requests, HTTP-aware disk cache.
    headers: {'User-Agent': 'ParkLink/1.0 (com.parklink.mobile)'},
    cachingProvider: BuiltInMapCachingProvider.getOrCreateInstance(
      maxCacheSize: 128 * 1024 * 1024,
    ),
  );
  @override
  void dispose() {
    _searchDebounce?.cancel();
    _reset.close();
    super.dispose();
  }

  void _onTileError() {
    if (_tileError || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_tileError) setState(() => _tileError = true);
    });
  }

  void _retry() {
    setState(() => _tileError = false);
    _reset.add(null);
    unawaited(widget.viewModel.search());
  }

  @override
  Widget build(BuildContext context) {
    final bottom =
        math.max(MediaQuery.viewPaddingOf(context).bottom, 14.0) + 68 + 16;
    final vm = widget.viewModel;
    return Stack(
      fit: StackFit.expand,
      children: [
        ValueListenableBuilder<MapTheme>(
          valueListenable: mapThemeController,
          builder: (context, theme, _) => FlutterMap(
            mapController: widget.controller,
            options: MapOptions(
              initialCenter: LatLng(vm.latitude, vm.longitude),
              initialZoom: 14,
              minZoom: 3,
              maxZoom: 19,
              keepAlive: true,
              backgroundColor: theme == MapTheme.oscuro
                  ? appSurface
                  : const Color(0xFFE9EEEE),
              onPositionChanged: (camera, _) {
                vm.latitude = camera.center.latitude;
                vm.longitude = camera.center.longitude;
              },
              onMapEvent: (event) {
                if (event is MapEventMoveEnd) {
                  _searchDebounce?.cancel();
                  _searchDebounce = Timer(
                    const Duration(milliseconds: 650),
                    vm.search,
                  );
                }
              },
            ),
            children: [
              ColorFiltered(
                colorFilter: ColorFilter.matrix(
                  theme == MapTheme.oscuro
                      ? const [
                          .574,
                          -1.43,
                          -.144,
                          0,
                          255,
                          -.426,
                          -.43,
                          -.144,
                          0,
                          255,
                          -.426,
                          -1.43,
                          .856,
                          0,
                          255,
                          0,
                          0,
                          0,
                          1,
                          0,
                        ]
                      : theme == MapTheme.claro
                      ? const [
                          .213,
                          .715,
                          .072,
                          0,
                          0,
                          .213,
                          .715,
                          .072,
                          0,
                          0,
                          .213,
                          .715,
                          .072,
                          0,
                          0,
                          0,
                          0,
                          0,
                          1,
                          0,
                        ]
                      : const [
                          1,
                          0,
                          0,
                          0,
                          0,
                          0,
                          1,
                          0,
                          0,
                          0,
                          0,
                          0,
                          1,
                          0,
                          0,
                          0,
                          0,
                          0,
                          1,
                          0,
                        ],
                ),
                child: TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.parklink.mobile',
                  tileProvider: _tileProvider,
                  maxNativeZoom: 19,
                  panBuffer: 0,
                  keepBuffer: 1,
                  reset: _reset.stream,
                  evictErrorTileStrategy: EvictErrorTileStrategy.notVisible,
                  errorTileCallback: (_, _, _) => _onTileError(),
                ),
              ),
              MarkerLayer(
                markers: [
                  if (widget.userLocation case final position?)
                    Marker(
                      point: LatLng(position.latitude, position.longitude),
                      width: 28,
                      height: 28,
                      child: Semantics(
                        label: 'Tu ubicación actual',
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: appLime.withValues(alpha: .25),
                          ),
                          padding: const EdgeInsets.all(5),
                          child: Container(
                            decoration: BoxDecoration(
                              color: appLime,
                              shape: BoxShape.circle,
                              border: Border.all(color: appWhite, width: 3),
                            ),
                          ),
                        ),
                      ),
                    ),
                  for (final space in vm.spaces)
                    Marker(
                      point: LatLng(space.latitude, space.longitude),
                      width: 96,
                      height: 48,
                      child: Semantics(
                        button: true,
                        label:
                            '${space.title}, ${parkingMoney(space.hourlyRate)} por hora. Consultar espacio.',
                        child: ExcludeSemantics(
                          child: Material(
                            color: appLime,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                              side: const BorderSide(
                                color: appBlack,
                                width: 1.5,
                              ),
                            ),
                            elevation: 2,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(24),
                              onTap: () => widget.onSelect(space),
                              child: Center(
                                child: Text(
                                  parkingMoney(space.hourlyRate),
                                  style: const TextStyle(
                                    color: appBlack,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
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
        Positioned(
          top: 0,
          right: 16,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                children: [
                  ParkingControl(
                    icon: Icons.tune_rounded,
                    label: 'Filtrar estacionamientos',
                    onPressed: widget.onFilters,
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  ParkingControl(
                    icon: Icons.layers_outlined,
                    label: 'Tema del mapa',
                    onPressed: () => showMapThemePicker(context),
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  ParkingControl(
                    icon: Icons.auto_awesome_outlined,
                    label: 'Abrir Copilot',
                    onPressed: widget.onCopilot,
                    size: 48,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_tileError || vm.mapError != null)
          Positioned(
            top: 0,
            left: 16,
            right: 80,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Material(
                  color: appWhite,
                  borderRadius: BorderRadius.circular(24),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: _retry,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.refresh, color: appBlack, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _tileError
                                  ? 'Mapa sin conexión. Reintentar'
                                  : 'Actualizar espacios',
                              style: const TextStyle(
                                color: appBlack,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        Positioned(
          right: 16,
          bottom: bottom + 32,
          child: ParkingControl(
            icon: Icons.my_location_outlined,
            label: 'Centrar en mi ubicación',
            onPressed: widget.onLocate,
            busy: widget.locating,
            size: 64,
          ),
        ),
        // Attribution stays visible above the floating dock, never behind a toggle.
        Positioned(
          left: 16,
          right: 96,
          bottom: bottom,
          child: Align(
            alignment: Alignment.bottomLeft,
            child: TextButton(
              onPressed: () => launchUrl(
                Uri.parse('https://www.openstreetmap.org/copyright'),
                mode: LaunchMode.externalApplication,
              ),
              style: TextButton.styleFrom(
                backgroundColor: appWhite,
                foregroundColor: appBlack,
                minimumSize: const Size(48, 44),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                '© OpenStreetMap contributors',
                style: TextStyle(fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
