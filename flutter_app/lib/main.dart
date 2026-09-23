import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:erp/app.dart';
import 'package:erp/core/auth/auth_provider.dart';
import 'package:erp/core/db/database_service.dart';
import 'package:erp/shared/ui/theme/app_colors.dart';
import 'package:erp/shared/ui/theme/app_spacing.dart';
import 'package:erp/modules/parametres/services/parametres_service.dart';
import 'package:erp/shared/ui/widgets/identite_societe.dart';
import 'package:erp/shared/ui/theme/app_text_styles.dart';
import 'package:erp/shared/ui/theme/app_theme.dart';
import 'package:erp/shared/ui/widgets/logo_mark.dart';

void main() {
  runApp(const StockApp());
}

/// Lets desktop users drag-scroll long tables with the mouse, which the
/// default Material behaviour restricts to touch devices.
class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

class StockApp extends StatelessWidget {
  const StockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: IdentiteSociete.instance,
      builder: (context, _) => _app(),
    );
  }

  Widget _app() {
    return ChangeNotifierProvider(
      create: (_) => AuthProvider(),
      child: MaterialApp(
        // Le titre suit le nom de l'entreprise dès qu'il est connu : la
        // barre des tâches est l'endroit où l'on cherche sa fenêtre.
        title: IdentiteSociete.instance.titreFenetre,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        scrollBehavior: const _AppScrollBehavior(),
        home: const _SplashGate(),
      ),
    );
  }
}

/// Awaits database initialization (seed copy on first launch) before
/// showing the rest of the app. This is the single-process equivalent
/// of "backend and frontend starting together".
class _SplashGate extends StatefulWidget {
  const _SplashGate();

  @override
  State<_SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<_SplashGate> {
  late final Future<void> _bootFuture;

  @override
  void initState() {
    super.initState();
    _bootFuture = _boot();
  }

  Future<void> _boot() async {
    // Touch the database so the seed copy + table creation happens here,
    // before the rest of the app (auth, navigation) is shown.
    final db = await DatabaseService.instance.database;
    await db.rawQuery('SELECT COUNT(*) FROM products');
    // Le nom de l'entreprise se lit une fois, ici : il s'affiche sur
    // chaque écran et le relire à chaque construction ferait une requête
    // par image.
    IdentiteSociete.instance
        .definir((await ParametresService().societe()).name);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _bootFuture,
      builder: (context, snapshot) {
        final Widget child;
        if (snapshot.connectionState != ConnectionState.done) {
          child = const _SplashScreen();
        } else if (snapshot.hasError) {
          child = _SplashScreen(error: snapshot.error.toString());
        } else {
          child = const AuthGate();
        }
        // Cross-fade from the splash into the app so startup reads as one
        // continuous motion rather than a jump between two screens.
        return AnimatedSwitcher(
          duration: AppDurations.slow,
          switchInCurve: AppCurves.enter,
          child: child,
        );
      },
    );
  }
}

class _SplashScreen extends StatelessWidget {
  final String? error;

  const _SplashScreen({this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const LogoLockup(markSize: 64, titleSize: 34),
              const SizedBox(height: AppSpacing.xxxl),
              if (error == null)
                const SizedBox(
                  width: 180,
                  child: ClipRRect(
                    borderRadius: BorderRadius.all(
                      Radius.circular(AppRadius.pill),
                    ),
                    child: LinearProgressIndicator(minHeight: 3),
                  ),
                )
              else
                Container(
                  constraints: const BoxConstraints(maxWidth: 420),
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: AppColors.errorBg,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: AppColors.error,
                        size: 22,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      const Text(
                        'Impossible d\'ouvrir la base de données',
                        style: AppTextStyles.bodyStrong,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        error!,
                        style: const TextStyle(
                          color: AppColors.error,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
