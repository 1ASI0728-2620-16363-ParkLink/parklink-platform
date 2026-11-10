import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../data/services/road_routing_service.dart';
import '../../domain/models/transport_service.dart';
import 'app_theme.dart';
import 'map_theme.dart';

class RouteVisual {
  const RouteVisual({
    required this.service,
    required this.color,
    this.highlighted = false,
    this.actualPoints = const [],
  });

  final TransportService service;
  final Color color;
  final bool highlighted;
  final List<LatLng> actualPoints;
}

class MapVehicleVisual {
  const MapVehicleVisual({
    required this.id,
    required this.point,
    required this.heading,
    required this.label,
    this.routeId,
    this.stale = false,
    this.useCarMarker = false,
  });

  final String id;
  final String? routeId;
  final LatLng point;
  final double heading;
  final String label;
  final bool stale;
  final bool useCarMarker;
}

class OrganicRouteMap extends StatefulWidget {
  const OrganicRouteMap({
    required this.routes,
    this.initialZoom = 11.2,
    this.selectedRouteId,
    this.draftPickup,
    this.draftDestination,
    this.onRouteSelected,
    this.vehicles = const [],
    this.onVehicleTap,
    this.followVehicleId,
    this.followVehicleCentered = false,
    this.headingUp = false,
    this.showEmptyMap = false,
    this.userLocation,
    this.zoomControlsBottomInset = 84,
    super.key,
  });

  final List<RouteVisual> routes;
  final double initialZoom;
  final String? selectedRouteId;
  final LatLng? draftPickup;
  final LatLng? draftDestination;
  final Future<void> Function(TransportService service)? onRouteSelected;
  final List<MapVehicleVisual> vehicles;
  /// Toque sobre una unidad del mapa. Si es nulo, el marcador no reacciona.
  final void Function(MapVehicleVisual vehicle)? onVehicleTap;
  final String? followVehicleId;
  final bool followVehicleCentered;
  final bool headingUp;
  final bool showEmptyMap;
  final LatLng? userLocation;
  final double zoomControlsBottomInset;

  @override
  State<OrganicRouteMap> createState() => _OrganicRouteMapState();
}

class _OrganicRouteMapState extends State<OrganicRouteMap> {
  static const _roadRoutingService = RoadRoutingService();
  static final Map<String, Future<List<LatLng>>> _routeCache = {};

  final MapController _mapController = MapController();
  final LayerHitNotifier<String> _hitNotifier = ValueNotifier(null);

  late Future<Map<String, List<LatLng>>> _roadRoutes;
  late String _routesSignature;

