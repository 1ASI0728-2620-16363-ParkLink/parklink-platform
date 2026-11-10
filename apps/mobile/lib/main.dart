import 'package:flutter/material.dart';
import 'data/repositories/parking_repository.dart';
import 'ui/features/parking/views/parklink_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = ParkingRepository();
  await repository.restore();
  runApp(ParkLinkApp(repository: repository));
}
