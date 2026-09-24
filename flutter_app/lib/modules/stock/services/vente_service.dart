import 'package:sqflite/sqflite.dart';

import 'package:erp/core/db/database_service.dart';
import 'package:erp/core/db/sync_columns.dart';
import 'package:erp/core/errors/messages.dart';
import 'package:erp/core/money/montant.dart';
import 'package:erp/modules/parametres/services/parametres_service.dart';
import 'package:erp/modules/stock/repositories/valorisation_repository.dart';
import 'package:erp/modules/stock/services/stock_service.dart';
import 'package:erp/shared/models/vente.dart';

/// Encaisser au comptoir.
///
/// « La vente est la sortie dans le magasin de la boutique » : ce
/// service n'écrit donc que des sorties. Ce qui en fait une vente plutôt
/// qu'un mouvement quelconque tient à trois choses posées sur chaque
/// ligne — le magasin du point de vente, le prix pratiqué, et un numéro
/// de ticket que les lignes d'un même passage en caisse partagent.
///
/// Le numéro de ticket occupe la colonne `invoice_number`, qui existait
/// déjà et que l'historique affiche déjà. Une table des ventes n'aurait
/// rien ajouté que les mouvements ne disent, et aurait divergé d'eux à
/// la première correction.
class VenteService {
  VenteService({
    Database? database,
    StockService? stockService,
    ParametresService? parametresService,
  })  : _injectedDb = database,
        _stock = stockService ?? StockService(),
        // Le même fichier que le reste du service : passer la base
        // injectée évite qu'un test écrive ici et compte là.
        _valorisation = ValorisationRepository(database: database),
        _parametres = parametresService ?? ParametresService();

  final Database? _injectedDb;
  final StockService _stock;
  final ValorisationRepository _valorisation;
  final ParametresService _parametres;

  Future<Database> get _db async =>
      _injectedDb ?? DatabaseService.instance.database;

  /// Préfixe des tickets de caisse.
  ///
  /// Distinct des `FAC…` que l'import Sage apporte : un ticket encaissé
  /// ici et une facture venue de Sage ne sont pas la même pièce, et les
  /// mélanger rendrait une numérotation impossible à reprendre.
  static const String prefixeTicket = 'TKT';

  /// Le point de vente à proposer à l'ouverture de la caisse.
  ///
  /// Un seul magasin : c'est celui-là. Le caissier ne décide rien en
  /// le confirmant, et une frappe de plus à chaque vente se paie cent
  /// fois dans une journée de comptoir.
  ///
  /// Plusieurs : **rien**. Une vente imputée au mauvais magasin fausse
  /// deux soldes en silence, et une corruption silencieuse est pire
  /// qu'une question posée — c'est le refus que ce projet tient de
  /// l'import Sage jusqu'à la reprise des tiers.
  ///
  /// Un choix déjà fait est gardé, sauf si le magasin a disparu
  /// entre-temps : une liste déroulante ouverte sur une valeur qu'elle
  /// ne propose pas est une valeur que Flutter refuse de construire.
  static int? pointDeVenteParDefaut(List<int> magasins, {int? choisi}) {
    if (choisi != null && magasins.contains(choisi)) return choisi;
    if (magasins.length == 1) return magasins.single;
    return null;
  }

