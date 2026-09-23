import 'package:erp/core/errors/messages.dart';
import 'package:erp/core/money/montant.dart';
import 'package:erp/modules/catalogue/models/famille.dart';
import 'package:erp/modules/catalogue/models/product.dart';
import 'package:erp/modules/catalogue/repositories/famille_repository.dart';
import 'package:erp/modules/catalogue/repositories/product_repository.dart';
import 'package:erp/modules/parametres/services/parametres_service.dart';
import 'package:erp/shared/models/view_models.dart';

/// Ce que le catalogue expose aux autres modules.
///
/// Le stock, les rapports et bientôt la caisse ont besoin d'articles ;
/// jusqu'ici ils allaient chercher `ProductRepository` directement, ce
/// qui liait leur code au SQL du catalogue. Ils passent maintenant par
/// ici, et le SQL redevient une affaire interne.
///
/// Le service est aussi l'endroit où un prix redevient un [Montant] :
/// la base stocke des entiers d'unités minimales, la devise appartient
/// aux paramètres de l'entreprise, et personne d'autre n'a à savoir
/// recoller les deux.
class CatalogueService {
  CatalogueService({
    ProductRepository? productRepository,
    FamilleRepository? familleRepository,
    ParametresService? parametresService,
  })  : _produits = productRepository ?? ProductRepository(),
        _familles = familleRepository ?? FamilleRepository(),
        _parametres = parametresService ?? ParametresService();

  final ProductRepository _produits;
  final FamilleRepository _familles;
  final ParametresService _parametres;

  /// Les articles avec leurs chiffres de stock agrégés.
  ///
  /// La moitié « stock » de cette vue appartient au module stock et
  /// migrera là-bas quand la phase 3 le remaniera ; d'ici là elle reste
  /// servie ici, parce que c'est ce dont les écrans se servent.
  Future<List<ProductOverview>> listerArticles({String? recherche}) =>
      _produits.getProductOverviews(search: recherche);

  Future<Product?> chercherParReference(String reference) =>
      _produits.getByReference(reference);

  /// Retrouve un article par son code-barres — ce que fera la douchette.
  Future<Product?> chercherParCodeBarre(String codeBarre) =>
      _produits.getByCodeBarre(codeBarre);

  Future<bool> referenceExiste(String reference, {int? sauf}) =>
      _produits.referenceExists(reference, excludeId: sauf);

  /// Crée un article. Tout ce qui touche au tarif est facultatif : un
  /// article importé arrive sans prix, et lui en inventer un serait pire
  /// que de laisser la case vide.
  Future<int> creerArticle({
    required String reference,
    required String designation,
    String unite = 'unité',
    int? familleId,
    int? tvaId,
    int? prixAchatUnites,
    int? prixVenteUnites,
    String? codeBarre,
  }) =>
      _produits.createProduct(
        reference: reference,
        designation: designation,
        unit: unite,
        familleId: familleId,
        tvaId: tvaId,
        prixAchatUnites: prixAchatUnites,
        prixVenteUnites: prixVenteUnites,
        codeBarre: codeBarre,
      );

  /// Pose les prix qui manquent à un article, sans jamais en écraser un.
  ///
  /// Le catalogue réel arrive sans aucun prix : sans cette reprise, il
  /// faudrait en saisir 723 à la main. Mais un prix déjà en place est
  /// une décision de quelqu'un — corrigée dans l'application après un
  /// import précédent, par exemple — et un classeur plus ancien ne doit
  /// pas la défaire en silence.
  ///
  /// Rend ce qui a été fait : `(posé, conservé)`. L'appelant compte,
  /// parce que savoir qu'un prix n'a pas été touché est ce qui permet
  /// d'y revenir sciemment.
  Future<({bool pose, bool conserve})> completerPrix(
    String reference, {
    Montant? prixVente,
    Montant? prixAchat,
  }) async {
    final article = await _produits.getByReference(reference);
    if (article == null) return (pose: false, conserve: false);

    final poseVente = prixVente != null && article.prixVenteUnites == null;
    final poseAchat = prixAchat != null && article.prixAchatUnites == null;
    final garde = (prixVente != null && article.prixVenteUnites != null) ||
        (prixAchat != null && article.prixAchatUnites != null);

    if (poseVente || poseAchat) {
      await _produits.updateProduct(article.copyWith(
        prixVenteUnites: poseVente ? prixVente.unites : null,
        prixAchatUnites: poseAchat ? prixAchat.unites : null,
      ));
    }
    return (pose: poseVente || poseAchat, conserve: garde);
  }

