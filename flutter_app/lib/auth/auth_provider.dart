import 'package:flutter/foundation.dart';

import '../data/models/user.dart';
import '../data/repositories/user_repository.dart';
import 'password_hasher.dart';

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
  /// form. The seeded database always has the admin user, so this only
  /// triggers setup mode if the seed asset was missing on first launch.
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
    _currentUser = user;
    _status = AuthStatus.loggedIn;
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
    _currentUser = user;
    _status = AuthStatus.loggedIn;
    notifyListeners();
    return true;
  }

  void logout() {
    _currentUser = null;
    _status = AuthStatus.loggedOut;
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