  @override
  void initState() {
    super.initState();
    _routesSignature = _signature();
    _roadRoutes = _loadRoadRoutes();
    if (widget.selectedRouteId != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _focusSelectedRoute(),
      );
    }
    final followed = _followedVehicle();
    if (followed != null && widget.headingUp) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _focusVehicle(followed),
      );
    }
  }

  @override
  void didUpdateWidget(covariant OrganicRouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final signature = _signature();
    if (signature != _routesSignature) {
      _routesSignature = signature;
      _roadRoutes = _loadRoadRoutes();
    }
    if (widget.selectedRouteId != oldWidget.selectedRouteId &&
        widget.selectedRouteId != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _focusSelectedRoute(),
      );
    }
    if (widget.draftPickup != oldWidget.draftPickup &&
        widget.draftPickup != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _focusDraftPoint(widget.draftPickup!),
      );
    }
    if (widget.draftDestination != oldWidget.draftDestination &&
        widget.draftDestination != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _focusDraftPoint(widget.draftDestination!),
      );
    }
    final followed = _followedVehicle();
    final oldFollowed = _followedVehicle(oldWidget);
    if (followed != null &&
        (followed.point != oldFollowed?.point ||
            followed.heading != oldFollowed?.heading ||
            widget.followVehicleCentered != oldWidget.followVehicleCentered ||
            widget.headingUp != oldWidget.headingUp)) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _focusVehicle(followed),
      );
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    _hitNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasMapContent) {
      return Semantics(
        label: 'No hay rutas ni vehículos para mostrar.',
        child: const ColoredBox(
          color: Color(0xFF171817),
          child: Center(
            child: Text(
              'Sin rutas ni vehículos para mostrar',
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
    }
    return FutureBuilder<Map<String, List<LatLng>>>(
      future: _roadRoutes,
      builder: (context, snapshot) {
        final roadRoutes = snapshot.data ?? const <String, List<LatLng>>{};
        final visibleRoutes = widget.selectedRouteId == null
            ? widget.routes
            : widget.routes
                  .where((route) => route.service.id == widget.selectedRouteId)
                  .toList();
        final visibleVehicles = widget.selectedRouteId == null
            ? widget.vehicles
            : widget.vehicles
                  .where(
                    (vehicle) =>
                        vehicle.routeId == null ||
                        vehicle.routeId == widget.selectedRouteId,
                  )
                  .toList();
        return Semantics(
          label: 'Mapa de rutas planificadas y recorridos GPS registrados.',
          child: Stack(
            fit: StackFit.expand,
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _initialCenter(),
                  initialZoom: widget.initialZoom,
                  minZoom: 4,
                  maxZoom: 19,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all,
                  ),
                ),
                children: [
                  ValueListenableBuilder<MapTheme>(
                    valueListenable: mapThemeController,
                    builder: (context, mapTheme, _) => TileLayer(
                      urlTemplate: mapTheme.urlTemplate,
                      subdomains: const ['a', 'b', 'c', 'd'],
                      retinaMode: RetinaMode.isHighDensity(context),
                      userAgentPackageName: 'com.rutasapp.mobile_driver',
                    ),
                  ),
                  GestureDetector(
                    onTap: widget.onRouteSelected == null
                        ? null
                        : _selectHitRoute,
                    child: PolylineLayer<String>(
                      hitNotifier: _hitNotifier,
                      minimumHitbox: 18,
                      polylines: [
                        for (final route in visibleRoutes)
                          if ((roadRoutes[route.service.id]?.length ?? 0) >= 2)
                            Polyline<String>(
                              points: roadRoutes[route.service.id]!,
                              color: route.color,
                              strokeWidth: route.highlighted ? 7 : 5,
                              borderColor: Colors.black.withValues(alpha: 0.65),
                              borderStrokeWidth: route.highlighted ? 11 : 8,
                              hitValue: route.service.id,
                            ),
                      ],
                    ),
                  ),
                  PolylineLayer(
                    polylines: [
                      for (final route in visibleRoutes)
                        if (route.actualPoints.length >= 2)
                          Polyline(
                            points: route.actualPoints,
                            color: appWhite,
                            strokeWidth: route.highlighted ? 5 : 4,
                            borderColor: appBlack.withValues(alpha: 0.8),
                            borderStrokeWidth: route.highlighted ? 8 : 7,
                          ),
                    ],
                  ),
                  MarkerLayer(markers: _markers(visibleRoutes)),
                  if (widget.userLocation != null)
                    _UserLocationMarker(point: widget.userLocation!),
                  for (final vehicle in visibleVehicles)
                    _AnimatedVehicleMarkerLayer(
                      key: ValueKey(vehicle.id),
                      vehicle: vehicle,
                      headingUp: widget.headingUp,
                      onTap: widget.onVehicleTap == null
                          ? null
                          : () {
                              _focusVehicle(vehicle);
                              widget.onVehicleTap!(vehicle);
                            },
                    ),
                ],
              ),
              Positioned(
                bottom:
                    MediaQuery.paddingOf(context).bottom +
                    widget.zoomControlsBottomInset,
                right: 16,
                child: _MapZoomControls(
                  onZoomIn: () => _changeZoom(1),
                  onZoomOut: () => _changeZoom(-1),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _changeZoom(double delta) {
    final camera = _mapController.camera;
    final zoom = (camera.zoom + delta).clamp(4.0, 19.0).toDouble();
    _mapController.move(camera.center, zoom);
  }

  LatLng _initialCenter() {
    final draftPoints = [
      if (widget.draftPickup != null) widget.draftPickup!,
      if (widget.draftDestination != null) widget.draftDestination!,
    ];
    if (draftPoints.isNotEmpty) {
      final lat =
          draftPoints.map((point) => point.latitude).reduce((a, b) => a + b) /
          draftPoints.length;
      final lng =
          draftPoints.map((point) => point.longitude).reduce((a, b) => a + b) /
          draftPoints.length;
      return LatLng(lat, lng);
    }
    final followed = _followedVehicle();
    if (followed != null) return followed.point;
    if (widget.vehicles.isNotEmpty) return widget.vehicles.first.point;
    final validRoutes = widget.routes.where(_hasCoordinates).toList();
    if (validRoutes.isEmpty) return const LatLng(-12.0464, -77.0428);
    final points = validRoutes
        .expand(
          (route) => [_pickup(route.service), _destination(route.service)],
        )
        .toList();
    final lat =
        points.map((point) => point.latitude).reduce((a, b) => a + b) /
        points.length;
    final lng =
        points.map((point) => point.longitude).reduce((a, b) => a + b) /
        points.length;
    return LatLng(lat, lng);
  }

  bool get _hasMapContent =>
      widget.showEmptyMap ||
      widget.userLocation != null ||
      widget.draftPickup != null ||
      widget.draftDestination != null ||
      widget.vehicles.isNotEmpty ||
      widget.routes.any(_hasCoordinates);

  List<Marker> _markers(List<RouteVisual> routes) {
    return [
      if (widget.draftPickup != null)
        _interactiveMarker(
          point: widget.draftPickup!,
          label: 'Origen de la nueva ruta',
          child: const SizedBox.square(
            dimension: 24,
            child: _RouteStartDot(color: appLime),
          ),
        ),
      if (widget.draftDestination != null)
        _interactiveMarker(
          point: widget.draftDestination!,
          label: 'Destino de la nueva ruta',
          child: const SizedBox.square(
            dimension: 36,
            child: _OutlinedMapFlag(color: appLime),
          ),
        ),
      for (final route in routes.where(_hasCoordinates)) ...[
        _interactiveMarker(
          point: _pickup(route.service),
          label: 'Origen de ${route.service.code}',
          child: SizedBox.square(
            dimension: 12,
            child: _RouteStartDot(color: route.color),
          ),
        ),
        _interactiveMarker(
          point: _destination(route.service),
          label: 'Destino de ${route.service.code}',
          child: SizedBox.square(
            dimension: 28,
            child: _OutlinedMapFlag(color: route.color),
          ),
        ),
        if (route.service.openStop?.latitude != null &&
            route.service.openStop?.longitude != null)
          _interactiveMarker(
            point: LatLng(
              route.service.openStop!.latitude!,
              route.service.openStop!.longitude!,
            ),
            label: 'Parada activa de ${route.service.code}',
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: route.color,
                shape: BoxShape.circle,
                border: Border.all(color: appWhite, width: 2),
              ),
              child: const Icon(Icons.pause_rounded, color: appBlack, size: 15),
            ),
          ),
      ],
    ];
  }

  Marker _interactiveMarker({
    required LatLng point,
    required String label,
    required Widget child,
  }) {
    return Marker(
      point: point,
      width: 48,
      height: 48,
      child: Semantics(
        button: true,
        label: '$label. Acercar mapa',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _focusPoint(point),
          child: Center(child: child),
        ),
      ),
    );
  }

  void _focusPoint(LatLng point) {
    final currentZoom = _mapController.camera.zoom;
    _mapController.move(point, currentZoom < 16.5 ? 16.5 : currentZoom);
  }

  void _focusDraftPoint(LatLng point) {
    final currentZoom = _mapController.camera.zoom;
    _mapController.move(
      point,
      currentZoom < 16.5 ? 16.5 : currentZoom,
      offset: Offset(0, -MediaQuery.sizeOf(context).height * 0.3),
    );
  }

  void _focusVehicle(MapVehicleVisual vehicle) {
    if (!mounted) return;
    final currentZoom = _mapController.camera.zoom;
    if (widget.headingUp && vehicle.heading.isFinite) {
      _mapController.rotate(-vehicle.heading);
    }
    _mapController.move(
      vehicle.point,
      currentZoom < 16.5 ? 16.5 : currentZoom,
      offset: widget.followVehicleCentered || widget.selectedRouteId == null
          ? Offset.zero
          : Offset(0, -MediaQuery.sizeOf(context).height * 0.16),
    );
  }

  void _selectHitRoute() {
    final hitValues = _hitNotifier.value?.hitValues;
    if (hitValues == null || hitValues.isEmpty) return;
    final id = hitValues.first;
    for (final route in widget.routes) {
      if (route.service.id == id) {
        widget.onRouteSelected?.call(route.service);
        return;
      }
    }
  }

  Future<void> _focusSelectedRoute() async {
    final selectedId = widget.selectedRouteId;
    if (selectedId == null) return;
    final routes = await _roadRoutes;
    if (!mounted || widget.selectedRouteId != selectedId) return;
    final points = routes[selectedId];
    if (points == null || points.isEmpty) return;
    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: points,
        padding: const EdgeInsets.fromLTRB(48, 80, 48, 320),
        maxZoom: 14,
      ),
    );
  }

  String _signature() {
    final routes = widget.routes
        .map((route) {
          final service = route.service;
          return '${service.id}:'
              '${service.pickupLatitude},${service.pickupLongitude}:'
              '${service.destinationLatitude},${service.destinationLongitude}';
        })
        .join('|');
    return '$routes|${widget.draftPickup}|${widget.draftDestination}';
  }

  Future<Map<String, List<LatLng>>> _loadRoadRoutes() async {
    final result = <String, List<LatLng>>{};
    for (final route in widget.routes) {
      final service = route.service;
      if (service.pickupLatitude == null ||
          service.pickupLongitude == null ||
          service.destinationLatitude == null ||
          service.destinationLongitude == null) {
        continue;
      }

      final start = _pickup(service);
      final end = _destination(service);
      final cacheKey =
          '${start.latitude},${start.longitude};'
          '${end.latitude},${end.longitude}';
      try {
        result[service.id] = await _routeCache.putIfAbsent(
          cacheKey,
          () => _roadRoutingService.route(start, end),
        );
      } catch (_) {
        result[service.id] = const [];
        _routeCache.remove(cacheKey);
      }
    }
    return result;
  }

  LatLng _pickup(TransportService service) {
    return LatLng(service.pickupLatitude!, service.pickupLongitude!);
  }

  bool _hasCoordinates(RouteVisual route) {
    final service = route.service;
    return service.pickupLatitude != null &&
        service.pickupLongitude != null &&
        service.destinationLatitude != null &&
        service.destinationLongitude != null;
  }

  LatLng _destination(TransportService service) {
    return LatLng(service.destinationLatitude!, service.destinationLongitude!);
  }

  MapVehicleVisual? _followedVehicle([OrganicRouteMap? source]) {
    final target = source ?? widget;
    final id = target.followVehicleId;
    if (id == null) return null;
    for (final vehicle in target.vehicles) {
      if (vehicle.id == id) return vehicle;
    }
    return null;
  }
}

class _AnimatedVehicleMarkerLayer extends StatelessWidget {
  const _AnimatedVehicleMarkerLayer({
    required this.vehicle,
    required this.headingUp,
    this.onTap,
    super.key,
  });

  final MapVehicleVisual vehicle;
  final bool headingUp;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 900);
    return TweenAnimationBuilder<LatLng>(
      tween: _LatLngTween(begin: vehicle.point, end: vehicle.point),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, point, _) => MarkerLayer(
        markers: [
          Marker(
            point: point,
            width: 48,
            height: 48,
            rotate: headingUp,
            child: Semantics(
              container: true,
              excludeSemantics: true,
              button: onTap != null,
              label: vehicle.stale
                  ? '${vehicle.label}. Ubicación temporalmente desactualizada'
                  : vehicle.label,
              // `opaque` para que el toque valga en todo el recuadro del
              // marcador y no solo sobre los pixeles pintados del auto.
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTap,
                child: Center(
                child: Opacity(
                  opacity: vehicle.stale ? 0.5 : 1,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(
                      begin: headingUp ? 0 : vehicle.heading,
                      end: headingUp ? 0 : vehicle.heading,
                    ),
                    duration: duration,
                    curve: Curves.easeOutCubic,
                    builder: (context, heading, child) => Transform.rotate(
                      angle: heading * math.pi / 180,
                      child: child,
                    ),
                    child: vehicle.useCarMarker
                        ? const SizedBox(
                            key: ValueKey('low-poly-vehicle'),
                            width: 30,
                            height: 36,
                            child: CustomPaint(painter: _LowPolyCarPainter()),
                          )
                        // El PNG viene con la nariz hacia arriba, así que la
                        // rotación por rumbo lo orienta sin corrección extra.
                        : Image.asset(
                            'assets/images/autorojo.png',
                            key: const ValueKey('vehicle-marker'),
                            width: 34,
                            height: 40,
                            fit: BoxFit.contain,
                            // Si el asset no carga, el marcador no puede
                            // desaparecer: es la posición del conductor.
                            errorBuilder: (context, _, _) => const Icon(
                              Icons.navigation_rounded,
                              color: appLime,
                              size: 34,
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
    );
  }
}

class _LowPolyCarPainter extends CustomPainter {
  const _LowPolyCarPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    final shadow = Paint()
      ..color = const Color(0x88000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(width * 0.5, height * 0.57),
        width: width * 0.9,
        height: height * 0.72,
      ),
      shadow,
    );

    final wheelPaint = Paint()..color = const Color(0xFF111311);
    for (final rect in [
      Rect.fromLTWH(width * 0.08, height * 0.2, width * 0.18, height * 0.22),
      Rect.fromLTWH(width * 0.74, height * 0.2, width * 0.18, height * 0.22),
      Rect.fromLTWH(width * 0.08, height * 0.64, width * 0.18, height * 0.22),
      Rect.fromLTWH(width * 0.74, height * 0.64, width * 0.18, height * 0.22),
    ]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(width * 0.06)),
        wheelPaint,
      );
    }

    final body = ui.Path()
      ..moveTo(width * 0.34, height * 0.02)
      ..lineTo(width * 0.66, height * 0.02)
      ..lineTo(width * 0.84, height * 0.22)
      ..lineTo(width * 0.8, height * 0.88)
      ..lineTo(width * 0.66, height * 0.98)
      ..lineTo(width * 0.34, height * 0.98)
      ..lineTo(width * 0.2, height * 0.88)
      ..lineTo(width * 0.16, height * 0.22)
      ..close();
    canvas.drawPath(body, Paint()..color = const Color(0xFFF8F8F4));
    canvas.drawPath(
      body,
      Paint()
        ..color = const Color(0xFF202220)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    final leftFacet = ui.Path()
      ..moveTo(width * 0.16, height * 0.22)
      ..lineTo(width * 0.5, height * 0.34)
      ..lineTo(width * 0.5, height * 0.9)
      ..lineTo(width * 0.2, height * 0.88)
      ..close();
    canvas.drawPath(leftFacet, Paint()..color = const Color(0xFFE1E2DD));

    final hood = ui.Path()
      ..moveTo(width * 0.34, height * 0.02)
      ..lineTo(width * 0.66, height * 0.02)
      ..lineTo(width * 0.76, height * 0.2)
      ..lineTo(width * 0.5, height * 0.3)
      ..lineTo(width * 0.24, height * 0.2)
      ..close();
    canvas.drawPath(hood, Paint()..color = const Color(0xFFFFFFFF));

    final cabin = ui.Path()
      ..moveTo(width * 0.3, height * 0.31)
      ..lineTo(width * 0.7, height * 0.31)
      ..lineTo(width * 0.73, height * 0.68)
      ..lineTo(width * 0.62, height * 0.78)
      ..lineTo(width * 0.38, height * 0.78)
      ..lineTo(width * 0.27, height * 0.68)
      ..close();
    canvas.drawPath(cabin, Paint()..color = const Color(0xFFBFC9CA));

    final windshield = ui.Path()
      ..moveTo(width * 0.32, height * 0.34)
      ..lineTo(width * 0.68, height * 0.34)
      ..lineTo(width * 0.65, height * 0.49)
      ..lineTo(width * 0.35, height * 0.49)
      ..close();
    canvas.drawPath(windshield, Paint()..color = const Color(0xFF344144));
    canvas.drawLine(
      Offset(width * 0.5, height * 0.31),
      Offset(width * 0.5, height * 0.9),
      Paint()
        ..color = const Color(0x5590928E)
        ..strokeWidth = 0.8,
    );

    final lightPaint = Paint()..color = const Color(0xFFD8FF58);
    canvas.drawCircle(Offset(width * 0.31, height * 0.13), 1.4, lightPaint);
    canvas.drawCircle(Offset(width * 0.69, height * 0.13), 1.4, lightPaint);
  }

  @override
  bool shouldRepaint(covariant _LowPolyCarPainter oldDelegate) => false;
}

class _UserLocationMarker extends StatelessWidget {
  const _UserLocationMarker({required this.point});

  final LatLng point;

  @override
  Widget build(BuildContext context) {
    return MarkerLayer(
      markers: [
        Marker(
          point: point,
          width: 48,
          height: 48,
          child: Semantics(
            container: true,
            excludeSemantics: true,
            label: 'Tu ubicación actual',
            child: Center(
              child: Container(
                width: 26,
                height: 26,
                decoration: const BoxDecoration(
                  color: appLime,
                  shape: BoxShape.circle,
                  border: Border.fromBorderSide(
                    BorderSide(color: appWhite, width: 3),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x66000000),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: const Center(
                  child: SizedBox.square(
                    dimension: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: appBlack,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LatLngTween extends Tween<LatLng> {
  _LatLngTween({required super.begin, required super.end});

  @override
  LatLng lerp(double t) => LatLng(
    begin!.latitude + (end!.latitude - begin!.latitude) * t,
    begin!.longitude + (end!.longitude - begin!.longitude) * t,
  );
}

class _MapZoomControls extends StatelessWidget {
  const _MapZoomControls({required this.onZoomIn, required this.onZoomOut});

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filled(
          tooltip: 'Acercar',
          onPressed: onZoomIn,
          style: _zoomButtonStyle(),
          icon: const Icon(Icons.add_rounded, size: 30),
        ),
        const SizedBox(height: 10),
        IconButton.filled(
          tooltip: 'Alejar',
          onPressed: onZoomOut,
          style: _zoomButtonStyle(),
          icon: const Icon(Icons.remove_rounded, size: 30),
        ),
      ],
    );
  }

  ButtonStyle _zoomButtonStyle() => IconButton.styleFrom(
    backgroundColor: appLime,
    foregroundColor: appWhite,
    minimumSize: const Size.square(56),
    side: const BorderSide(color: Color(0x33000000)),
  );
}

class _RouteStartDot extends StatelessWidget {
  const _RouteStartDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: appBlack, width: 2),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 4),
        ],
      ),
    );
  }
}

class _OutlinedMapFlag extends StatelessWidget {
  const _OutlinedMapFlag({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final glyph = String.fromCharCode(Icons.flag_rounded.codePoint);
    return Stack(
      alignment: Alignment.center,
      children: [
        Text(
          glyph,
          style: TextStyle(
            inherit: false,
            fontFamily: Icons.flag_rounded.fontFamily,
            fontSize: 22,
            height: 1,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3
              ..strokeJoin = StrokeJoin.round
              ..color = Colors.white,
          ),
        ),
        Text(
          glyph,
          style: TextStyle(
            inherit: false,
            fontFamily: Icons.flag_rounded.fontFamily,
            fontSize: 22,
            height: 1,
            color: color,
          ),
        ),
      ],
    );
  }
}
