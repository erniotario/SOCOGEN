import 'package:sqflite/sqflite.dart';

import 'package:erp/core/db/database_service.dart';
import 'package:erp/core/money/montant.dart';
import 'package:erp/modules/parametres/services/parametres_service.dart';
import 'package:erp/modules/stock/services/facture_service.dart';
import 'package:erp/shared/models/cloture.dart';
import 'package:erp/shared/models/facture.dart';
import 'package:erp/shared/models/paiement.dart';

/// La clôture de caisse d'une journée.
///
/// Elle ne décide de rien et n'écrit rien : c'est une lecture, comme la
/// facture. Fermer une caisse au sens comptable — figer la journée,
/// interdire les corrections après coup — supposerait un exercice et
/// une écriture de clôture, et cela viendra avec la comptabilité.
///
/// Ce qu'elle apporte, c'est de **séparer deux chiffres** que tout le
/// monde confond : ce qui a été vendu et ce qui est entré. Un ticket
/// parti à crédit gonfle le premier sans toucher le second ; une
/// créance de la semaine dernière réglée ce matin fait l'inverse. Les
/// additionner ou les prendre l'un pour l'autre est la raison
/// ordinaire pour laquelle une caisse ne tombe pas juste.
class ClotureService {
  ClotureService({
    Database? database,
    ParametresService? parametresService,
  })  : _injectedDb = database,
        _parametres = parametresService ?? ParametresService();

  final Database? _injectedDb;
  final ParametresService _parametres;

  Future<Database> get _db async =>
      _injectedDb ?? DatabaseService.instance.database;

  /// La clôture du jour [date] (`AAAA-MM-JJ`), pour un magasin ou tous.
  Future<ClotureCaisse> pour({
    required String date,
    int? magasinId,
    String? nomMagasin,
  }) async {
    final db = await _db;
    final devise = await _parametres.devise();
    final zero = Montant(0, devise: devise);

    // Un transfert n'est pas une vente : la marchandise n'a pas quitté
    // l'entreprise. Même exclusion que la valorisation.
    final filtreMagasin = magasinId == null ? '' : 'AND s.store_id = ? ';
    final argsMagasin = magasinId == null ? const [] : [magasinId];

    final ventes = await db.rawQuery(
      'SELECT s.invoice_number AS ticket, s.quantity AS quantity, '
      's.prix_unitaire AS prix, s.tva_pour_dix_mille AS taux '
      'FROM stock_outputs s '
      'WHERE substr(s.date, 1, 10) = ? AND s.transfert_id IS NULL '
      '$filtreMagasin',
      [date, ...argsMagasin],
    );

    var ventesTtc = zero;
    var lignesSansPrix = 0;
    final lignesConnues = <LigneFacture>[];
    final tickets = <String>{};
    for (final ligne in ventes) {
      final prix = ligne['prix'] as int?;
      final numero = (ligne['ticket'] as String?)?.trim() ?? '';
      if (numero.isNotEmpty) tickets.add(numero);
      if (prix == null) {
        // Absent n'est pas nul : la ligne est comptée à part plutôt
        // que versée au total comme un zéro.
        lignesSansPrix++;
        continue;
      }
      final quantite = (ligne['quantity'] as num).toInt();
      final taux = ligne['taux'] as int?;
      final ligneFacture = LigneFacture(
        reference: '',
        designation: '',
        quantite: quantite,
        prixUnitaire: Montant(prix, devise: devise),
        taux: taux == null ? null : Taux(taux),
      );
      lignesConnues.add(ligneFacture);
      ventesTtc = ventesTtc + ligneFacture.totalTtc;
    }

    // La même ventilation que la facture, pour que le récapitulatif du
    // soir et la pièce remise au client ne puissent pas se contredire.
    final tva = FactureService.ventiler(lignesConnues, devise: devise);
    var ttcSansTaux = zero;
    for (final ligne in lignesConnues.where((l) => l.taux == null)) {
      ttcSansTaux = ttcSansTaux + ligne.totalTtc;
    }

    // Ce qui a été réglé sur les tickets du jour, quelle que soit la
    // date du règlement : le crédit accordé est ce qui reste dû sur ces
    // ventes-là, et un ticket réglé le lendemain n'était pas du crédit
    // au sens où on l'entend ici — il l'était le soir même.
    final regleSurLeJour = tickets.isEmpty
        ? 0
        : Sqflite.firstIntValue(await db.rawQuery(
              'SELECT COALESCE(SUM(montant), 0) FROM paiements '
              'WHERE ticket IN (${List.filled(tickets.length, '?').join(',')})',
              tickets.toList(),
            )) ??
            0;
    final credit = ventesTtc - Montant(regleSurLeJour, devise: devise);

    // Les encaissements du jour, rattachés au magasin par le ticket
    // qu'ils règlent.
    final encaissements = await db.rawQuery(
      'SELECT p.mode AS mode, p.montant AS montant, p.ticket AS ticket, '
      '(SELECT MIN(substr(s.date, 1, 10)) FROM stock_outputs s '
      ' WHERE s.invoice_number = p.ticket) AS date_vente '
      'FROM paiements p '
      'WHERE substr(p.date, 1, 10) = ? '
      '${magasinId == null ? '' : 'AND EXISTS (SELECT 1 FROM stock_outputs s '
          'WHERE s.invoice_number = p.ticket AND s.store_id = ?) '}',
      [date, ...argsMagasin],
    );

    final parMode = <ModePaiement, (Montant, int)>{};
    var duJour = zero;
    var surCreances = zero;
    for (final row in encaissements) {
      final mode = ModePaiement.depuisCode(row['mode'] as String?);
      final montant = Montant((row['montant'] as num).toInt(), devise: devise);
      final precedent = parMode[mode] ?? (zero, 0);
      parMode[mode] = (precedent.$1 + montant, precedent.$2 + 1);
      // Un règlement dont on ne retrouve pas la vente — ticket
      // supprimé depuis — est compté comme recouvrement plutôt que
      // rattaché d'office à aujourd'hui : l'argent est là, sa vente
      // n'est plus, et le ranger dans le chiffre du jour le
      // gonflerait.
      if (row['date_vente'] == date) {
        duJour = duJour + montant;
      } else {
        surCreances = surCreances + montant;
      }
    }

    return ClotureCaisse(
      date: date,
      magasin: nomMagasin,
      tickets: tickets.length,
      ventesTtc: ventesTtc,
      tva: tva,
      lignesSansPrix: lignesSansPrix,
      ttcSansTaux: ttcSansTaux,
      creditAccorde: credit.estNegatif ? zero : credit,
      encaisse: [
        for (final mode in ModePaiement.values)
          if (parMode.containsKey(mode))
            EncaisseParMode(
              mode: mode,
              montant: parMode[mode]!.$1,
              operations: parMode[mode]!.$2,
            ),
      ],
      encaisseDuJour: duJour,
      encaisseSurCreances: surCreances,
    );
  }
}
