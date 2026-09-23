import 'package:flutter/material.dart';

import 'package:erp/shared/models/company_settings.dart';
import 'package:erp/modules/parametres/repositories/settings_repository.dart';
import 'package:erp/modules/stock/repositories/store_repository.dart';
import 'package:erp/shared/ui/theme/app_colors.dart';
import 'package:erp/shared/ui/theme/app_spacing.dart';
import 'package:erp/shared/ui/theme/app_text_styles.dart';
import 'package:erp/shared/ui/widgets/logo_mark.dart';
import 'package:erp/core/errors/messages.dart';
import 'package:erp/shared/ui/widgets/identite_societe.dart';

/// Asked once, on a brand-new database, right after the first
/// administrator account is created.
///
/// Before this existed, a new business opened the app to another
/// customer's name on its reports and that customer's three warehouses in
/// its Magasins list. Nothing was broken, but nothing said "yours"
/// either, and the storekeeper's first impression was of somebody else's
/// premises.
///
/// The skip is not a convenience: a second device of the *same* business
/// must not invent its own magasins, because they would merge into the
/// first device's list as duplicates on the next sync. Such a device says
/// so here and takes both the company and its magasins from that sync.
class CompanySetupScreen extends StatefulWidget {
  /// Called once the answer is recorded, so the shell can take over.
  final VoidCallback onDone;

  final SettingsRepository? settingsRepository;
  final StoreRepository? storeRepository;

  const CompanySetupScreen({
    super.key,
    required this.onDone,
    this.settingsRepository,
    this.storeRepository,
  });

  @override
  State<CompanySetupScreen> createState() => _CompanySetupScreenState();
}

class _CompanySetupScreenState extends State<CompanySetupScreen> {
  late final SettingsRepository _settings =
      widget.settingsRepository ?? SettingsRepository();
  late final StoreRepository _stores =
      widget.storeRepository ?? StoreRepository();

  final _nameController = TextEditingController();
  final _cityController = TextEditingController();

  /// One controller per magasin row. Starts at a single empty field
  /// rather than a prefilled list: a suggestion here would be the same
  /// inherited identity this screen exists to remove.
  final List<TextEditingController> _storeControllers = [
    TextEditingController(),
  ];

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _cityController.dispose();
    for (final controller in _storeControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _addStoreField() {
    setState(() => _storeControllers.add(TextEditingController()));
  }

  void _removeStoreField(int index) {
    setState(() => _storeControllers.removeAt(index).dispose());
  }

  /// Trimmed, in the order typed, with blanks dropped.
  List<String> get _storeNames => _storeControllers
      .map((c) => c.text.trim())
      .where((name) => name.isNotEmpty)
      .toList();

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final stores = _storeNames;

    if (name.isEmpty) {
      setState(() => _error = "Indiquez le nom de l'entreprise.");
      return;
    }
    if (stores.isEmpty) {
      setState(
        () => _error = 'Ajoutez au moins un magasin, ou choisissez la '
            'synchronisation ci-dessous.',
      );
      return;
    }
    final lowered = stores.map((s) => s.toLowerCase()).toList();
    if (lowered.toSet().length != lowered.length) {
      setState(() => _error = 'Deux magasins portent le même nom.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _settings.saveSettings(
        CompanySettings(name: name, city: _cityController.text.trim()),
      );
      // Dès la première saisie : c'est ce nom que la barre latérale,
      // l'écran de connexion et les documents afficheront.
      IdentiteSociete.instance.definir(name);
      for (final store in stores) {
        await _stores.createStore(store);
      }
      await _settings.markCompanyConfigured();
      widget.onDone();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = messagePour(e, operation: 'la configuration');
      });
    }
  }

  /// Records that the question was answered without creating anything, so
  /// the screen does not return on the next launch.
  Future<void> _skipForSync() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _settings.markCompanyConfigured();
      widget.onDone();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = messagePour(e, operation: 'la configuration');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const LogoLockup(subtitle: 'Configuration initiale'),
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
                      const Text(
                        'Votre entreprise',
                        style: AppTextStyles.cardTitle,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      const Text(
                        "Ce nom apparaît sur vos rapports. Vous pourrez le "
                        'modifier dans Paramètres.',
                        style: AppTextStyles.bodyMuted,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      TextField(
                        controller: _nameController,
                        autofocus: true,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: "Nom de l'entreprise *",
                          hintText: 'Ex : ETS KAMGA & FILS',
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextField(
                        controller: _cityController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Ville',
                          hintText: 'Ex : Yaoundé, Cameroun',
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      const Text('VOS MAGASINS', style: AppTextStyles.sectionLabel),
                      const SizedBox(height: AppSpacing.xs),
                      const Text(
                        'Les lieux où votre stock est rangé. Vous pourrez en '
                        'ajouter à tout moment.',
                        style: AppTextStyles.bodyMuted,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      for (var i = 0; i < _storeControllers.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _storeControllers[i],
                                  textCapitalization: TextCapitalization.words,
                                  decoration: InputDecoration(
                                    labelText: 'Magasin ${i + 1}',
                                    hintText: 'Ex : Dépôt central',
                                  ),
                                  onSubmitted: (_) => _addStoreField(),
                                ),
                              ),
                              // The first row has no remove button: at
                              // least one field must stay on screen for
                              // the form to make sense.
                              if (_storeControllers.length > 1) ...[
                                const SizedBox(width: AppSpacing.xs),
                                IconButton(
                                  onPressed: _saving
                                      ? null
                                      : () => _removeStoreField(i),
                                  icon: const Icon(Icons.close),
                                  tooltip: 'Retirer ce magasin',
                                  color: AppColors.textSecondary,
                                ),
                              ],
                            ],
                          ),
                        ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _saving ? null : _addStoreField,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Ajouter un magasin'),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: AppSpacing.md),
                        _ErrorBanner(message: _error!),
                      ],
                      const SizedBox(height: AppSpacing.xl),
                      SizedBox(
                        height: 46,
                        child: ElevatedButton(
                          onPressed: _saving ? null : _save,
                          child: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Enregistrer et commencer'),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextButton(
                        onPressed: _saving ? null : _skipForSync,
                        child: const Text(
                          'Je vais synchroniser avec un autre appareil',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
