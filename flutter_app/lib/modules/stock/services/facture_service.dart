import 'package:sqflite/sqflite.dart';

import 'package:erp/core/db/database_service.dart';
import 'package:erp/core/errors/messages.dart';
import 'package:erp/core/money/montant.dart';
import 'package:erp/modules/parametres/services/parametres_service.dart';
import 'package:erp/modules/stock/services/paiement_service.dart';
import 'package:erp/shared/models/facture.dart';

/// Établit la facture d'une vente déjà encaissée.
///
/// Elle se relit des mouvements, comme le ticket : le papier remis au
/// client doit dire ce que le registre tient, et non ce que le panier
/// disait avant d'être écrit. Rien n'est enregistré — une facture n'est
/// pas une opération, c'est une lecture.
class FactureService {
  FactureService({
    Database? database,
    ParametresService? parametresService,
    PaiementService? paiementService,
  })  : _injectedDb = database,
        _parametres = parametresService ?? ParametresService(),
        _reglements = paiementService ??
            PaiementService(database: database);

  final Database? _injectedDb;
  final ParametresService _parametres;
  final PaiementService _reglements;

  Future<Database> get _db async =>
      _injectedDb ?? DatabaseService.instance.database;

  /// La facture du ticket [numero].
  ///
  /// Lève si le ticket n'existe pas : facturer un numéro sans lignes
  /// produirait une pièce à zéro qui a l'air valable.
  Future<Facture> pour(String numero) async {
    final db = await _db;
    final devise = await _parametres.devise();
    final rows = await db.rawQuery(
      'SELECT s.date AS date, s.reference AS reference, '
      's.designation AS designation, s.quantity AS quantity, '
      's.prix_unitaire AS prix_unitaire, '
      's.tva_pour_dix_mille AS taux, s.destination AS destination, '
      's.transfert_id AS transfert_id, '
      'm.name AS magasin, t.nom AS tiers, u.username AS caissier '
      'FROM stock_outputs s '
      'JOIN stores m ON m.id = s.store_id '
      'LEFT JOIN tiers t ON t.id = s.tiers_id '
      'LEFT JOIN users u ON u.id = s.created_by '
      'WHERE s.invoice_number = ? ORDER BY s.id',
      [numero],
    );
    if (rows.isEmpty) {
      throw ErreurUtilisateur(
        'Aucune vente ne porte le numéro $numero.',
      );
    }
    // Un transfert n'est pas une vente : la marchandise n'a pas quitté
    // l'entreprise, et facturer un déplacement entre ses propres
    // magasins produirait une pièce qui affirme une vente qui n'a pas
    // eu lieu.
    if (rows.every((row) => row['transfert_id'] != null)) {
      throw ErreurUtilisateur(
        '$numero est un transfert entre magasins, pas une vente : il '
        'ne peut pas être facturé.',
      );
    }

    final lignes = [
      for (final row in rows)
        LigneFacture(
          reference: row['reference'] as String,
          designation: row['designation'] as String,
          quantite: (row['quantity'] as num).toInt(),
          prixUnitaire: Montant(
            (row['prix_unitaire'] as num?)?.toInt() ?? 0,
            devise: devise,
          ),
          taux: row['taux'] == null
              ? null
              : Taux((row['taux'] as num).toInt()),
        ),
    ];

    final premiere = rows.first;
    final solde = await _reglements.solde(numero);

    return Facture(
      numero: numero,
      date: premiere['date'] as String,
      magasin: premiere['magasin'] as String,
      client: _premierNonVide([
        premiere['tiers'] as String?,
        premiere['destination'] as String?,
      ]),
      caissier: premiere['caissier'] as String?,
      lignes: lignes,
      ventilation: ventiler(lignes, devise: devise),
      totalTtc: _somme(lignes.map((l) => l.totalTtc), devise),
      regle: solde.regle,
      reste: solde.reste,
    );
  }

  /// Regroupe les lignes par taux, du plus élevé au plus bas.
  ///
  /// Les bases sont sommées **avant** d'en tirer la TVA plutôt que
  /// ligne à ligne : arrondir chaque ligne puis additionner décale le
  /// total de quelques francs par rapport au même calcul fait d'un
  /// coup, et c'est ce genre d'écart qu'un client relève.
  ///
  /// Les lignes sans taux sont **écartées**, jamais comptées à zéro :
  /// « on ne sait pas » n'est pas « exonéré ». La facture les nomme
  /// ailleurs, et leur TTC reste dans le total général.
  static List<VentilationTva> ventiler(
    List<LigneFacture> lignes, {
    required Devise devise,
  }) {
    final parTaux = <int, Montant>{};
    for (final ligne in lignes) {
      final taux = ligne.taux;
      if (taux == null) continue;
      parTaux[taux.pourDixMille] =
          (parTaux[taux.pourDixMille] ?? Montant(0, devise: devise)) +
              ligne.totalTtc;
    }
    final codes = parTaux.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      for (final code in codes)
        () {
          final taux = Taux(code);
          final ttc = parTaux[code]!;
          final ht = ttc.horsTaxe(taux);
          return VentilationTva(taux: taux, baseHt: ht, tva: ttc - ht);
        }(),
    ];
  }

  static Montant _somme(Iterable<Montant> montants, Devise devise) {
    var total = Montant(0, devise: devise);
    for (final montant in montants) {
      total = total + montant;
    }
    return total;
  }

  static String? _premierNonVide(List<String?> candidats) {
    for (final candidat in candidats) {
      if (candidat != null && candidat.trim().isNotEmpty) return candidat;
    }
    return null;
  }
}
