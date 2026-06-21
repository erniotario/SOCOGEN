import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:sqflite/sqflite.dart';

import '../data_refresh_bus.dart';
import '../../data/db/sync_columns.dart';
import 'sync_engine.dart';
import 'sync_models.dart';

/// Fixed port the local sync server listens on. Both devices must agree on
/// this value; only the IP address differs.
const int syncPort = 8765;

/// Local HTTP server exposing a single `POST /sync` endpoint that merges
/// the caller's [ChangeSet] into [database] and replies with this device's
/// own changes. Started/stopped manually from the Sécurité screen.
class SyncServer {
  SyncServer(this._database);

  final Database _database;
  HttpServer? _httpServer;

  bool get isRunning => _httpServer != null;

  Future<void> start() async {
    if (_httpServer != null) return;
    final handler = const Pipeline().addHandler(_handle);
    _httpServer = await shelf_io.serve(handler, InternetAddress.anyIPv4, syncPort);
  }

  Future<void> stop() async {
    final server = _httpServer;
    _httpServer = null;
    await server?.close(force: true);
  }

  Future<Response> _handle(Request request) async {
    if (request.method != 'POST' || request.url.path != 'sync') {
      return Response.notFound('Not found');
    }
    try {
      final incoming = ChangeSet.fromJson(
        jsonDecode(await request.readAsString()) as Map<String, Object?>,
      );
      await SyncEngine.applyChanges(_database, incoming);

      final outgoing = await SyncEngine.collectChanges(_database, syncEpoch);
      await SyncEngine.setLastSyncAt(_database, nowIso());

      if (!incoming.isEmpty) {
        DataRefreshBus.instance.notifyChanged();
      }

      return Response.ok(
        jsonEncode(outgoing.toJson()),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(body: 'Erreur de synchronisation : $e');
    }
  }

  /// Local IPv4 addresses this device can be reached at on the current
  /// network, for display in the UI (loopback/link-local excluded).
  static Future<List<String>> localAddresses() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );
    return interfaces.expand((i) => i.addresses).map((a) => a.address).toList();
  }
}
