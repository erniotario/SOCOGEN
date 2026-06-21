import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../data_refresh_bus.dart';
import '../../data/db/sync_columns.dart';
import 'sync_engine.dart';
import 'sync_models.dart';
import 'sync_server.dart' show syncPort;

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

    final uri = Uri.parse('http://$host:$port/sync');
    final response = await http
        .post(
          uri,
          headers: {'content-type': 'application/json'},
          body: jsonEncode(outgoing.toJson()),
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception('Le serveur a répondu avec le code ${response.statusCode}');
    }

    final incoming = ChangeSet.fromJson(jsonDecode(response.body) as Map<String, Object?>);
    final received = await SyncEngine.applyChanges(_database, incoming);
    await SyncEngine.setLastSyncAt(_database, nowIso());

    if (received > 0) {
      DataRefreshBus.instance.notifyChanged();
    }

    return SyncResult(sent: outgoing.recordCount, received: received);
  }
}
