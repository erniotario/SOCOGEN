import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:erp/core/auth/auth_provider.dart';
import 'package:erp/modules/parametres/repositories/settings_repository.dart';
import 'package:erp/modules/parametres/ui/company_setup_screen.dart';
import 'package:erp/core/auth/ui/login_screen.dart';
import 'package:erp/shared/ui/theme/app_colors.dart';
import 'package:erp/shared/ui/theme/app_spacing.dart';
import 'package:erp/shared/ui/widgets/logo_mark.dart';
import 'package:erp/shell/nav_shell.dart';

/// Decides which screen to show based on [AuthProvider.status]:
/// loading -> setup/login -> main navigation shell.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _settings = SettingsRepository();

  /// Null until the question has been asked of the database. Only a
  /// brand-new install answers false; see
  /// [SettingsRepository.isCompanyConfigured].
  bool? _companyConfigured;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthProvider>().checkSetup();
    });
  }

  bool _loadingConfigured = false;

  Future<void> _loadCompanyConfigured() async {
    if (_loadingConfigured) return;
    _loadingConfigured = true;
    final configured = await _settings.isCompanyConfigured();
    if (!mounted) return;
    setState(() => _companyConfigured = configured);
  }

  @override
  Widget build(BuildContext context) {
    final status = context.watch<AuthProvider>().status;
    switch (status) {
      case AuthStatus.unknown:
        return const _Booting();
      case AuthStatus.setupRequired:
      case AuthStatus.loggedOut:
        return const LoginScreen();
      case AuthStatus.loggedIn:
        // Asked after sign-in rather than before it, so the answer is
        // given by someone who has proved they own this installation.
        if (_companyConfigured == null) {
          _loadCompanyConfigured();
          return const _Booting();
        }
        if (_companyConfigured == false) {
          return CompanySetupScreen(
            onDone: () => setState(() => _companyConfigured = true),
          );
        }
        return const NavShell();
    }
  }
}

/// The lockup shown while the app decides what to display: the same mark
/// as the native splash, so the hand-off between boot and first screen is
/// invisible.
class _Booting extends StatelessWidget {
  const _Booting();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LogoLockup(markSize: 64, titleSize: 34),
            SizedBox(height: AppSpacing.xxxl),
            SizedBox(
              width: 180,
              child: LinearProgressIndicator(minHeight: 3),
            ),
          ],
        ),
      ),
    );
  }
}
