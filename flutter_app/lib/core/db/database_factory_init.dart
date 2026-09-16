import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Configures the global [databaseFactory] for desktop platforms
/// (Windows/Linux/macOS), which need the FFI-based sqlite3 backend.
/// Android/iOS/web use the default sqflite factory untouched.
void initializeDatabaseFactory() {
  if (kIsWeb) return;
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}
