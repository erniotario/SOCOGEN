import 'package:sqflite/sqflite.dart';

import 'package:erp/core/db/database_service.dart';
import 'package:erp/core/db/sync_columns.dart';
import 'package:erp/core/db/verrou_comptable.dart';
import 'package:erp/core/errors/messages.dart';
import 'package:erp/core/money/montant.dart';
import 'package:erp/modules/parametres/services/parametres_service.dart';
import 'package:erp/shared/models/comptabilite.dart';

/// La comptabilité : fermer une période, et dire ce qu'elle a collecté.
///
/// Fermer est le contrôle qui manquait le plus. Tant qu'un mouvement de
/// mars pouvait être corrigé en décembre, aucune déclaration n'était
/// définitive — et une déclaration qu'on peut réécrire ne vaut rien.
///
/// Ce service **charge** la limite et la pose dans `VerrouComptable` ;
/// c'est le noyau qui l'applique à chaque écriture. La même répartition
/// que les permissions : le module sait d'où vient la règle, le noyau
/// sait l'opposer, et aucun chemin d'écriture ne peut l'oublier.
class ComptabiliteService {
  ComptabiliteService({
    Database? database,
    ParametresService? parametresService,
  })  : _injectedDb = database,
        _parametres = parametresService ?? ParametresService();

  final Database? _injectedDb;
  final ParametresService _parametres;

  Future<Database> get _db async =>
      _injectedDb ?? DatabaseService.instance.database;

  // --- La période fermée ---------------------------------------------

  /// Relit la limite en base et la pose dans le noyau.
  ///
  /// Appelé au démarrage et après chaque acte. Le verrou est ambiant,
  /// donc il doit être rechargé là où il est posé — et une seule fois,
  /// pas à chaque écriture : une requête par ligne de mouvement sur un
  /// import de 5 000 lignes se sentirait.
  Future<String?> charger() async {
    final limite = await limiteCourante();
    VerrouComptable.instance.definir(limite);
    return limite;
  }

