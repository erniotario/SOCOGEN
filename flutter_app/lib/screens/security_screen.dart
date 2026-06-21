import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_provider.dart';
import '../data/db/database_service.dart';
import '../data/models/user.dart';
import '../data/repositories/user_repository.dart';
import '../services/app_restart.dart';
import '../services/sync/sync_client.dart';
import '../services/sync/sync_server.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/page_header.dart';
import '../widgets/section_card.dart';

/// Admin-only screen for creating accounts, changing roles, resetting
/// passwords and deleting users.
class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  final _userRepo = UserRepository();
  late Future<List<AppUser>> _usersFuture;

  bool _dbBusy = false;
  String? _dbError;

  SyncServer? _syncServer;
  bool _syncServerBusy = false;
  List<String> _syncServerAddresses = [];
  String? _syncServerError;

  final _peerIpController = TextEditingController();
  bool _syncBusy = false;
  String? _syncResultText;
  String? _syncError;

  bool get _syncServerRunning => _syncServer?.isRunning ?? false;

  @override
  void initState() {
    super.initState();
    _usersFuture = _userRepo.getAllUsers();
  }

  @override
  void dispose() {
    _peerIpController.dispose();
    _syncServer?.stop();
    super.dispose();
  }

  void _refreshUsers() {
    setState(() {
      _usersFuture = _userRepo.getAllUsers();
    });
  }

  Future<void> _openAddUserDialog() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => const _UserFormDialog(),
    );
    if (created == true) _refreshUsers();
  }

  Future<void> _changeUserRole(AppUser user, String role) async {
    if (role == user.role) return;
    if (user.role == 'admin' && role != 'admin') {
      final admins = await _userRepo.countAdmins();
      if (admins <= 1) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible de rétrograder le dernier administrateur.')),
        );
        return;
      }
    }
    await _userRepo.updateRole(user.id, role);
    _refreshUsers();
  }

  Future<void> _resetUserPassword(AppUser user) async {
    await showDialog<bool>(
      context: context,
      builder: (context) => _ResetPasswordDialog(user: user),
    );
  }

  Future<void> _deleteUser(AppUser user) async {
    if (user.role == 'admin') {
      final admins = await _userRepo.countAdmins();
      if (admins <= 1) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible de supprimer le dernier administrateur.')),
        );
        return;
      }
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Supprimer l'utilisateur"),
        content: Text('Voulez-vous vraiment supprimer le compte « ${user.username} » ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _userRepo.deleteUser(user.id);
    _refreshUsers();
  }

  Future<void> _importDatabase() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['db'],
    );
    final path = result?.files.single.path;
    if (path == null) return;

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Importer une base de données'),
        content: const Text(
          'Toutes les données actuelles (produits, magasins, mouvements, comptes) seront '
          "remplacées par celles du fichier sélectionné, puis l'application redémarrera. "
          'Voulez-vous continuer ?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Importer et redémarrer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _dbBusy = true;
      _dbError = null;
    });
    try {
      await DatabaseService.instance.replaceDatabaseFile(path);
      await restartApp();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _dbBusy = false;
        _dbError = 'Erreur : $e';
      });
    }
  }

  Future<void> _resetDatabase() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Vider la base de données'),
        content: const Text(
          'Toutes les données (produits, magasins, mouvements et comptes utilisateurs) seront '
          'définitivement supprimées. L\'application redémarrera sur l\'écran de création du '
          'compte administrateur. Cette action est irréversible. Voulez-vous continuer ?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Vider et redémarrer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _dbBusy = true;
      _dbError = null;
    });
    try {
      await DatabaseService.instance.resetDatabaseFile();
      await restartApp();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _dbBusy = false;
        _dbError = 'Erreur : $e';
      });
    }
  }

  Future<void> _toggleSyncServer() async {
    setState(() {
      _syncServerBusy = true;
      _syncServerError = null;
    });
    try {
      if (_syncServerRunning) {
        await _syncServer!.stop();
        if (!mounted) return;
        setState(() => _syncServerAddresses = []);
      } else {
        final db = await DatabaseService.instance.database;
        final server = _syncServer ?? SyncServer(db);
        await server.start();
        final addresses = await SyncServer.localAddresses();
        if (!mounted) return;
        setState(() {
          _syncServer = server;
          _syncServerAddresses = addresses;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _syncServerError = 'Erreur : $e');
    } finally {
      if (mounted) setState(() => _syncServerBusy = false);
    }
  }

  Future<void> _syncWithPeer() async {
    final host = _peerIpController.text.trim();
    if (host.isEmpty) {
      setState(() => _syncError = "Veuillez saisir l'adresse IP de l'autre appareil.");
      return;
    }
    setState(() {
      _syncBusy = true;
      _syncError = null;
      _syncResultText = null;
    });
    try {
      final db = await DatabaseService.instance.database;
      final result = await SyncClient(db).syncWithPeer(host);
      if (!mounted) return;
      setState(() {
        _syncResultText =
            '${result.sent} enregistrement(s) envoyé(s), ${result.received} reçu(s) et appliqué(s).';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _syncError = 'Erreur : $e');
    } finally {
      if (mounted) setState(() => _syncBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const PageHeader(
          title: 'Sécurité',
          subtitle: 'Gestion des comptes utilisateurs et des accès',
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              SectionCard(
                icon: Icons.admin_panel_settings_outlined,
                title: 'GESTION DES UTILISATEURS',
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      onPressed: _openAddUserDialog,
                      icon: const Icon(Icons.person_add_alt, size: 18),
                      label: const Text('Nouvel utilisateur'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FutureBuilder<List<AppUser>>(
                    future: _usersFuture,
                    builder: (context, usersSnapshot) {
                      if (usersSnapshot.connectionState != ConnectionState.done) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (usersSnapshot.hasError) {
                        return Text(
                          'Erreur de chargement : ${usersSnapshot.error}',
                          style: const TextStyle(color: AppColors.error),
                        );
                      }
                      final users = usersSnapshot.data!;
                      final selfId = context.watch<AuthProvider>().currentUser?.id;
                      return Column(
                        children: [
                          for (final user in users)
                            _UserRow(
                              user: user,
                              isSelf: user.id == selfId,
                              onRoleChanged: (role) => _changeUserRole(user, role),
                              onResetPassword: () => _resetUserPassword(user),
                              onDelete: () => _deleteUser(user),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SectionCard(
                icon: Icons.storage_outlined,
                title: 'BASE DE DONNÉES',
                children: [
                  const Text(
                    "Importez un fichier de base de données (.db) pour remplacer les données "
                    "actuelles, ou videz la base pour repartir avec des données vierges. "
                    "Dans les deux cas, l'application redémarre automatiquement.",
                    style: AppTextStyles.bodyMuted,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _dbBusy ? null : _importDatabase,
                        icon: const Icon(Icons.file_upload_outlined, size: 18),
                        label: const Text('Importer une base de données'),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: _dbBusy ? null : _resetDatabase,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: const BorderSide(color: AppColors.border),
                        ),
                        icon: const Icon(Icons.delete_forever_outlined, size: 18),
                        label: const Text('Vider la base de données'),
                      ),
                      if (_dbBusy) ...[
                        const SizedBox(width: 14),
                        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      ],
                    ],
                  ),
                  if (_dbError != null) ...[
                    const SizedBox(height: 12),
                    Text(_dbError!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              SectionCard(
                icon: Icons.sync,
                title: 'SYNCHRONISATION',
                children: [
                  const Text(
                    "Échangez les magasins, produits, stocks, entrées et sorties avec un autre "
                    "appareil connecté au même réseau Wi-Fi. Sur l'appareil qui doit fournir ses "
                    "données, démarrez le serveur et notez l'adresse affichée. Sur l'autre "
                    "appareil, saisissez cette adresse puis appuyez sur « Synchroniser ».",
                    style: AppTextStyles.bodyMuted,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _syncServerBusy ? null : _toggleSyncServer,
                        icon: Icon(_syncServerRunning ? Icons.stop_circle_outlined : Icons.podcasts, size: 18),
                        label: Text(_syncServerRunning ? 'Arrêter le serveur' : 'Démarrer le serveur'),
                      ),
                      if (_syncServerBusy) ...[
                        const SizedBox(width: 14),
                        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      ],
                    ],
                  ),
                  if (_syncServerRunning) ...[
                    const SizedBox(height: 10),
                    Text(
                      _syncServerAddresses.isEmpty
                          ? 'Serveur actif sur le port $syncPort (adresse IP locale introuvable).'
                          : "Serveur actif. Sur l'autre appareil, saisissez l'adresse : "
                              '${_syncServerAddresses.join(' ou ')}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                  if (_syncServerError != null) ...[
                    const SizedBox(height: 8),
                    Text(_syncServerError!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
                  ],
                  const Divider(height: 28),
                  const Text(
                    "Pour récupérer les données d'un autre appareil, saisissez son adresse IP "
                    "(affichée sur cet appareil quand son serveur est démarré) :",
                    style: AppTextStyles.bodyMuted,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      SizedBox(
                        width: 220,
                        child: TextField(
                          controller: _peerIpController,
                          decoration: const InputDecoration(
                            labelText: "Adresse IP de l'autre appareil",
                            hintText: '192.168.1.42',
                            isDense: true,
                          ),
                          keyboardType: TextInputType.url,
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: _syncBusy ? null : _syncWithPeer,
                        icon: const Icon(Icons.sync, size: 18),
                        label: const Text('Synchroniser'),
                      ),
                      if (_syncBusy) ...[
                        const SizedBox(width: 14),
                        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      ],
                    ],
                  ),
                  if (_syncResultText != null) ...[
                    const SizedBox(height: 12),
                    Text(_syncResultText!, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                  if (_syncError != null) ...[
                    const SizedBox(height: 12),
                    Text(_syncError!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _UserRow extends StatelessWidget {
  final AppUser user;
  final bool isSelf;
  final ValueChanged<String> onRoleChanged;
  final VoidCallback onResetPassword;
  final VoidCallback onDelete;

  const _UserRow({
    required this.user,
    required this.isSelf,
    required this.onRoleChanged,
    required this.onResetPassword,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_outline, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  user.username,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
                if (isSelf) const Text('Vous', style: AppTextStyles.bodyMuted),
              ],
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 180,
            child: DropdownButtonFormField<String>(
              initialValue: user.role,
              isExpanded: true,
              decoration: const InputDecoration(isDense: true),
              items: const [
                DropdownMenuItem(value: 'admin', child: Text('Administrateur')),
                DropdownMenuItem(value: 'magasinier', child: Text('Magasinier')),
              ],
              onChanged: isSelf
                  ? null
                  : (value) {
                      if (value != null) onRoleChanged(value);
                    },
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.lock_reset, size: 18),
            color: AppColors.textSecondary,
            tooltip: 'Réinitialiser le mot de passe',
            onPressed: onResetPassword,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            color: isSelf ? AppColors.textMuted : AppColors.error,
            tooltip: isSelf ? 'Vous ne pouvez pas supprimer votre propre compte' : 'Supprimer',
            onPressed: isSelf ? null : onDelete,
          ),
        ],
      ),
    );
  }
}

class _UserFormDialog extends StatefulWidget {
  const _UserFormDialog();

  @override
  State<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<_UserFormDialog> {
  final _userRepo = UserRepository();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  String _role = 'magasinier';
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmController.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = "Le nom d'utilisateur et le mot de passe sont obligatoires.");
      return;
    }
    if (password != confirm) {
      setState(() => _error = 'Les mots de passe ne correspondent pas.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final existing = await _userRepo.findByUsername(username);
      if (existing != null) {
        setState(() {
          _error = "Le nom d'utilisateur « $username » existe déjà.";
          _saving = false;
        });
        return;
      }
      await _userRepo.createUser(username: username, password: password, role: _role);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _error = 'Erreur : $e';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nouvel utilisateur'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(labelText: "Nom d'utilisateur *"),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Mot de passe *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirmer le mot de passe *'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _role,
              decoration: const InputDecoration(labelText: 'Rôle'),
              items: const [
                DropdownMenuItem(value: 'magasinier', child: Text('Magasinier')),
                DropdownMenuItem(value: 'admin', child: Text('Administrateur')),
              ],
              onChanged: (value) => setState(() => _role = value ?? 'magasinier'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Annuler')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Ajouter'),
        ),
      ],
    );
  }
}

class _ResetPasswordDialog extends StatefulWidget {
  final AppUser user;

  const _ResetPasswordDialog({required this.user});

  @override
  State<_ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<_ResetPasswordDialog> {
  final _userRepo = UserRepository();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _passwordController.text;
    final confirm = _confirmController.text;
    if (password.isEmpty) {
      setState(() => _error = 'Le nouveau mot de passe est requis.');
      return;
    }
    if (password != confirm) {
      setState(() => _error = 'Les mots de passe ne correspondent pas.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    await _userRepo.updatePassword(widget.user.id, password);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Réinitialiser le mot de passe de « ${widget.user.username} »'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Nouveau mot de passe *'),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirmer le mot de passe *'),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Annuler')),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Réinitialiser'),
        ),
      ],
    );
  }
}
