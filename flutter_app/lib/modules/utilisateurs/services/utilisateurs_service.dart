import 'package:socogen/core/auth/permissions.dart';
import 'package:socogen/modules/utilisateurs/repositories/role_repository.dart';
import 'package:socogen/shared/models/role.dart';

/// Ce que les utilisateurs et leurs rôles exposent aux autres modules.
///
/// Le shell y demande le [PermissionGate] de la personne connectée. Le
/// noyau, lui, ne sait pas d'où viennent les droits : il reçoit un
/// ensemble de codes et répond oui ou non.
class UtilisateursService {
  UtilisateursService({RoleRepository? roleRepository})
      : _roles = roleRepository ?? RoleRepository();

  final RoleRepository _roles;

  /// Construit le point de décision pour un rôle donné.
  ///
  /// L'administrateur ne fait pas de requête : il répond oui à tout par
  /// construction, et aller lire une table pour le confirmer ne ferait
  /// qu'ouvrir la possibilité qu'elle dise non.
  Future<PermissionGate> droitsDe(String? roleCode) async {
    if (roleCode == null) return PermissionGate.aucun;
    if (roleCode == PermissionGate.roleAdmin) {
      return const PermissionGate(PermissionGate.roleAdmin);
    }
    return PermissionGate(roleCode, accordees: await _roles.droitsDe(roleCode));
  }

  Future<List<Role>> listerRoles() => _roles.getAll();

  Future<Role?> role(String code) => _roles.getByCode(code);

  Future<Set<String>> permissionsDe(String roleCode) =>
      _roles.droitsDe(roleCode);

  Future<void> definirPermissions(String roleCode, Set<String> codes) =>
      _roles.definirDroits(roleCode, codes);

  Future<void> creerRole({required String code, required String libelle}) =>
      _roles.creer(Role(code: code.trim(), libelle: libelle.trim()));

  Future<void> renommerRole(String code, String libelle) =>
      _roles.renommer(code, libelle);

  Future<void> supprimerRole(String code) => _roles.supprimer(code);

  Future<int> comptesAvecRole(String code) => _roles.compterComptes(code);
}