  /// Le dernier jour fermé, ou nul si rien ne l'est.
  ///
  /// C'est le **dernier acte posé** qui fait foi, pas le maximum des
  /// dates : une réouverture doit pouvoir reculer la limite, et prendre
  /// le maximum la rendrait sans effet.
  Future<String?> limiteCourante() async {
    final db = await _db;
    final rows = await db.query(
      'cloture_comptable',
      columns: ['ferme_jusquau'],
      orderBy: 'id DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final valeur = (rows.first['ferme_jusquau'] as String?)?.trim();
    // Une limite vide est la trace d'une réouverture totale : plus rien
    // n'est fermé.
    return (valeur == null || valeur.isEmpty) ? null : valeur;
  }

  /// Ferme les livres jusqu'à [jusquau] inclus.
  ///
  /// Refusé dans deux cas. **Une date à venir** : on ne ferme pas une
  /// période qui n'a pas eu lieu, et le faire empêcherait de saisir la
  /// vente de cet après-midi. **Une date antérieure à la limite** :
  /// reculer est une réouverture, elle a sa propre méthode et elle
  /// exige un motif — laisser `cloturer` le faire en silence ferait
  /// rouvrir une période par inadvertance.
  Future<void> cloturer({required DateTime jusquau, String? motif}) async {
    final jour = _iso(jusquau);
    final aujourdhui = _iso(DateTime.now());
    if (jour.compareTo(aujourdhui) > 0) {
      throw const ErreurUtilisateur(
        'On ne clôture pas une période qui n\'a pas encore eu lieu : '
        'choisissez une date passée ou aujourd\'hui.',
      );
    }
    final limite = await limiteCourante();
    if (limite != null && jour.compareTo(limite) < 0) {
      throw ErreurUtilisateur(
        'Les livres sont déjà fermés jusqu\'au $limite. Reculer la '
        'limite est une réouverture, et elle demande un motif.',
      );
    }
    await _poser(jour, motif);
  }

  /// Recule la limite à [jusquau], ou l'enlève entièrement si nul.
  ///
  /// Le motif est **obligatoire**. Rouvrir une période déjà déclarée
  /// est l'acte qu'un contrôle regardera en premier ; le laisser se
  /// poser sans un mot d'explication reviendrait à ne pas le tracer.
  Future<void> rouvrir({DateTime? jusquau, required String motif}) async {
    if (motif.trim().isEmpty) {
      throw const ErreurUtilisateur(
        'Une réouverture demande un motif : c\'est ce qui restera au '
        'dossier pour expliquer pourquoi une période fermée a été '
        'rouverte.',
      );
    }
    final limite = await limiteCourante();
    if (limite == null) {
      throw const ErreurUtilisateur(
        'Aucune période n\'est fermée : il n\'y a rien à rouvrir.',
      );
    }
    final jour = jusquau == null ? '' : _iso(jusquau);
    if (jour.isNotEmpty && jour.compareTo(limite) >= 0) {
      throw ErreurUtilisateur(
        'Rouvrir demande une date antérieure au $limite. Pour fermer '
        'davantage, utilisez la clôture.',
      );
    }
    await _poser(jour, motif);
  }

  Future<void> _poser(String jour, String? motif) async {
    final db = await _db;
    await db.insert('cloture_comptable', {
      'ferme_jusquau': jour,
      'motif': motif?.trim().isEmpty ?? true ? null : motif!.trim(),
      'sync_id': newSyncId(),
      'updated_at': nowIso(),
      ...attribution(),
    });
    await charger();
  }

  /// Tous les actes, du plus récent au plus ancien.
  ///
  /// Rien n'est écrasé : c'est l'historique qui répond à « qui a
  /// rouvert mars, et pourquoi ».
  Future<List<ActeCloture>> historique() async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT c.id AS id, c.ferme_jusquau AS jour, c.motif AS motif, '
      'c.created_at AS quand, u.username AS auteur '
      'FROM cloture_comptable c '
      'LEFT JOIN users u ON u.id = c.created_by '
      'ORDER BY c.id DESC',
    );
    // Un acte est une réouverture s'il recule par rapport au précédent,
    // ce qui se lit sur la suite elle-même plutôt que sur une colonne
    // qu'il faudrait tenir à jour.
    final actes = <ActeCloture>[];
    for (var i = 0; i < rows.length; i++) {
      final jour = (rows[i]['jour'] as String?) ?? '';
      final precedent = i + 1 < rows.length
          ? (rows[i + 1]['jour'] as String?) ?? ''
          : null;
      actes.add(ActeCloture(
        id: rows[i]['id'] as int,
        fermeJusquau: jour,
        motif: rows[i]['motif'] as String?,
        auteur: rows[i]['auteur'] as String?,
        quand: rows[i]['quand'] as String?,
        estUneReouverture:
            precedent != null && jour.compareTo(precedent) < 0,
      ));
    }
    return actes;
  }

  // --- La TVA collectée ------------------------------------------------

  /// Ce que les ventes ont collecté entre [du] et [au] inclus.
  ///
  /// Les taux sont lus **sur les lignes**, pas sur les articles : c'est
  /// ce qui a été facturé qui se déclare, et non ce que le catalogue
  /// dit aujourd'hui. Un transfert est exclu — la marchandise n'a pas
  /// quitté l'entreprise, donc rien n'a été collecté.
  Future<DeclarationTva> tvaCollectee({
    required DateTime du,
    required DateTime au,
  }) async {
    final db = await _db;
    final devise = await _parametres.devise();
    final zero = Montant(0, devise: devise);
    final debut = _iso(du);
    final fin = _iso(au);
    if (fin.compareTo(debut) < 0) {
      throw const ErreurUtilisateur(
        'La fin de période est avant son début.',
      );
    }

    final rows = await db.rawQuery(
      'SELECT tva_pour_dix_mille AS taux, '
      'SUM(quantity * prix_unitaire) AS ttc, COUNT(*) AS lignes '
      'FROM stock_outputs '
      'WHERE substr(date, 1, 10) BETWEEN ? AND ? '
      'AND transfert_id IS NULL AND prix_unitaire IS NOT NULL '
      'GROUP BY tva_pour_dix_mille',
      [debut, fin],
    );

    final lignes = <LigneTva>[];
    var ttcSansTaux = zero;
    var lignesSansTaux = 0;
    for (final row in rows) {
      final ttc = Montant((row['ttc'] as num).toInt(), devise: devise);
      final code = row['taux'] as int?;
      if (code == null) {
        ttcSansTaux = ttcSansTaux + ttc;
        lignesSansTaux += (row['lignes'] as num).toInt();
        continue;
      }
      final taux = Taux(code);
      // Le HT se retrouve en divisant par 1 + taux, jamais en retirant
      // le taux : 11 925 à 19,25 % font 10 000, pas 9 629.
      final ht = ttc.horsTaxe(taux);
      lignes.add(LigneTva(taux: taux, ttc: ttc, baseHt: ht, tva: ttc - ht));
    }
    lignes.sort((a, b) => b.taux.pourDixMille.compareTo(a.taux.pourDixMille));

    final sansPrix = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM stock_outputs '
          'WHERE substr(date, 1, 10) BETWEEN ? AND ? '
          'AND transfert_id IS NULL AND prix_unitaire IS NULL',
          [debut, fin],
        )) ??
        0;

    return DeclarationTva(
      du: debut,
      au: fin,
      lignes: lignes,
      ttcSansTaux: ttcSansTaux,
      lignesSansTaux: lignesSansTaux,
      lignesSansPrix: sansPrix,
      fermeJusquau: await limiteCourante(),
    );
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
