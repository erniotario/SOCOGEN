import 'package:flutter/material.dart';

import 'package:erp/shared/ui/theme/app_branding.dart';
import 'package:erp/shared/ui/widgets/identite_societe.dart';
import 'package:erp/shared/ui/theme/app_colors.dart';
import 'package:erp/shared/ui/theme/app_spacing.dart';

/// The app mark: a gradient tile carrying the initial of whatever name
/// the interface is showing.
///
/// Used by the sidebar, the rail, the login card and the splash screen.
/// The letter follows `IdentiteSociete` rather than being engraved: a
/// hard-coded initial is how the previous owner's identity survived the
/// rename, and a tile reading `S` above « Maison Kamdem » would say the
/// software still belongs to someone else.
class LogoMark extends StatelessWidget {
  final double size;

  const LogoMark({super.key, this.size = 34});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.accentLight, AppColors.accent],
        ),
        borderRadius: BorderRadius.circular(size * 0.26),
        boxShadow: AppShadows.low,
      ),
      alignment: Alignment.center,
      child: Text(
        IdentiteSociete.instance.initiale,
        style: TextStyle(
          fontSize: size * 0.52,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          height: 1.1,
        ),
      ),
    );
  }
}

/// The app mark next to the product name — the lockup used on the login
/// card and the splash screen.
class LogoLockup extends StatelessWidget {
  final double markSize;
  final double titleSize;
  /// Nul pour le sous-titre par défaut, qui nomme le produit.
  final String? subtitle;

  const LogoLockup({
    super.key,
    this.markSize = 44,
    this.titleSize = 26,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    // L'entreprise d'abord, ici aussi : l'écran de connexion est le
    // premier que quelqu'un voit le matin, et il doit reconnaître sa
    // maison. Le produit reste en sous-titre pour dire de quel logiciel
    // il s'agit.
    final identite = IdentiteSociete.instance;
    final sousTitre = subtitle ??
        (identite.estConnu
            ? '${AppBranding.productName} · ${AppBranding.tagline}'
            : AppBranding.tagline);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LogoMark(size: markSize),
        const SizedBox(height: AppSpacing.md),
        Text(
          identite.affichable,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: titleSize,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          sousTitre,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
