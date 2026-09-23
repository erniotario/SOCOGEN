import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:erp/shared/models/company_settings.dart';
import 'package:erp/modules/parametres/repositories/settings_repository.dart';
import 'package:erp/shared/ui/theme/app_colors.dart';
import 'package:erp/shared/ui/theme/app_text_styles.dart';
import 'package:erp/shared/ui/theme/app_breakpoints.dart';
import 'package:erp/shared/ui/theme/app_spacing.dart';
import 'package:erp/shared/ui/widgets/empty_state.dart';
import 'package:erp/shared/ui/widgets/identite_societe.dart';
import 'package:erp/shared/ui/widgets/page_header.dart';
import 'package:erp/shared/ui/widgets/responsive_row.dart';
import 'package:erp/shared/ui/widgets/section_card.dart';
import 'package:erp/core/errors/messages.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _settingsRepo = SettingsRepository();
  late Future<CompanySettings> _future;

  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _phoneController = TextEditingController();
  final _seuilController = TextEditingController();
  final _emailController = TextEditingController();
  final _websiteController = TextEditingController();
  final _taxIdController = TextEditingController();
  final _rccmController = TextEditingController();

  String _logoPath = '';
  String? _statusMessage;
  bool _statusIsError = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _seuilController.dispose();
    _nameController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _websiteController.dispose();
    _taxIdController.dispose();
    _rccmController.dispose();
    super.dispose();
  }

  Future<CompanySettings> _load() async {
    final settings = await _settingsRepo.getSettings();
    _applySettings(settings);
    return settings;
  }

  /// La dernière version lue.
  ///
  /// Gardée parce que cet écran ne modifie qu'une partie de la fiche :
  /// reconstruire un `CompanySettings` complet à l'enregistrement
  /// remettait en silence la devise à XAF pour une entreprise qui
  /// comptait en euros.
  CompanySettings _courant = const CompanySettings();

  void _applySettings(CompanySettings s) {
    _courant = s;
    _seuilController.text = s.seuilStockParDefaut.toString();
    _nameController.text = s.name;
    _addressController.text = s.address;
    _cityController.text = s.city;
    _phoneController.text = s.phone;
    _emailController.text = s.email;
    _websiteController.text = s.website;
    _taxIdController.text = s.taxId;
    _rccmController.text = s.rccm;
    _logoPath = s.logoPath;
  }

  Future<void> _reset() async {
    final settings = await _settingsRepo.getSettings();
    if (!mounted) return;
    setState(() {
      _applySettings(settings);
      _statusMessage = null;
    });
  }

  Future<void> _pickLogo() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'bmp'],
    );
    final path = result?.files.single.path;
    if (path != null) setState(() => _logoPath = path);
  }

  void _clearLogo() => setState(() => _logoPath = '');

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final seuil = int.tryParse(_seuilController.text.trim());
      if (seuil == null || seuil < 0) {
        setState(() {
          _saving = false;
          _statusMessage =
              "Le seuil d'alerte doit être un nombre entier positif.";
          _statusIsError = true;
        });
        return;
      }
      // copyWith, et non un objet neuf : ce qui n'est pas sur cet écran
      // — la devise, par exemple — doit survivre à un enregistrement.
      await _settingsRepo.saveSettings(_courant.copyWith(
        // Un champ vidé veut dire que le nom est inconnu, pas qu'il est
        // celui du premier client.
        name: _nameController.text.trim(),
        address: _addressController.text.trim(),
        city: _cityController.text.trim(),
        phone: _phoneController.text.trim(),
        email: _emailController.text.trim(),
        website: _websiteController.text.trim(),
        taxId: _taxIdController.text.trim(),
        rccm: _rccmController.text.trim(),
        logoPath: _logoPath,
        seuilStockParDefaut: seuil,
      ));
      // La barre latérale et l'écran de connexion lisent ce nom : sans
      // cette ligne, ils garderaient l'ancien jusqu'au prochain
      // démarrage.
      IdentiteSociete.instance.definir(_nameController.text.trim());
      if (!mounted) return;
      setState(() {
        _saving = false;
        _statusMessage = 'Paramètres enregistrés avec succès.';
        _statusIsError = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _statusMessage = messagePour(e, operation: "l'enregistrement des paramètres");
        _statusIsError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = AppSpacing.pagePadding(context.windowSize);
    return Column(
      children: [
        const PageHeader(
          title: 'Paramètres',
          subtitle: 'Informations affichées dans les en-têtes des rapports PDF',
        ),
        Expanded(
          child: FutureBuilder<CompanySettings>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return AppErrorState(message: '${snapshot.error}');
              }
              return ListView(
                padding: padding,
                children: [
                  SectionCard(
                    icon: Icons.apartment_outlined,
                    title: 'IDENTITÉ DE LA SOCIÉTÉ',
                    children: [
                      ResponsiveRow(
                        items: [
                          RowItem(
                            flex: 3,
            child:                             _LabeledField(
                              label: 'Nom de la société',
                              required: true,
                              controller: _nameController,
                              hintText: 'Ex : ETS KAMGA & FILS',
                            ),
                          ),
                          RowItem(
                            flex: 2,
            child:                             _LabeledField(
                              label: 'N° Contribuable',
                              controller: _taxIdController,
                              hintText: 'Ex : M123456789',
                            ),
                          ),
                          RowItem(
                            flex: 2,
            child:                             _LabeledField(
                              label: 'RCCM',
                              controller: _rccmController,
                              hintText: 'Ex : RC/YAO/2020/B/1234',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      ResponsiveRow(
                        items: [
                          RowItem(
                            flex: 3,
            child:                             _LabeledField(
                              label: 'Adresse',
                              controller: _addressController,
                              hintText: 'Ex : BP 1234, Rue des Palmiers',
                            ),
                          ),
                          RowItem(
                            flex: 2,
            child:                             _LabeledField(
                              label: 'Ville / Pays',
                              controller: _cityController,
                              hintText: 'Ex : Yaoundé, Cameroun',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SectionCard(
                    icon: Icons.contact_phone_outlined,
                    title: 'COORDONNÉES',
                    children: [
                      ResponsiveRow(
                        items: [
                          RowItem(
                            child: _LabeledField(
                              label: 'Téléphone',
                              controller: _phoneController,
                              hintText: 'Ex : +237 6XX XXX XXX',
                            ),
                          ),
                          RowItem(
                            child: _LabeledField(
                              label: 'Email',
                              controller: _emailController,
                              hintText: 'Ex : contact@monentreprise.cm',
                            ),
                          ),
                          RowItem(
                            child: _LabeledField(
                              label: 'Site web',
                              controller: _websiteController,
                              hintText: 'Ex : www.monentreprise.cm',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SectionCard(
                    icon: Icons.inventory_outlined,
                    title: 'STOCK',
                    children: [
                      ResponsiveRow(
                        items: [
                          RowItem(
                            child: _LabeledField(
                              label: "Seuil d'alerte par défaut",
                              controller: _seuilController,
                              hintText: 'Ex : 10',
                            ),
                          ),
                          const RowItem(
                            child: Padding(
                              padding: EdgeInsets.only(top: 22),
                              child: Text(
                                'Un article passe en « stock faible » '
                                'sous ce nombre. Chaque article peut '
                                'avoir le sien, saisi sur sa fiche.',
                                style: AppTextStyles.bodyMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SectionCard(
                    icon: Icons.image_outlined,
                    title: 'LOGO DE LA SOCIÉTÉ',
                    children: [
                      ResponsiveRow(
                        stackBelow: 620,
                        items: [
                          RowItem(
                            flex: 2,
            child:                             Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _LogoPreview(path: _logoPath),
                                const SizedBox(width: AppSpacing.lg),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ElevatedButton.icon(
                                        onPressed: _pickLogo,
                                        icon: const Icon(
                                          Icons.upload_file,
                                          size: 18,
                                        ),
                                        label: const Text('Choisir un fichier'),
                                      ),
                                      const SizedBox(height: AppSpacing.sm),
                                      OutlinedButton.icon(
                                        onPressed: _clearLogo,
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: AppColors.error,
                                        ),
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          size: 18,
                                        ),
                                        label: const Text('Supprimer'),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const RowItem(
                            flex: 2,
            child:                             Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '· Formats acceptés : PNG, JPG, BMP',
                                  style: AppTextStyles.bodyMuted,
                                ),
                                SizedBox(height: AppSpacing.xs),
                                Text(
                                  '· Taille recommandée : 200 × 80 px',
                                  style: AppTextStyles.bodyMuted,
                                ),
                                SizedBox(height: AppSpacing.xs),
                                Text(
                                  '· Fond transparent recommandé',
                                  style: AppTextStyles.bodyMuted,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _SaveBar(
                    statusMessage: _statusMessage,
                    statusIsError: _statusIsError,
                    saving: _saving,
                    onReset: _reset,
                    onSave: _save,
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Footer holding the save/reset actions and the last status message.
class _SaveBar extends StatelessWidget {
  final String? statusMessage;
  final bool statusIsError;
  final bool saving;
  final VoidCallback onReset;
  final VoidCallback onSave;

  const _SaveBar({
    required this.statusMessage,
    required this.statusIsError,
    required this.saving,
    required this.onReset,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final status = Text(
      statusMessage ?? '',
      style: TextStyle(
        fontSize: 12,
        color: statusIsError ? AppColors.error : AppColors.success,
      ),
    );
    final saveButton = FilledButton.icon(
      onPressed: saving ? null : onSave,
      icon: saving
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.save_outlined, size: 18),
      label: const Text('Enregistrer les paramètres'),
    );
    final resetButton = OutlinedButton(
      onPressed: onReset,
      child: const Text('Réinitialiser'),
    );

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.md,
      ),
      decoration: appSurfaceDecoration(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 520) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (statusMessage != null && statusMessage!.isNotEmpty) ...[
                  status,
                  const SizedBox(height: AppSpacing.md),
                ],
                saveButton,
                const SizedBox(height: AppSpacing.sm),
                resetButton,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: status),
              resetButton,
              const SizedBox(width: AppSpacing.md),
              saveButton,
            ],
          );
        },
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hintText;
  final bool required;

  const _LabeledField({
    required this.label,
    required this.controller,
    this.hintText,
    this.required = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // Uppercase labels are wide; in a three-across form row they
            // can exceed the column, so let them ellipsize.
            Flexible(
              child: Text(
                label.toUpperCase(),
                style: AppTextStyles.kpiLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (required)
              const Text(' *', style: TextStyle(color: AppColors.error, fontSize: 11, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 5),
        TextField(
          controller: controller,
          decoration: InputDecoration(hintText: hintText, isDense: true),
        ),
      ],
    );
  }
}

class _LogoPreview extends StatelessWidget {
  final String path;

  const _LogoPreview({required this.path});

  @override
  Widget build(BuildContext context) {
    final file = path.isEmpty ? null : File(path);
    final exists = file != null && file.existsSync();
    return Container(
      width: 140,
      height: 88,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: exists ? AppColors.accent.withValues(alpha: 0.4) : AppColors.border,
          style: exists ? BorderStyle.solid : BorderStyle.solid,
        ),
      ),
      child: exists
          ? ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(file, fit: BoxFit.contain),
            )
          : const Text('Aucun logo', style: AppTextStyles.bodyMuted),
    );
  }
}
