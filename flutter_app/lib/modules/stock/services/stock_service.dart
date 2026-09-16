import 'package:socogen/modules/stock/repositories/stock_repository.dart';
import 'package:socogen/shared/models/view_models.dart';

/// Ce que le stock expose aux autres modules — et à ses propres écrans.
///
/// La caisse aura besoin de savoir ce qu'il reste avant d'encaisser, les
/// ventes avant de livrer, les rapports pour signaler une anomalie.
/// Aucun d'eux n'a à connaître le SQL qui dérive un solde ; ils posent
/// la question, le module stock répond.
class StockService {
  StockService({StockRepository? stockRepository})
      : _stock = stockRepository ?? StockRepository();

  final StockRepository _stock;

  /// Ce que le registre dit du stock de [reference] dans [magasinId].
  ///
  /// [exclureEntreeId] et [exclureSortieId] servent à juger une
  /// *modification* : le solde doit être calculé sans la ligne qu'on est
  /// en train de changer, sinon son ancien chiffre compte encore et la
  /// modification paraît anodine jusqu'à l'enregistrement.
  Future<int> solde({
    required String reference,
    required int magasinId,
    int? exclureEntreeId,
    int? exclureSortieId,
  }) =>
      _stock.balanceExcluding(
        reference: reference,
        storeId: magasinId,
        excludeEntryId: exclureEntreeId,
        excludeOutputId: exclureSortieId,
      );

  /// Ce qui reste de [reference], magasin par magasin.
  ///
  /// Ne liste que les magasins où l'article a une ligne de stock.
  Future<List<StoreAvailability>> disponibiliteParMagasin({
    required String reference,
    required int articleId,
  }) =>
      _stock.getStoreAvailability(reference, articleId);

  /// Ce que [quantite] sortie de [magasinId] laisserait derrière elle.
  ///
  /// Négatif veut dire que la sortie creuserait un trou. Les trois
  /// chemins d'écriture s'en servent pour prévenir avant d'enregistrer —
  /// la politique de ce projet est d'avertir puis d'inscrire, jamais de
  /// refuser en silence : un magasinier dont la marchandise est
  /// physiquement partie doit pouvoir le dire.
  Future<int> soldeApresSortie({
    required String reference,
    required int magasinId,
    required int quantite,
    int? exclureSortieId,
  }) async {
    final actuel = await solde(
      reference: reference,
      magasinId: magasinId,
      exclureSortieId: exclureSortieId,
    );
    return actuel - quantite;
  }

  /// Vrai si l'article a déjà une ligne de stock dans ce magasin.
  Future<bool> ligneDeStockExiste({
    required int articleId,
    required int magasinId,
  }) =>
      _stock.productStockExists(articleId, magasinId);

  /// Pose ou met à jour le stock d'ouverture de (article, magasin).
  ///
  /// C'est bien une *ouverture* qu'on écrit ici, jamais un stock
  /// courant : celui-ci reste dérivé des mouvements. Y verser un stock
  /// courant puis importer les mouvements les compterait deux fois.
  Future<void> definirStockOuverture({
    required int articleId,
    required int magasinId,
    required int quantite,
  }) =>
      _stock.upsertProductStock(
        productId: articleId,
        storeId: magasinId,
        initialStock: quantite,
      );
}
