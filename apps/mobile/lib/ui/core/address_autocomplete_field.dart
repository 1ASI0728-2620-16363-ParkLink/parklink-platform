import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../data/services/road_routing_service.dart';
import 'app_theme.dart';

/// Campo de dirección con autocompletar de Google Maps.
///
/// Pensado para usarse dentro de sheets con fondo claro
/// (misma paleta que [buildAppSheetTheme]).
class AddressAutocompleteField extends StatefulWidget {
  const AddressAutocompleteField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.validator,
    required this.onPointChanged,
    this.routingService = const RoadRoutingService(),
    this.errorText,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final FormFieldValidator<String> validator;
  final ValueChanged<LatLng?> onPointChanged;
  final RoadRoutingService routingService;
  final String? errorText;

  @override
  State<AddressAutocompleteField> createState() =>
      _AddressAutocompleteFieldState();
}

class _AddressAutocompleteFieldState extends State<AddressAutocompleteField> {
  final _focusNode = FocusNode();
  Timer? _debounce;
  List<AddressSuggestion> _suggestions = const [];
  bool _loading = false;
  bool _selectingSuggestion = false;
  int _requestId = 0;
  String? _lookupError;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.controller.removeListener(_onTextChanged);
    _focusNode
      ..removeListener(_onFocusChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextFormField(
          controller: widget.controller,
          focusNode: _focusNode,
          textInputAction: TextInputAction.next,
          style: const TextStyle(color: appBlack),
          decoration: InputDecoration(
            labelText: widget.label,
            prefixIcon: Icon(widget.icon),
            errorText: widget.errorText ?? _lookupError,
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
          ),
          validator: widget.validator,
        ),
        if (_suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE1E1E1)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x18000000),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Column(
                children: [
                  for (var index = 0; index < _suggestions.length; index++) ...[
                    _AddressSuggestionTile(
                      suggestion: _suggestions[index],
                      onTap: () => _selectSuggestion(_suggestions[index]),
                    ),
                    if (index != _suggestions.length - 1)
                      const Divider(height: 1, color: Color(0xFFE8E8E8)),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  void _onTextChanged() {
    if (_selectingSuggestion) return;
    _debounce?.cancel();
    if (_focusNode.hasFocus) {
      widget.onPointChanged(null);
      if (_lookupError != null) {
        setState(() => _lookupError = null);
      }
    }
    final query = widget.controller.text.trim();
    if (!_focusNode.hasFocus || query.length < 3) {
      if (_suggestions.isNotEmpty || _loading) {
        setState(() {
          _suggestions = const [];
          _loading = false;
        });
      }
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 450), () {
      _loadSuggestions(query);
    });
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) return;

    // Al tocar una sugerencia el campo pierde el foco antes de que InkWell
    // complete el tap. Darle un instante evita borrar la opción seleccionada.
    Future<void>.delayed(const Duration(milliseconds: 150), () {
      if (!mounted || _focusNode.hasFocus || _selectingSuggestion) return;
      _debounce?.cancel();
      _requestId++;
      if (_suggestions.isNotEmpty || _loading) {
        setState(() {
          _suggestions = const [];
          _loading = false;
        });
      }
    });
  }

  Future<void> _loadSuggestions(String query) async {
    final requestId = ++_requestId;
    setState(() => _loading = true);
    try {
      final suggestions = await widget.routingService.addressSuggestions(query);
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _suggestions = suggestions;
        _loading = false;
        _lookupError = null;
      });
    } on RoadRoutingException catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _suggestions = const [];
        _loading = false;
        _lookupError = error.message;
      });
    } catch (_) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _suggestions = const [];
        _loading = false;
        _lookupError = 'No se pudo buscar direcciones. Revisa tu conexión.';
      });
    }
  }

  Future<void> _selectSuggestion(AddressSuggestion suggestion) async {
    _debounce?.cancel();
    _requestId++;
    _selectingSuggestion = true;
    setState(() {
      _suggestions = const [];
      _loading = true;
      _lookupError = null;
    });
    try {
      final resolved = await widget.routingService.resolveSuggestion(
        suggestion,
      );
      if (!mounted) return;
      widget.controller.value = TextEditingValue(
        text: resolved.label,
        selection: TextSelection.collapsed(offset: resolved.label.length),
      );
      widget.onPointChanged(resolved.point);
      _focusNode.unfocus();
      setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      widget.onPointChanged(null);
      setState(() {
        _loading = false;
        _lookupError = 'No se pudo confirmar esta dirección.';
      });
    } finally {
      _selectingSuggestion = false;
    }
  }
}

class _AddressSuggestionTile extends StatelessWidget {
  const _AddressSuggestionTile({required this.suggestion, required this.onTap});

  final AddressSuggestion suggestion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final parts = suggestion.label.split(', ');
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            const Icon(Icons.location_on_outlined, color: appBlack, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    parts.first,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: appBlack,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (parts.length > 1)
                    Text(
                      parts.skip(1).join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF666666),
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
