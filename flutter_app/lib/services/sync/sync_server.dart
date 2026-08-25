import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:sqflite/sqflite.dart';

import '../data_refresh_bus.dart';
import '../web/web_report_pages.dart';
import '../../data/db/sync_columns.dart';
import 'sync_engine.dart';
import 'sync_models.dart';

/// Fixed port the local sync server listens on. Both devices must agree on
/// this value; only the IP address differs.
const int syncPort = 8765;

/// Local HTTP server started/stopped manually from the Sécurité screen.
///
/// It serves two things on the same port: `POST /sync`, which merges the
/// caller's [ChangeSet] into [database] and replies with this device's own
/// changes, and a pair of read-only HTML pages (`/` and `/mouvements`) so
/// the admin can share a link with colleagues on the same Wi-Fi.
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

  static const Map<String, String> _htmlHeaders = {
    'content-type': 'text/html; charset=utf-8',
    // The pages read live data, so never let a browser reuse them.
    'cache-control': 'no-store',
  };

  Future<Response> _handle(Request request) async {
    // Read-only pages for colleagues on the same network. Kept to GET so
    // a shared link can never change anything.
    if (request.method == 'GET') {
      try {
        switch (request.url.path) {
          case '':
          case '/':
            return Response.ok(
              await WebReportPages.stockPage(),
              headers: _htmlHeaders,
            );
          case 'mouvements':
            return Response.ok(
              await WebReportPages.movementsPage(),
              headers: _htmlHeaders,
            );
          case 'favicon.ico':
            return Response.notFound('');
          default:
            return Response.notFound(
              WebReportPages.notFoundPage(),
              headers: _htmlHeaders,
            );
        }
      } catch (e) {
        return Response.internalServerError(
          body: 'Erreur lors de la génération de la page : $e',
        );
      }
    }

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
