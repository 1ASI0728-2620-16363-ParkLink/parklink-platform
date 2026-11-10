import 'package:flutter/material.dart';

import '../../../core/app_theme.dart';
import '../../../../ui/core/app_scope.dart';
import '../view_models/login_view_model.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({this.onLogin, this.onRegister, super.key});
  final Future<void> Function(String, String)? onLogin;
  final VoidCallback? onRegister;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _lime = appLime;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  late final LoginViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = widget.onLogin != null
        ? LoginViewModel(loginAction: widget.onLogin)
        : LoginViewModel(authRepository: AppScope.of(context, listen: false).authRepository);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/images/login_bg.png', fit: BoxFit.cover),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.6, -0.75),
                    radius: 1.05,
                    colors: [
                      _lime.withValues(alpha: 0.36),
                      _lime.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.topLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 620),
                          child: const Padding(
                            padding: EdgeInsets.fromLTRB(26, 42, 26, 32),
                            child: _LoginIntroduction(),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 560),
                          child: _LoginCard(
                            viewModel: _viewModel,
                            emailController: _emailController,
                            passwordController: _passwordController,
                             onSubmit: _login,
                             onRegister: widget.onRegister,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _login() async {
    final ok = await _viewModel.login(
      _emailController.text,
      _passwordController.text,
    );
    if (ok && mounted) FocusScope.of(context).unfocus();
  }
}

class _LoginIntroduction extends StatelessWidget {
  const _LoginIntroduction();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Image.asset('assets/images/parklink_logo_transparent.png', width: 200, semanticLabel: 'ParkLink'),
        const SizedBox(height: 22),
        const Text(
          'Tu lugar,\nmás cerca.',
          style: TextStyle(
            color: Colors.white,
            fontSize: 48,
            height: 0.94,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.96,
            fontFamily: 'Inter',
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Encuentra estacionamiento o comparte tu espacio. '
          'Consulta el precio antes de reservar.',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            height: 1.25,
            letterSpacing: -0.4,
            fontFamily: 'Helvetica',
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Estacionamientos entre personas.',
          style: TextStyle(
            color: appLime,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.34,
            fontFamily: 'Helvetica',
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'ParkLink · Lima, Perú',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.86),
            fontSize: 16,
            fontWeight: FontWeight.w300,
            letterSpacing: -0.32,
            fontFamily: 'Helvetica',
          ),
        ),
      ],
    );
  }
}

class _LoginCard extends StatefulWidget {
  const _LoginCard({
    required this.viewModel,
    required this.emailController,
    required this.passwordController,
    required this.onSubmit,
    this.onRegister,
  });

  final LoginViewModel viewModel;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final Future<void> Function() onSubmit;
  final VoidCallback? onRegister;

  @override
  State<_LoginCard> createState() => _LoginCardState();
}

class _LoginCardState extends State<_LoginCard> {
  bool _obscurePassword = true;

  @override
  Widget build(BuildContext context) {
    final viewModel = widget.viewModel;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(38, 28, 38, 38 + bottomInset),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [
          BoxShadow(
            color: Color(0x40000000),
            offset: Offset(0, -6),
            blurRadius: 18,
          ),
        ],
      ),
      child: ListenableBuilder(
        listenable: viewModel,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Inicio de sesión',
              style: TextStyle(
                color: Colors.black,
                fontSize: 26,
                height: 1,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                fontFamily: 'Helvetica',
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Ingresa con tu cuenta de conductor o propietario.',
              style: TextStyle(
                color: Color(0xFF5C5C5C),
                fontSize: 13,
                height: 1.35,
                fontFamily: 'Helvetica',
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: widget.emailController,
              autofillHints: const [
                AutofillHints.username,
                AutofillHints.email,
              ],
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              enabled: !viewModel.isLoading,
              style: const TextStyle(color: Colors.black),
              cursorColor: Colors.black,
              decoration: _fieldDecoration('Correo o usuario'),
            ),
            const SizedBox(height: 13),
            TextField(
              controller: widget.passwordController,
              autofillHints: const [AutofillHints.password],
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              enabled: !viewModel.isLoading,
              onSubmitted: (_) => widget.onSubmit(),
              style: const TextStyle(color: Colors.black),
              cursorColor: Colors.black,
              decoration: _fieldDecoration('Contraseña').copyWith(
                suffixIcon: IconButton(
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                  tooltip: _obscurePassword
                      ? 'Mostrar contraseña'
                      : 'Ocultar contraseña',
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: const Color(0xFF5C5C5C),
                  ),
                ),
              ),
            ),
            if (viewModel.errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Semantics(
                  liveRegion: true,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: const BoxDecoration(
                            color: _LoginScreenState._lime,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.priority_high_rounded,
                            color: Colors.black,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            viewModel.errorMessage!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              const SizedBox(height: 17),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: viewModel.isLoading ? null : widget.onSubmit,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: _LoginScreenState._lime,
                  foregroundColor: appBlack,
                  disabledBackgroundColor: _LoginScreenState._lime.withValues(
                    alpha: 0.6,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                child: viewModel.isLoading
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: appWhite,
                        ),
                      )
                    : const Text(
                        'Ingresar',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                          fontFamily: 'Helvetica',
                        ),
                      ),
              ),
            ),
            if (widget.onRegister != null)
              TextButton(onPressed: widget.onRegister, child: const Text('Crear una cuenta', style: TextStyle(color: appBlack))),
          ],
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(String label) {
    const border = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(13)),
      borderSide: BorderSide(color: Colors.black),
    );
    return const InputDecoration(
      filled: true,
      fillColor: Colors.white,
      labelStyle: TextStyle(color: Color(0xFF5C5C5C)),
      floatingLabelStyle: TextStyle(
        color: Colors.black,
        fontWeight: FontWeight.w700,
        backgroundColor: Colors.white,
      ),
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(13)),
        borderSide: BorderSide(color: Colors.black, width: 1.5),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    ).copyWith(labelText: label);
  }
}
