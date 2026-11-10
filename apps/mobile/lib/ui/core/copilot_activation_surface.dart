import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Observes the shortcut without claiming the map's tap/zoom gesture arena.
/// Screen-reader activation remains untouched; the explicit Copilot button is
/// the accessible alternative when accessible navigation is enabled.
class CopilotActivationSurface extends StatefulWidget {
  const CopilotActivationSurface({required this.child, required this.onActivate, super.key});
  final Widget child;
  final VoidCallback onActivate;
  @override State<CopilotActivationSurface> createState() => _CopilotActivationSurfaceState();
}

class _CopilotActivationSurfaceState extends State<CopilotActivationSurface> {
  final _down = <int, Offset>{};
  DateTime? _lastTap;
  Offset? _lastPosition;
  bool _multiTouch = false;
  void down(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch && event.kind != PointerDeviceKind.mouse) return;
    _down[event.pointer] = event.position;
    if (_down.length > 1) { _multiTouch = true; _lastTap = null; }
  }
  void up(PointerUpEvent event) {
    final origin = _down.remove(event.pointer);
    final multiTouch = _multiTouch;
    if (_down.isEmpty) _multiTouch = false;
    if (origin == null || multiTouch || (origin - event.position).distance > 12) { _lastTap = null; return; }
    if (MediaQuery.accessibleNavigationOf(context) || MediaQuery.viewInsetsOf(context).bottom > 0) { _lastTap = null; return; }
    final now = DateTime.now();
    if (_lastTap != null && now.difference(_lastTap!).inMilliseconds <= 350 && (event.position - _lastPosition!).distance <= 32) {
      _lastTap = null;
      widget.onActivate();
    } else { _lastTap = now; _lastPosition = event.position; }
  }
  @override Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: down, onPointerUp: up,
    onPointerMove: (event) { final origin = _down[event.pointer]; if (origin != null && (origin - event.position).distance > 12) { _down.remove(event.pointer); _lastTap = null; } },
    onPointerCancel: (event) { _down.remove(event.pointer); _lastTap = null; if (_down.isEmpty) _multiTouch = false; },
    child: widget.child,
  );
}
