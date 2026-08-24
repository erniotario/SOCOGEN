import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../widgets/logo_mark.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _passwordFocus = FocusNode();

  bool _submitting = false;
  bool _obscure = true;
  String? _localError;

  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: AppDurations.slow,
  )..forward();

  @override
  void dispose() {
    _intro.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit(AuthProvider auth) async {
    if (_submitting) return;
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final isSetup = auth.status == AuthStatus.setupRequired;

    if (username.isEmpty || password.isEmpty) {
      setState(() => _localError = 'Renseignez le nom et le mot de passe.');
      return;
    }
    if (isSetup && password != _confirmController.text) {
      setState(
        () => _localError = 'Les deux mots de passe ne correspondent pas.',
      );
      return;
    }

    setState(() {
      _submitting = true;
      _localError = null;
    });

    final ok = isSetup
        ? await auth.createAdminAccount(username, password)
        : await auth.login(username, password);

    if (!mounted) return;
    setState(() => _submitting = false);
    if (!ok && auth.error != null) {
      setState(() => _localError = auth.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isSetup = auth.status == AuthStatus.setupRequired;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: FadeTransition(
            opacity: _intro,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(parent: _intro, curve: AppCurves.enter),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LogoLockup(
                      subtitle: isSetup
                          ? 'Configuration initiale'
                          : 'Gestion de Stock',
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.xxl),
                      decoration: appSurfaceDecoration(
                        color: AppColors.surface,
                        radius: AppRadius.xl,
                        border: AppColors.borderStrong,
                        shadows: AppShadows.medium,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            isSetup
                                ? 'Créer le compte administrateur'
                                : 'Connexion',
                            style: AppTextStyles.cardTitle,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            isSetup
                                ? 'Ce compte pourra gérer les utilisateurs et '
                                    'les paramètres de la société.'
                                : 'Identifiez-vous pour accéder au stock.',
                            style: AppTextStyles.bodyMuted,
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          _LoginField(
                            controller: _usernameController,
                            label: "Nom d'utilisateur",
                            icon: Icons.person_outline,
                            textInputAction: TextInputAction.next,
                            onSubmitted: (_) => _passwordFocus.requestFocus(),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _LoginField(
                            controller: _passwordController,
                            focusNode: _passwordFocus,
                            label: 'Mot de passe',
                            icon: Icons.lock_outline,
                            obscure: _obscure,
                            textInputAction: isSetup
                                ? TextInputAction.next
                                : TextInputAction.done,
                            suffix: IconButton(
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                size: 18,
                              ),
                              tooltip: _obscure ? 'Afficher' : 'Masquer',
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                            onSubmitted: isSetup ? null : (_) => _submit(auth),
                          ),
                          if (isSetup) ...[
                            const SizedBox(height: AppSpacing.md),
                            _LoginField(
                              controller: _confirmController,
                              label: 'Confirmer le mot de passe',
                              icon: Icons.lock_reset_outlined,
                              obscure: _obscure,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _submit(auth),
                            ),
                          ],
                          AnimatedSize(
                            duration: AppDurations.fast,
                            curve: AppCurves.standard,
                            child: _localError == null
                                ? const SizedBox(width: double.infinity)
                                : Padding(
                                    padding: const EdgeInsets.only(
                                      top: AppSpacing.md,
                                    ),
                                    child: _ErrorBanner(message: _localError!),
                                  ),
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          SizedBox(
                            height: 46,
                            child: ElevatedButton(
                              onPressed:
                                  _submitting ? null : () => _submit(auth),
                              child: _submitting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(
                                      isSetup
                                          ? 'Créer le compte'
                                          : 'Se connecter',
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    const Text(
                      'SHEMAB • Yaoundé, Cameroun',
                      style: AppTextStyles.captionMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.errorBg,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 16, color: AppColors.error),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12, color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscure;
  final Widget? suffix;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  const _LoginField({
    required this.controller,
    required this.label,
    required this.icon,
    this.obscure = false,
    this.suffix,
    this.focusNode,
    this.textInputAction,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscure,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18),
        suffixIcon: suffix,
        filled: true,
        fillColor: AppColors.bg,
      ),
    );
  }
}
