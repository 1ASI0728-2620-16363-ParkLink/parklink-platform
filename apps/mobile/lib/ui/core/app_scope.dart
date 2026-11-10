import 'package:flutter/widgets.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/admin_repository.dart';
import '../../data/repositories/client_service_repository.dart';
import '../../data/repositories/driver_presence_repository.dart';
import '../../data/repositories/evidence_repository.dart';
import '../../data/repositories/notification_repository.dart';
import '../../data/repositories/service_event_repository.dart';
import '../../data/repositories/service_repository.dart';
import '../../data/repositories/tracking_repository.dart';
import '../../data/services/background_tracking_service.dart';
import '../../data/services/location_service.dart';
import '../../data/services/road_routing_service.dart';
import '../../data/services/session_store.dart';
import '../../data/services/sync_coordinator.dart';

class AppScope extends InheritedWidget {
  const AppScope({
    required this.authRepository,
    required this.adminRepository,
    required this.clientServiceRepository,
    required this.driverPresenceRepository,
    required this.notificationRepository,
    required this.serviceRepository,
    required this.eventRepository,
    required this.evidenceRepository,
    required this.locationService,
    required this.roadRoutingService,
    required this.sessionStore,
    required this.trackingRepository,
    required this.backgroundTrackingService,
    required this.syncCoordinator,
    required super.child,
    super.key,
  });

  final AuthRepository authRepository;
  final AdminRepository adminRepository;
  final ClientServiceRepository clientServiceRepository;
  final DriverPresenceRepository driverPresenceRepository;
  final NotificationRepository notificationRepository;
  final ServiceRepository serviceRepository;
  final ServiceEventRepository eventRepository;
  final EvidenceRepository evidenceRepository;
  final LocationService locationService;
  final RoadRoutingService roadRoutingService;
  final SessionStore sessionStore;
  final TrackingRepository trackingRepository;
  final BackgroundTrackingService backgroundTrackingService;
  final SyncCoordinator syncCoordinator;

  static AppScope of(BuildContext context, {bool listen = true}) {
    final widget = listen
        ? context.dependOnInheritedWidgetOfExactType<AppScope>()
        : context.getInheritedWidgetOfExactType<AppScope>();
    assert(widget != null, 'AppScope not found');
    return widget!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => false;
}
