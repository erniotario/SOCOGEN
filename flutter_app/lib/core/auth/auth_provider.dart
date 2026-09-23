import 'package:flutter/foundation.dart';

import 'package:erp/core/auth/session_courante.dart';
import 'package:erp/modules/utilisateurs/models/user.dart';
import 'package:erp/modules/utilisateurs/repositories/user_repository.dart';
import 'package:erp/core/auth/password_hasher.dart';

enum AuthStatus { unknown, setupRequired, loggedOut, loggedIn }

class AuthProvider extends ChangeNotifier {
  AuthProvider({UserRepository? userRepository})
      : _userRepository = userRepository ?? UserRepository();

  final UserRepository _userRepository;

  AuthStatus _status = AuthStatus.unknown;
  AppUser? _currentUser;
  String? _error;

  AuthStatus get status => _status;
  AppUser? get currentUser => _currentUser;
  String? get error => _error;

  /// Decides whether to show the setup form (no users yet) or the login
  /// form. The bundled seed asset ships with no accounts, so a fresh
  /// install lands on setup and the first person to open the app creates
  /// the administrator.
  Future<void> checkSetup() async {
    final hasUsers = await _userRepository.hasUsers();
    _status = hasUsers ? AuthStatus.loggedOut : AuthStatus.setupRequired;
    notifyListeners();
  }

  Future<bool> login(String username, String password) async {
    _error = null;
    final user = await _userRepository.authenticate(username, password);
    if (user == null) {
      _error = 'Identifiants invalides';
      notifyListeners();
      return false;
    }
    _ouvrirSession(user);
    notifyListeners();
    return true;
  }

  Future<bool> createAdminAccount(String username, String password) async {
    _error = null;
    if (username.trim().isEmpty || password.isEmpty) {
      _error = 'Veuillez remplir tous les champs';
      notifyListeners();
      return false;
    }
    final existing = await _userRepository.findByUsername(username.trim());
    if (existing != null) {
      _error = 'Ce nom d\'utilisateur existe déjà';
      notifyListeners();
      return false;
    }
    final user = await _userRepository.createUser(
      username: username.trim(),
      password: password,
      role: 'admin',
    );
    _ouvrirSession(user);
    notifyListeners();
    return true;
  }

  /// Retient la personne connectée en deux endroits : ici pour l'écran,
  /// et dans [SessionCourante] pour les écritures.
  ///
  /// Les dépôts y lisent l'auteur au moment d'écrire, plutôt que de le
  /// recevoir en argument — sans quoi un formulaire pourrait signer au
  /// nom d'un autre.
  void _ouvrirSession(AppUser user) {
    _currentUser = user;
    _status = AuthStatus.loggedIn;
    SessionCourante.instance.ouvrir(
      utilisateurId: user.id,
      nom: user.username,
    );
  }

  void logout() {
    _currentUser = null;
    _status = AuthStatus.loggedOut;
    // Une écriture qui suivrait n'aura pas d'auteur, ce qui est exact.
    SessionCourante.instance.fermer();
    notifyListeners();
  }

  /// Lets the signed-in user change their own password, after verifying
  /// [oldPassword] against their stored hash.
  Future<bool> changePassword(String oldPassword, String newPassword) async {
    _error = null;
    final user = _currentUser;
    if (user == null) return false;
    if (!PasswordHasher.verify(oldPassword, user.passwordSalt, user.passwordHash)) {
      _error = 'Mot de passe actuel incorrect';
      notifyListeners();
      return false;
    }
    if (newPassword.isEmpty) {
      _error = 'Le nouveau mot de passe est requis';
      notifyListeners();
      return false;
    }
    _currentUser = await _userRepository.updatePassword(user.id, newPassword);
    notifyListeners();
    return true;
  }
}
