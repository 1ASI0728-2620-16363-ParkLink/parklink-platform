import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';

/// Estilos de mapa disponibles.
///
/// Son teselas de CartoDB, el mismo proveedor que ya usaba el mapa, así que no
/// hace falta ninguna llave nueva ni cambian las condiciones de uso.
enum MapTheme {
  oscuro(
    label: 'Oscuro',
    description: 'El estilo de siempre, ideal de noche.',
    icon: Icons.dark_mode_outlined,
    urlTemplate:
        'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
  ),
  claro(
    label: 'Claro',
    description: 'Fondo blanco, más legible con sol.',
    icon: Icons.light_mode_outlined,
    urlTemplate:
        'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
  ),
  calles(
    label: 'Calles',
    description: 'A color, con nombres de calles y lugares.',
    icon: Icons.map_outlined,
    urlTemplate:
        'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
  );

  const MapTheme({
    required this.label,
    required this.description,
    required this.icon,
    required this.urlTemplate,
  });

  final String label;
  final String description;
  final IconData icon;
  final String urlTemplate;
}

/// Preferencia de estilo de mapa, compartida por conductor, cliente y admin.
///
/// Es un [ValueNotifier] global en vez de pasar por `AppScope` porque el mapa
/// se dibuja en los tres shells y la preferencia no depende de la sesión: se
/// guarda por instalación y sobrevive al cierre de sesión.
class MapThemeController extends ValueNotifier<MapTheme> {
  MapThemeController() : super(MapTheme.oscuro);

  static const _storageKey = 'map_theme';

  /// Lee la preferencia guardada. Se llama una vez al arrancar la app.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_storageKey);
      if (stored == null) return;
      value = MapTheme.values.firstWhere(
        (theme) => theme.name == stored,
        orElse: () => MapTheme.oscuro,
      );
    } catch (_) {
      // Si no se puede leer la preferencia se sigue con el tema por defecto.
    }
  }

  Future<void> select(MapTheme theme) async {
    if (value == theme) return;
    value = theme;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, theme.name);
    } catch (_) {
      // El cambio ya se aplicó en pantalla aunque no se pueda persistir.
    }
  }
}

final mapThemeController = MapThemeController();

/// Hoja para elegir el estilo del mapa. La usan los tres roles.
Future<void> showMapThemePicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: appWhite,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tema del mapa',
              style: TextStyle(
                color: appBlack,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Se aplica al instante y queda guardado en este teléfono.',
              style: TextStyle(color: Color(0xFF666666)),
            ),
            const SizedBox(height: 16),
            ValueListenableBuilder<MapTheme>(
              valueListenable: mapThemeController,
              builder: (context, selected, _) => Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F1EE),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(
                  children: [
                    for (final theme in MapTheme.values) ...[
                      ListTile(
                        leading: Icon(theme.icon, color: appBlack),
                        title: Text(
                          theme.label,
                          style: const TextStyle(
                            color: appBlack,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        subtitle: Text(
                          theme.description,
                          style: const TextStyle(
                            color: Color(0xFF3E3E3A),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        trailing: theme == selected
                            ? const Icon(
                                Icons.check_circle_rounded,
                                color: appBlack,
                              )
                            : null,
                        onTap: () => mapThemeController.select(theme),
                      ),
                      if (theme != MapTheme.values.last)
                        const Divider(height: 1),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
