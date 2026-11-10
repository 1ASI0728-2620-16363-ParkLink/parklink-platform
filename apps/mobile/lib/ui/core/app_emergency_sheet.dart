import 'package:flutter/material.dart';

import 'app_theme.dart';

class AppEmergencySheet extends StatefulWidget {
  const AppEmergencySheet({
    required this.onSend,
    required this.errorMessage,
    super.key,
  });

  final Future<bool> Function() onSend;
  final String? Function() errorMessage;

  @override
  State<AppEmergencySheet> createState() => _AppEmergencySheetState();
}

class _AppEmergencySheetState extends State<AppEmergencySheet> {
  bool _sending = false;
  bool _sent = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      child: _sent
          ? const SizedBox(
              key: ValueKey('sos-sent'),
              height: 320,
              child: _EmergencyConfirmation(),
            )
          : SafeArea(
              key: const ValueKey('sos-confirmation'),
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: appLime,
                            borderRadius: BorderRadius.circular(17),
                          ),
                          child: const Icon(
                            Icons.sos_rounded,
                            color: appBlack,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Alerta de emergencia',
                                style: TextStyle(
                                  color: appBlack,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Úsala si necesitas ayuda inmediata.',
                                style: TextStyle(color: Color(0xFF666666)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F1EE),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.shield_outlined, color: appBlack),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Enviaremos tu información y la ruta activa al equipo de Centinela para que puedan contactarte.',
                              style: TextStyle(
                                color: appBlack,
                                height: 1.35,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        _error!,
                        style: const TextStyle(
                          color: Color(0xFFB3261E),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final cancel = OutlinedButton(
                          onPressed: _sending
                              ? null
                              : () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: appBlack,
                          ),
                          child: const Text('Cancelar'),
                        );
                        final send = FilledButton.icon(
                          onPressed: _sending ? null : _send,
                          style: FilledButton.styleFrom(
                            backgroundColor: appBlack,
                            foregroundColor: appWhite,
                          ),
                          icon: _sending
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: appWhite,
                                  ),
                                )
                              : const Icon(Icons.sos_rounded, color: appLime),
                          label: Text(_sending ? 'Enviando…' : 'Enviar SOS'),
                        );
                        if (constraints.maxWidth < 300) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              send,
                              const SizedBox(height: 10),
                              cancel,
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: cancel),
                            const SizedBox(width: 12),
                            Expanded(flex: 2, child: send),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    final sent = await widget.onSend();
    if (!mounted) return;
    if (!sent) {
      setState(() {
        _sending = false;
        _error = widget.errorMessage();
      });
      return;
    }
    setState(() => _sent = true);
    await Future<void>.delayed(const Duration(milliseconds: 1300));
    if (mounted) Navigator.pop(context);
  }
}

class _EmergencyConfirmation extends StatelessWidget {
  const _EmergencyConfirmation();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: const BoxDecoration(
              color: appLime,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded, color: appWhite, size: 52),
          ),
          const SizedBox(height: 22),
          Text(
            'SOS enviado',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          const Text(
            'Nos pondremos en contacto contigo pronto.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF666666)),
          ),
        ],
      ),
    );
  }
}