  /// Enregistre un article modifié, tel qu'il est fourni.
  ///
  /// Les drapeaux `effacer*` de [Product.copyWith] restent la façon de
  /// retirer une valeur : ici, ce qui est nul est simplement conservé.
  Future<void> modifierArticle(Product article) =>
      _produits.updateProduct(article);

  Future<List<Famille>> listerFamilles() => _familles.getAll();

  /// Le chemin d'une famille, « Alimentaire › Boissons › Sodas ».
  Future<String> cheminFamille(int familleId, {String separateur = ' › '}) async {
    final chemin = await _familles.getChemin(familleId);
    return chemin.map((f) => f.nom).join(separateur);
  }

  /// Le prix de vente d'un article, ou null s'il n'en a pas.
  ///
  /// Null n'est pas zéro : un article sans prix n'est pas gratuit, il
  /// n'est pas tarifé, et la caisse doit refuser de l'encaisser plutôt
  /// que de l'offrir.
  Future<Montant?> prixDeVente(Product article) async {
    final unites = article.prixVenteUnites;
    if (unites == null) return null;
    return Montant(unites, devise: await _parametres.devise());
  }

  Future<Montant?> prixDAchat(Product article) async {
    final unites = article.prixAchatUnites;
    if (unites == null) return null;
    return Montant(unites, devise: await _parametres.devise());
  }

  /// Le prix de vente TTC, TVA de l'article comprise.
  ///
  /// Un article sans taux est traité comme non taxé plutôt que refusé :
  /// les articles hérités de Sage n'ont pas de TVA, et bloquer leur
  /// affichage rendrait le catalogue inutilisable en attendant qu'on les
  /// ait tous repris.
  Future<Montant?> prixDeVenteTtc(Product article) async {
    final ht = await prixDeVente(article);
    if (ht == null) return null;
    if (article.tvaId == null) return ht;
    final taux = await _parametres.tauxTvaParId(article.tvaId!);
    return taux == null ? ht : ht.majorerDe(taux.taux);
  }

  /// Enregistre le prix de vente d'un article.
  ///
  /// Refuse un prix négatif : une remise se saisit comme une remise, pas
  /// comme un prix à l'envers, et un prix négatif fausserait tout total
  /// qui le rencontrerait.
  Future<void> definirPrixDeVente(Product article, Montant? prix) async {
    if (prix != null && prix.estNegatif) {
      throw const ErreurUtilisateur(
        'Un prix de vente ne peut pas être négatif.',
      );
    }
    await _produits.updateProduct(
      article.copyWith(
        prixVenteUnites: prix?.unites,
        effacerPrixVente: prix == null,
      ),
    );
  }

  /// Le seuil qui vaut réellement pour cet article : le sien s'il en a
  /// un, sinon celui de l'entreprise.
  ///
  /// C'est la question que posent les écrans, et elle a une réponse même
  /// quand l'article n'a rien réglé — d'où ce service plutôt qu'une
  /// lecture directe de `article.stockMin`, qui rendrait null.
  Future<int> seuilDAlerte(Product article) async =>
      article.stockMin ?? await _parametres.seuilStockParDefaut();

  /// Enregistre le seuil d'alerte propre à un article.
  ///
  /// Null le retire : l'article repasse sous le seuil d'entreprise.
  /// Zéro est autre chose — une décision de ne jamais l'alerter — et se
  /// conserve tel quel. Un seuil négatif n'a pas de sens : aucun stock
  /// ne peut passer dessous, l'alerte ne se déclencherait jamais, et
  /// c'est plus probablement une faute de frappe qu'un choix.
  Future<void> definirSeuilDAlerte(Product article, int? seuil) async {
    if (seuil != null && seuil < 0) {
      throw const ErreurUtilisateur(
        'Un seuil de stock ne peut pas être négatif. '
        "Laissez le champ vide pour utiliser le seuil de l'entreprise.",
      );
    }
    await _produits.updateProduct(
      article.copyWith(stockMin: seuil, effacerStockMin: seuil == null),
    );
  }
}
