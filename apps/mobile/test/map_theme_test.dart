import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_driver/ui/core/map_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('arranca en oscuro cuando no hay nada guardado', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = MapThemeController();
    await controller.load();
    expect(controller.value, MapTheme.oscuro);
  });

  test('recupera el tema guardado en el teléfono', () async {
    SharedPreferences.setMockInitialValues({'map_theme': 'calles'});
    final controller = MapThemeController();
    await controller.load();
    expect(controller.value, MapTheme.calles);
  });

  test('un valor desconocido no rompe la app: cae en oscuro', () async {
    SharedPreferences.setMockInitialValues({'map_theme': 'satelite_inventado'});
    final controller = MapThemeController();
    await controller.load();
    expect(controller.value, MapTheme.oscuro);
  });

  test('seleccionar persiste y avisa a los oyentes', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = MapThemeController();
    var notificaciones = 0;
    controller.addListener(() => notificaciones++);

    await controller.select(MapTheme.claro);

    expect(controller.value, MapTheme.claro);
    expect(notificaciones, 1);

    final recargado = MapThemeController();
    await recargado.load();
    expect(recargado.value, MapTheme.claro);
  });

  test('reseleccionar el mismo tema no vuelve a notificar', () async {
    SharedPreferences.setMockInitialValues({'map_theme': 'claro'});
    final controller = MapThemeController();
    await controller.load();
    var notificaciones = 0;
    controller.addListener(() => notificaciones++);

    await controller.select(MapTheme.claro);

    expect(notificaciones, 0);
  });

  test('todos los estilos apuntan a teselas de cartocdn', () {
    for (final theme in MapTheme.values) {
      expect(theme.urlTemplate, contains('basemaps.cartocdn.com'));
      expect(theme.urlTemplate, contains('{z}/{x}/{y}'));
      expect(theme.label, isNotEmpty);
    }
  });
}
