import 'package:sqflite/sqflite.dart';

import 'package:socogen/core/db/database_service.dart';

/// Ce que le stock vaut et ce que les ventes ont rapporté.
///
/// Tout se lit sur `prix_unitaire`, figé sur chaque mouvement au moment
/// de l'écriture. Aucune de ces requêtes ne va chercher le prix courant
/// d'un article : une vente de mars doit continuer de rapporter ce
/// qu'elle a rapporté, même si le tarif a changé depuis.
///
/// Les mouvements sans prix — les transferts, et les 5 201 lignes
/// antérieures à la v10 — sont **exclus des totaux**, pas comptés pour
/// zéro. La différence est celle entre « on ne sait pas » et « ça n'a
/// rien rapporté », et seul le premier est vrai.
class ValorisationRepository {
  ValorisationRepository({Database? database}) : _injectedDb = database;

  final Database? _injectedDb;

  Future<Database> get _db async =>
      _injectedDb ?? DatabaseService.instance.database;

  /// Ce que les sorties d'un magasin ont rapporté sur une période.
  ///
  /// C'est le chiffre d'affaires de la boutique : « la vente est la
  /// sortie dans le magasin de la boutique », donc les sorties valorisées
  /// de ce magasin *sont* les ventes.
  ///
  /// [lignesSansPrix] dit combien de sorties ont été laissées de côté
  /// faute de prix. Un total présenté sans ce nombre laisserait croire
  /// que la période entière est couverte.
  Future<({int total, int lignes, int lignesSansPrix})> ventes({
    int? magasinId,
    String? du,
    String? au,
  }) async {
    final db = await _db;
    final conditions = <String>[];
    final args = <Object?>[];
    if (magasinId != null) {
      conditions.add('store_id = ?');
      args.add(magasinId);
    }
    if (du != null) {
      conditions.add('date >= ?');
      args.add(du);
    }
    if (au != null) {
      conditions.add('date <= ?');
      args.add(au);
    }
    // Un transfert n'est pas une vente : la marchandise n'a pas quitté
    // l'entreprise, elle a changé de magasin.
    conditions.add('transfert_id IS NULL');
    final where = 'WHERE ${conditions.join(' AND ')}';

    final row = (await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN prix_unitaire IS NOT NULL
                          THEN quantity * prix_unitaire END), 0) AS total,
        SUM(CASE WHEN prix_unitaire IS NOT NULL THEN 1 ELSE 0 END) AS lignes,
        SUM(CASE WHEN prix_unitaire IS NULL THEN 1 ELSE 0 END) AS sans_prix
      FROM stock_outputs
      $where
    ''', args))
        .first;

    return (
      total: (row['total'] as num).toInt(),
      lignes: (row['lignes'] as num?)?.toInt() ?? 0,
      lignesSansPrix: (row['sans_prix'] as num?)?.toInt() ?? 0,
    );
  }

  /// Ce que le stock d'un magasin vaut, au prix d'achat de l'article.
  ///
  /// Au prix d'achat et non de vente : la valeur d'un stock est ce qu'il
  /// a coûté, pas ce qu'on espère en tirer. Le jour où il faudra du
  /// CUMP, c'est ici que le calcul changera — les mouvements portent
  /// déjà leur prix, il suffira de les pondérer au lieu de lire la
  /// fiche article.
  ///
  /// [articlesSansPrix] compte ceux qui n'en ont pas : leur stock est
  /// réel mais sa valeur est inconnue, et la taire ferait passer un
  /// inventaire à moitié valorisé pour un inventaire complet.
  Future<({int valeur, int articles, int articlesSansPrix})> valeurDuStock({
    int? magasinId,
  }) async {
    final db = await _db;
    final args = <Object?>[];
    var filtre = '';
    if (magasinId != null) {
      filtre = 'WHERE ps.store_id = ?';
      args.add(magasinId);
    }

    // Totaux pré-agrégés joints une fois, et non deux sous-requêtes
    // corrélées par (article × magasin) : c'est la différence entre
    // 63 ms et trois secondes sur ce catalogue.
    final row = (await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN prix_achat IS NOT NULL
                          THEN solde * prix_achat END), 0) AS valeur,
        SUM(CASE WHEN prix_achat IS NOT NULL THEN 1 ELSE 0 END) AS avec,
        SUM(CASE WHEN prix_achat IS NULL THEN 1 ELSE 0 END) AS sans
      FROM (
        SELECT
          p.prix_achat AS prix_achat,
          COALESCE(ps.initial_stock, 0)
            + COALESCE(e.total, 0) - COALESCE(o.total, 0) AS solde
        FROM product_stocks ps
        JOIN products p ON p.id = ps.product_id
        LEFT JOIN (
          SELECT reference, store_id, SUM(quantity) AS total
          FROM stock_entries GROUP BY reference, store_id
        ) e ON e.reference = p.reference AND e.store_id = ps.store_id
        LEFT JOIN (
          SELECT reference, store_id, SUM(quantity) AS total
          FROM stock_outputs GROUP BY reference, store_id
        ) o ON o.reference = p.reference AND o.store_id = ps.store_id
        $filtre
      )
    ''', args))
        .first;

    return (
      valeur: (row['valeur'] as num).toInt(),
      articles: (row['avec'] as num?)?.toInt() ?? 0,
      articlesSansPrix: (row['sans'] as num?)?.toInt() ?? 0,
    );
  }

}
