import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Replicates the Python app's password hashing exactly:
/// `hashlib.sha256((salt + password).encode()).hexdigest()`
/// with `salt = secrets.token_hex(16)` (32 hex chars).
class PasswordHasher {
  PasswordHasher._();

  static String generateSalt({int byteLength = 16}) {
    final random = Random.secure();
    final bytes = List<int>.generate(byteLength, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String hash(String password, String salt) {
    return sha256.convert(utf8.encode(salt + password)).toString();
  }

  static bool verify(String password, String salt, String expectedHash) {
    return hash(password, salt) == expectedHash;
  }
}
