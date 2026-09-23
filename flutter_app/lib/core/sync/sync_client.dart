import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import 'package:erp/core/events/data_refresh_bus.dart';
import 'package:erp/core/db/sync_columns.dart';
import 'package:erp/core/sync/sync_engine.dart';
import 'package:erp/core/sync/sync_models.dart';
import 'package:erp/core/sync/sync_server.dart' show syncPort;

/// Summary of a completed sync, shown to the user.
class SyncResult {
  final int sent;
  final int received;

  const SyncResult({required this.sent, required this.received});
}

/// Connects to a peer's [SyncServer] over the local network and exchanges
/// changes with it.
class SyncClient {
  SyncClient(this._database);

  final Database _database;

  /// Sends every local change since the last sync to `http://$host:$port`,
  /// applies the peer's reply, and returns a summary of what was exchanged.
  Future<SyncResult> syncWithPeer(String host, {int port = syncPort}) async {
    final since = await SyncEngine.getLastSyncAt(_database);
    final outgoing = await SyncEngine.collectChanges(_database, since);
    final localTenant = await SyncEngine.getTenantId(_database);

    final uri = Uri.parse('http://$host:$port/sync');
    final response = await http
        .post(
          uri,
          headers: {'content-type': 'application/json'},
          body: jsonEncode(outgoing.withTenant(localTenant).toJson()),
        )
        .timeout(const Duration(seconds: 20));

    // The peer refuses an exchange between two businesses before it merges
    // anything, and says so with 409 rather than a generic failure.
    if (response.statusCode == 409) {
      throw const TenantMismatch();
    }
    if (response.statusCode != 200) {
      throw Exception('Le serveur a répondu avec le code ${response.statusCode}');
    }

    final incoming = ChangeSet.fromJson(jsonDecode(response.body) as Map<String, Object?>);

    // Checked on this side too. The peer could be an older build with no
    // tenant check at all, in which case this is the only thing standing
    // between a stranger's catalogue and the local one.
    await SyncEngine.reconcileTenant(_database, incoming.tenantId);

    final received = await SyncEngine.applyChanges(_database, incoming);
    await SyncEngine.setLastSyncAt(_database, nowIso());

    if (received > 0) {
      DataRefreshBus.instance.notifyChanged();
    }

    return SyncResult(sent: outgoing.recordCount, received: received);
  }
}
