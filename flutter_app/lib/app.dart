import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'auth/auth_provider.dart';
import 'screens/login_screen.dart';
import 'theme/app_colors.dart';
import 'theme/app_spacing.dart';
import 'widgets/logo_mark.dart';
import 'widgets/nav_shell.dart';

/// Decides which screen to show based on [AuthProvider.status]:
/// loading -> setup/login -> main navigation shell.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthProvider>().checkSetup();
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = context.watch<AuthProvider>().status;
    switch (status) {
      case AuthStatus.unknown:
        // Same lockup as the splash, so the hand-off between boot and
        // auth is invisible to the user.
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
      case AuthStatus.setupRequired:
      case AuthStatus.loggedOut:
        return const LoginScreen();
      case AuthStatus.loggedIn:
        return const NavShell();
    }
  }
}
