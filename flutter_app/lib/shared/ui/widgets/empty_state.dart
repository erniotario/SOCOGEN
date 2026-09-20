import 'package:flutter/material.dart';

import 'package:socogen/shared/ui/theme/app_colors.dart';
import 'package:socogen/shared/ui/theme/app_spacing.dart';
import 'package:socogen/shared/ui/theme/app_text_styles.dart';

/// Placeholder shown when a list or table has nothing to display.
///
/// An icon plus a short explanation reads as a deliberate state rather
/// than a failure, and the optional [action] gives the user the obvious
/// next step (usually "add the first record").
class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  // Centré quand il y a la place, défilant quand il n'y en a pas.
  //
  // L'icône, le titre, la phrase et le bouton font ensemble près de
  // 290 px : plus que la hauteur utile d'un téléphone en paysage une
  // fois l'en-tête et les filtres posés. Sans ce défilement, l'état
  // vide débordait de 139 px — et un état vide est précisément ce que
  // voit une installation neuve, donc le tout premier écran d'un
  // nouveau client.
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, contraintes) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight:
                contraintes.hasBoundedHeight ? contraintes.maxHeight : 0,
          ),
          child: _contenu(),
        ),
      ),
    );
  }

  Widget _contenu() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.elevated,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(icon, size: 26, color: AppColors.textMuted),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.cardTitle,
            ),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.xs),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMuted,
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Error counterpart of [AppEmptyState], with a retry affordance.
class AppErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const AppErrorState({super.key, required this.message, this.onRetry});

  // Même traitement que [AppEmptyState] ci-dessus, et pour la
  // même raison : cet état-là aussi s'affiche dans un panneau
  // qui peut être court.
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, contraintes) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight:
                contraintes.hasBoundedHeight ? contraintes.maxHeight : 0,
          ),
          child: _contenu(),
        ),
      ),
    );
  }

  Widget _contenu() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.errorBg,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
              ),
              child: const Icon(
                Icons.error_outline,
                size: 26,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text('Une erreur est survenue', style: AppTextStyles.cardTitle),
            const SizedBox(height: AppSpacing.xs),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMuted,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Réessayer'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