  /// Le prochain numéro libre, calculé sur le maximum observé.
  ///
  /// Calculé plutôt que stocké dans un compteur : un compteur se
  /// désynchronise d'une base restaurée ou fusionnée, alors que le
  /// maximum observé reste vrai quoi qu'il arrive. Même raisonnement
  /// que le code des tiers.
  Future<String> prochainTicket() async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT invoice_number FROM stock_outputs '
      'WHERE invoice_number LIKE ? ORDER BY invoice_number DESC LIMIT 1',
      ['$prefixeTicket%'],
    );
    var suivant = 1;
    if (rows.isNotEmpty) {
      final dernier = int.tryParse(
        (rows.first['invoice_number'] as String).substring(prefixeTicket.length),
      );
      if (dernier != null) suivant = dernier + 1;
    }
    return '$prefixeTicket${suivant.toString().padLeft(7, '0')}';
  }

  /// Encaisse un panier : une sortie par ligne, toutes en une fois.
  ///
  /// Ce qui est refusé, et pourquoi. Un **panier vide** n'a rien à
  /// encaisser. Une **quantité nulle ou négative** inverserait le sens
  /// de la vente sans le dire. Un **prix négatif** fausserait tout total
  /// qui le rencontrerait — une remise se saisit comme un prix plus bas,
  /// pas comme un prix à l'envers.
  ///
  /// Il n'y a en revanche **pas de prix imposé par le catalogue** : la
  /// ligne porte ce qui a été réellement pratiqué. Un article sans prix
  /// au catalogue se vend donc, à condition qu'un prix soit saisi — ce
  /// qu'exige l'écran. Refuser l'article rendrait la caisse inutilisable
  /// sur les 583 articles qui n'ont pas encore de tarif ; accepter une
  /// vente sans prix rendrait le chiffre d'affaires inconnaissable.
  ///
  /// Ce qui est seulement signalé : un stock passé sous zéro. La
  /// marchandise est partie avec le client, et le nier ne la ramènerait
  /// pas.
  ///
  /// Toutes les lignes s'écrivent dans une seule transaction : un ticket
  /// à moitié enregistré, c'est de la marchandise sortie sans être
  /// facturée.
  Future<ResultatVente> encaisser({
    required int magasinId,
    required List<LigneVente> lignes,
    int? tiersId,
    String? client,
    DateTime? le,
  }) async {
    if (lignes.isEmpty) {
      throw const ErreurUtilisateur('Le panier est vide.');
    }
    for (final ligne in lignes) {
      if (ligne.quantite <= 0) {
        throw ErreurUtilisateur(
          'La quantité vendue pour ${ligne.reference} doit être '
          'supérieure à 0.',
        );
      }
      if (ligne.prixUnitaire.estNegatif) {
        throw ErreurUtilisateur(
          'Le prix de ${ligne.reference} ne peut pas être négatif.',
        );
      }
    }

    // Relevé d'avant : ce que cette vente creuse, et rien d'autre.
    final negatifs = <String>[];
    for (final ligne in lignes) {
      final avant = await _stock.solde(
        reference: ligne.reference,
        magasinId: magasinId,
      );
      final apres = avant - ligne.quantite;
      if (apres < 0 && avant >= 0) {
        negatifs.add('${ligne.reference} : $apres.');
      }
    }

    final devise = await _parametres.devise();
    final ticket = await prochainTicket();
    final date = _iso(le ?? DateTime.now());
    final db = await _db;

    await db.transaction((txn) async {
      for (final ligne in lignes) {
        await txn.insert('stock_outputs', {
          'date': date,
          'reference': ligne.reference,
          'designation': ligne.designation,
          'invoice_number': ticket,
          'store_id': magasinId,
          'destination': client ?? '',
          'quantity': ligne.quantite,
          'tiers_id': tiersId,
          'prix_unitaire': ligne.prixUnitaire.unites,
          'sync_id': newSyncId(),
          'updated_at': nowIso(),
          ...attribution(),
        });
      }
    });

    var total = Montant(0, devise: devise);
    for (final ligne in lignes) {
      total = total + ligne.total;
    }

    return ResultatVente(
      numeroTicket: ticket,
      lignes: lignes.length,
      total: total,
      negatifs: negatifs,
    );
  }

  /// Ce qu'un magasin a encaissé sur une période.
  ///
  /// Rend aussi le nombre de lignes laissées de côté faute de prix :
  /// les 5 201 mouvements antérieurs n'en ont pas, et les compter pour
  /// zéro ferait passer « on ne sait pas » pour « ça n'a rien
  /// rapporté ».
  Future<({int total, int lignes, int lignesSansPrix})> chiffreDAffaires({
    int? magasinId,
    String? du,
    String? au,
  }) =>
      _valorisation.ventes(magasinId: magasinId, du: du, au: au);

  /// Les lignes d'un ticket, telles qu'elles ont été enregistrées.
  Future<List<LigneVente>> lignesDuTicket(String numero) async {
    final db = await _db;
    final devise = await _parametres.devise();
    final rows = await db.query(
      'stock_outputs',
      where: 'invoice_number = ?',
      whereArgs: [numero],
      orderBy: 'id',
    );
    return rows
        .map((row) => LigneVente(
              reference: row['reference'] as String,
              designation: row['designation'] as String,
              quantite: (row['quantity'] as num).toInt(),
              prixUnitaire: Montant(
                (row['prix_unitaire'] as num?)?.toInt() ?? 0,
                devise: devise,
              ),
            ))
        .toList();
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
