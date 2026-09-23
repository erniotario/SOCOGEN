import 'package:flutter/material.dart';

import 'package:erp/core/auth/permissions.dart';
import 'package:erp/core/errors/messages.dart';
import 'package:erp/modules/utilisateurs/services/utilisateurs_service.dart';
import 'package:erp/shared/models/role.dart';
import 'package:erp/shared/ui/theme/app_colors.dart';
import 'package:erp/shared/ui/theme/app_text_styles.dart';
import 'package:erp/shared/ui/widgets/section_card.dart';

/// Les rôles et ce que chacun a le droit de faire.
///
/// L'administrateur y figure mais ne s'y règle pas : il répond oui à
/// tout par construction. Si ses droits étaient modifiables, un
/// administrateur pourrait se retirer celui de régler les droits — et
/// plus personne ne rattraperait rien, ni lui ni les autres.
class RolesSection extends StatelessWidget {
  final Future<List<Role>> rolesFuture;
  final UtilisateursService service;
  final VoidCallback onChanged;

  const RolesSection({
    super.key,
    required this.rolesFuture,
    required this.service,
    required this.onChanged,
  });

  Future<void> _creer(BuildContext context) async {
    final cree = await showDialog<bool>(
      context: context,
      builder: (_) => _DialogueRole(service: service),
    );
    if (cree == true) onChanged();
  }

  Future<void> _droits(BuildContext context, Role role) async {
    final accordees = await service.permissionsDe(role.code);
    if (!context.mounted) return;
    final change = await showDialog<bool>(
      context: context,
      builder: (_) => _DialogueDroits(
        role: role,
        accordees: accordees,
        service: service,
      ),
    );
    if (change == true) onChanged();
  }

  Future<void> _supprimer(BuildContext context, Role role) async {
    final comptes = await service.comptesAvecRole(role.code);
    if (!context.mounted) return;
    final confirme = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer le rôle'),
        content: Text(
          comptes == 0
              ? 'Le rôle « ${role.libelle} » sera supprimé, avec les droits '
                  'qui lui sont accordés.'
              // Ces comptes se retrouveraient sans aucun droit du jour
              // au lendemain, sans que personne l'ait demandé.
              : '$comptes compte${comptes > 1 ? 's' : ''} '
                  'utilise${comptes > 1 ? 'nt' : ''} encore ce rôle. '
                  'Changez-leur de rôle avant de le supprimer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          if (comptes == 0)
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Supprimer'),
            ),
        ],
      ),
    );
    if (confirme != true) return;
    try {
      await service.supprimerRole(role.code);
      onChanged();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(messagePour(e, operation: 'la suppression du rôle')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      icon: Icons.badge_outlined,
      title: 'RÔLES ET DROITS',
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            onPressed: () => _creer(context),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Nouveau rôle'),
          ),
        ),
        const SizedBox(height: 12),
        FutureBuilder<List<Role>>(
          future: rolesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final roles = snapshot.data ?? const <Role>[];
            return Column(
              children: [
                for (final role in roles)
                  _LigneRole(
                    role: role,
                    onDroits: () => _droits(context, role),
                    onSupprimer: () => _supprimer(context, role),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _LigneRole extends StatelessWidget {
  final Role role;
  final VoidCallback onDroits;
  final VoidCallback onSupprimer;

  const _LigneRole({
    required this.role,
    required this.onDroits,
    required this.onSupprimer,
  });

  bool get _estAdmin => role.code == PermissionGate.roleAdmin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            _estAdmin ? Icons.shield_outlined : Icons.badge_outlined,
            size: 18,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(role.libelle, style: AppTextStyles.body),
                Text(
                  _estAdmin ? 'Tous les droits, par construction' : role.code,
                  style: AppTextStyles.captionMuted,
                ),
              ],
            ),
          ),
          if (!_estAdmin)
            TextButton.icon(
              onPressed: onDroits,
              icon: const Icon(Icons.tune, size: 16),
              label: const Text('Droits'),
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            color: role.integre ? AppColors.textMuted : AppColors.error,
            tooltip: role.integre
                ? "Ce rôle fait partie de l'application"
                : 'Supprimer',
            onPressed: role.integre ? null : onSupprimer,
          ),
        ],
      ),
    );
  }
}

/// Créer un rôle.
class _DialogueRole extends StatefulWidget {
  final UtilisateursService service;

  const _DialogueRole({required this.service});

  @override
  State<_DialogueRole> createState() => _DialogueRoleState();
}

class _DialogueRoleState extends State<_DialogueRole> {
  final _code = TextEditingController();
  final _libelle = TextEditingController();
  String? _erreur;
  bool _enCours = false;

  @override
  void dispose() {
    _code.dispose();
    _libelle.dispose();
    super.dispose();
  }

  Future<void> _creer() async {
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      await widget.service.creerRole(
        code: _code.text.trim().toLowerCase(),
        libelle: _libelle.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _erreur = messagePour(e, operation: 'la création du rôle');
        _enCours = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nouveau rôle'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _libelle,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nom du rôle *',
                hintText: 'Ex : Caissier, Responsable de magasin',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _code,
              decoration: const InputDecoration(
                labelText: 'Code *',
                hintText: 'Ex : caissier',
                // Le code est ce que portent les comptes : le changer
                // reviendrait à les réécrire tous.
                helperText: 'Identifiant stable, non modifiable ensuite',
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              "Un rôle neuf n'a aucun droit. Accordez-les ensuite : "
              'ouvrir se rattrape, refermer après coup se rattrape mal.',
              style: AppTextStyles.bodyMuted,
            ),
            if (_erreur != null) ...[
              const SizedBox(height: 12),
              Text(_erreur!,
                  style: const TextStyle(color: AppColors.error, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _enCours ? null : () => Navigator.pop(context, false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _enCours ? null : _creer,
          child: _enCours
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Créer'),
        ),
      ],
    );
  }
}

/// Cocher les droits d'un rôle.
class _DialogueDroits extends StatefulWidget {
  final Role role;
  final Set<String> accordees;
  final UtilisateursService service;

  const _DialogueDroits({
    required this.role,
    required this.accordees,
    required this.service,
  });

  @override
  State<_DialogueDroits> createState() => _DialogueDroitsState();
}

class _DialogueDroitsState extends State<_DialogueDroits> {
  late final Set<String> _coches = {...widget.accordees};
  String? _erreur;
  bool _enCours = false;

  Future<void> _enregistrer() async {
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      await widget.service.definirPermissions(widget.role.code, _coches);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _erreur = messagePour(e, operation: 'la modification des droits');
        _enCours = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Droits de « ${widget.role.libelle} »'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final permission in Permissions.toutes)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _coches.contains(permission.code),
                  title: Text(permission.libelle, style: AppTextStyles.body),
                  subtitle:
                      Text(permission.code, style: AppTextStyles.captionMuted),
                  onChanged: (coche) => setState(() {
                    if (coche == true) {
                      _coches.add(permission.code);
                    } else {
                      _coches.remove(permission.code);
                    }
                  }),
                ),
              const SizedBox(height: 8),
              const Text(
                'Sans serveur, un droit cache un écran : il ne protège pas '
                'le fichier de données.',
                style: AppTextStyles.bodyMuted,
              ),
              if (_erreur != null) ...[
                const SizedBox(height: 12),
                Text(_erreur!,
                    style:
                        const TextStyle(color: AppColors.error, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _enCours ? null : () => Navigator.pop(context, false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _enCours ? null : _enregistrer,
          child: _enCours
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Enregistrer'),
        ),
      ],
    );
  }
}
