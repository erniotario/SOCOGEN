class AppUser {
  final int id;
  final String username;
  final String passwordHash;
  final String passwordSalt;
  final String role;

  const AppUser({
    required this.id,
    required this.username,
    required this.passwordHash,
    required this.passwordSalt,
    required this.role,
  });

  bool get isAdmin => role == 'admin';

  factory AppUser.fromMap(Map<String, Object?> map) {
    return AppUser(
      id: map['id'] as int,
      username: map['username'] as String,
      passwordHash: map['password_hash'] as String,
      passwordSalt: map['password_salt'] as String,
      role: map['role'] as String,
    );
  }

  Map<String, Object?> toMap({bool includeId = true}) {
    return {
      if (includeId) 'id': id,
      'username': username,
      'password_hash': passwordHash,
      'password_salt': passwordSalt,
      'role': role,
    };
  }
}
