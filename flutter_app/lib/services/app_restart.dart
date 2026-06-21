import 'dart:io';

/// Relaunches the current executable as a detached process and exits
/// this one. Used after replacing or resetting the local database file,
/// since [DatabaseService] only reads it once at startup.
Future<void> restartApp() async {
  await Process.start(
    Platform.resolvedExecutable,
    Platform.executableArguments,
    mode: ProcessStartMode.detached,
  );
  exit(0);
}
