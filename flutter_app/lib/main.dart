import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'auth/auth_provider.dart';
import 'data/db/database_service.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const SocogenApp());
}

class SocogenApp extends StatelessWidget {
  const SocogenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AuthProvider(),
      child: MaterialApp(
        title: 'SOCOGEN',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
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
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _bootFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _SplashScreen();
        }
        if (snapshot.hasError) {
          return _SplashScreen(error: snapshot.error.toString());
        }
        return const AuthGate();
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'SOCOGEN',
              style: TextStyle(
                fontSize: 42,
                fontWeight: FontWeight.w800,
                color: AppColors.accentLight,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Gestion de Stock',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            if (error == null)
              const SizedBox(
                width: 200,
                child: LinearProgressIndicator(
                  color: AppColors.accent,
                  backgroundColor: AppColors.surface,
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  error!,
                  style: const TextStyle(color: AppColors.error, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
