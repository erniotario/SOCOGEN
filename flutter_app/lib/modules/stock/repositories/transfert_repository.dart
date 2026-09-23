import 'package:sqflite/sqflite.dart';

import 'package:erp/core/db/database_service.dart';
import 'package:erp/core/db/sync_columns.dart';
import 'package:erp/shared/models/transfert.dart';

/// Les déplacements de marchandises entre magasins.
class TransfertRepository {
  TransfertRepository({Database? database}) : _injectedDb = database;

  final Database? _injectedDb;

  Future<Database> get _db async =>
      _injectedDb ?? DatabaseService.instance.database;

  /// Comment un transfert se nomme sur la sortie qu'il produit.
  ///
  /// Le texte reste lisible sans suivre le lien : quelqu'un qui relit
  /// Transactions dans six mois voit où la marchandise est allée, même
  /// si l'écran qui affiche les transferts n'est pas ouvert. Même
  /// intention que « Inventaire physique » pour l'inventaire.
  static String versMagasin(String nom) => 'Transfert vers $nom';

  static String depuisMagasin(String nom) => 'Transfert depuis $nom';

  /// Écrit le transfert et ses deux mouvements par ligne, **en une seule
  /// transaction**.
  ///
  /// C'est l'invariant de cette opération : un transfert à moitié écrit
  /// est de la marchandise disparue — sortie d'un magasin sans être
  /// entrée dans l'autre. Les dépôts de mouvements n'exposant pas la
  /// transaction en cours, l'écriture se fait ici plutôt que par eux.
  Future<int> creer({
    required String date,
    required int sourceId,
    required String nomSource,
    required int destinationId,
    required String nomDestination,
    required List<LigneTransfert> lignes,
    String? notes,
  }) async {
    final db = await _db;
    return db.transaction((txn) async {
      final transfertId = await txn.insert('transferts', {
        'date': date,
        'source_id': sourceId,
        'destination_id': destinationId,
        'notes': notes,
        'sync_id': newSyncId(),
        'updated_at': nowIso(),
        ...attribution(),
      });

      for (final ligne in lignes) {
        await txn.insert('stock_outputs', {
          'date': date,
          'reference': ligne.reference,
          'designation': ligne.designation,
          'invoice_number': '',
          'store_id': sourceId,
          'destination': versMagasin(nomDestination),
          'quantity': ligne.quantite,
          'transfert_id': transfertId,
          'sync_id': newSyncId(),
          'updated_at': nowIso(),
          ...attribution(),
        });
        await txn.insert('stock_entries', {
          'date': date,
          'supplier': depuisMagasin(nomSource),
          'reference': ligne.reference,
          'designation': ligne.designation,
          'store_id': destinationId,
          'quantity': ligne.quantite,
          'transfert_id': transfertId,
          'sync_id': newSyncId(),
          'updated_at': nowIso(),
          ...attribution(),
        });
      }

      return transfertId;
    });
  }

  /// Les transferts, du plus récent au plus ancien, avec les noms des
  /// magasins et le nombre d'articles déplacés.
  ///
  /// Le nombre se compte sur les sorties : chaque ligne en produit
  /// exactement une, et les compter sur les deux tables doublerait le
  /// résultat.
  Future<List<({Transfert transfert, String source, String destination, int lignes})>>
      getAll({int? limite}) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT t.*,
             src.name AS source_nom,
             dst.name AS destination_nom,
             (SELECT COUNT(*) FROM stock_outputs o WHERE o.transfert_id = t.id)
               AS lignes
      FROM transferts t
      JOIN stores src ON src.id = t.source_id
      JOIN stores dst ON dst.id = t.destination_id
      ORDER BY t.date DESC, t.id DESC
      ${limite == null ? '' : 'LIMIT $limite'}
    ''');
    return rows
        .map((row) => (
              transfert: Transfert.fromMap(row),
              source: row['source_nom'] as String,
              destination: row['destination_nom'] as String,
              lignes: (row['lignes'] as num).toInt(),
            ))
        .toList();
  }

  /// Ce qu'un transfert a déplacé, lu sur ses sorties.
  ///
  /// Les mouvements sont la seule source : l'en-tête ne recopie ni la
  /// référence ni la quantité, donc rien ne peut diverger.
  Future<List<LigneTransfert>> lignesDe(int transfertId) async {
    final db = await _db;
    final rows = await db.query(
      'stock_outputs',
      where: 'transfert_id = ?',
      whereArgs: [transfertId],
      orderBy: 'reference',
    );
    return rows
        .map((row) => LigneTransfert(
              reference: row['reference'] as String,
              designation: row['designation'] as String,
              quantite: (row['quantity'] as num).toInt(),
            ))
        .toList();
  }

  Future<Transfert?> getById(int id) async {
    final db = await _db;
    final rows =
        await db.query('transferts', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Transfert.fromMap(rows.first);
  }
}
