import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/models/company_settings.dart';
import '../data/repositories/settings_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/page_header.dart';
import '../widgets/section_card.dart';

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

  void _applySettings(CompanySettings s) {
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
      await _settingsRepo.saveSettings(CompanySettings(
        name: _nameController.text.trim().isEmpty ? 'SOCOGEN' : _nameController.text.trim(),
        address: _addressController.text.trim(),
        city: _cityController.text.trim(),
        phone: _phoneController.text.trim(),
        email: _emailController.text.trim(),
        website: _websiteController.text.trim(),
        taxId: _taxIdController.text.trim(),
        rccm: _rccmController.text.trim(),
        logoPath: _logoPath,
      ));
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
        _statusMessage = 'Erreur : $e';
        _statusIsError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
                return Center(
                  child: Text(
                    'Erreur de chargement : ${snapshot.error}',
                    style: const TextStyle(color: AppColors.error),
                  ),
                );
              }
              return ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  SectionCard(
                    icon: Icons.apartment_outlined,
                    title: 'IDENTITÉ DE LA SOCIÉTÉ',
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: _LabeledField(
                              label: 'Nom de la société',
                              required: true,
                              controller: _nameController,
                              hintText: 'Ex : SOCOGEN SARL',
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            flex: 2,
                            child: _LabeledField(
                              label: 'N° Contribuable',
                              controller: _taxIdController,
                              hintText: 'Ex : M123456789',
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            flex: 2,
                            child: _LabeledField(
                              label: 'RCCM',
                              controller: _rccmController,
                              hintText: 'Ex : RC/YAO/2020/B/1234',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: _LabeledField(
                              label: 'Adresse',
                              controller: _addressController,
                              hintText: 'Ex : BP 1234, Rue des Palmiers',
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            flex: 2,
                            child: _LabeledField(
                              label: 'Ville / Pays',
                              controller: _cityController,
                              hintText: 'Ex : Yaoundé, Cameroun',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SectionCard(
                    icon: Icons.contact_phone_outlined,
                    title: 'COORDONNÉES',
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _LabeledField(
                              label: 'Téléphone',
                              controller: _phoneController,
                              hintText: 'Ex : +237 6XX XXX XXX',
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: _LabeledField(
                              label: 'Email',
                              controller: _emailController,
                              hintText: 'Ex : contact@socogen.cm',
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: _LabeledField(
                              label: 'Site web',
                              controller: _websiteController,
                              hintText: 'Ex : www.socogen.cm',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SectionCard(
                    icon: Icons.image_outlined,
                    title: 'LOGO DE LA SOCIÉTÉ',
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _LogoPreview(path: _logoPath),
                          const SizedBox(width: 20),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 180,
                                child: ElevatedButton.icon(
                                  onPressed: _pickLogo,
                                  icon: const Icon(Icons.upload_file, size: 18),
                                  label: const Text('Choisir un fichier'),
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: 180,
                                child: OutlinedButton.icon(
                                  onPressed: _clearLogo,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.error,
                                    side: const BorderSide(color: AppColors.border),
                                  ),
                                  icon: const Icon(Icons.delete_outline, size: 18),
                                  label: const Text('Supprimer'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 20),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('· Formats acceptés : PNG, JPG, BMP', style: AppTextStyles.bodyMuted),
                                SizedBox(height: 4),
                                Text('· Taille recommandée : 200 × 80 px', style: AppTextStyles.bodyMuted),
                                SizedBox(height: 4),
                                Text('· Fond transparent recommandé', style: AppTextStyles.bodyMuted),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.elevated,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _statusMessage ?? '',
                            style: TextStyle(
                              fontSize: 12,
                              color: _statusIsError ? AppColors.error : AppColors.success,
                            ),
                          ),
                        ),
                        OutlinedButton(
                          onPressed: _reset,
                          child: const Text('Réinitialiser'),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: _saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.save_outlined, size: 18),
                          label: const Text('Enregistrer les paramètres'),
                        ),
                      ],
                    ),
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
            Text(label.toUpperCase(), style: AppTextStyles.kpiLabel),
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
