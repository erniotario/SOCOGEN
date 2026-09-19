import 'package:socogen/core/errors/messages.dart';
import 'package:socogen/core/money/montant.dart';
import 'package:socogen/modules/parametres/services/parametres_service.dart';
import 'package:socogen/modules/tiers/models/tiers.dart';
import 'package:socogen/modules/tiers/repositories/tiers_repository.dart';

/// Ce que les tiers exposent aux autres modules.
///
/// Le stock y puise pour proposer un fournisseur à l'entrée et un client
/// à la sortie ; les ventes et la caisse y puiseront pour identifier
/// l'acheteur. Aucun d'eux n'a à connaître la table.
class TiersService {
  TiersService({
    TiersRepository? tiersRepository,
    ParametresService? parametresService,
  })  : _tiers = tiersRepository ?? TiersRepository(),
        _parametres = parametresService ?? ParametresService();

  final TiersRepository _tiers;
  final ParametresService _parametres;

  Future<List<Tiers>> listerClients() =>
      _tiers.getAll(type: TypeTiers.client);

  Future<List<Tiers>> listerFournisseurs() =>
      _tiers.getAll(type: TypeTiers.fournisseur);

  Future<List<Tiers>> lister({TypeTiers? type, bool actifsSeuls = true}) =>
      _tiers.getAll(type: type, actifsSeuls: actifsSeuls);

  Future<List<Tiers>> rechercher(String terme, {TypeTiers? type}) =>
      _tiers.rechercher(terme, type: type);

  Future<Tiers?> parId(int id) => _tiers.getById(id);

  /// Retrouve un tiers par son nom exact.
  ///
  /// C'est la clé par laquelle les mouvements déjà saisis ont été
  /// rattachés : l'import Sage et la reprise s'en servent pour ne pas
  /// recréer une fiche qui existe.
  Future<Tiers?> parNom(String nom) => _tiers.getParNom(nom);

  /// Crée une fiche, en lui attribuant le prochain code libre.
  Future<int> creer({
    required String nom,
    TypeTiers type = TypeTiers.client,
    String? niu,
    String? rccm,
    String? telephone,
    String? email,
    String? ville,
    String? adresse,
    Montant? plafondCredit,
  }) async {
    final existant = await _tiers.getParNom(nom);
    if (existant != null) {
      throw ErreurUtilisateur(
        'Une fiche « ${existant.nom} » existe déjà sous le code '
        '${existant.code}.',
      );
    }
    if (plafondCredit != null && plafondCredit.estNegatif) {
      throw const ErreurUtilisateur(
        'Un plafond de crédit ne peut pas être négatif.',
      );
    }
    return _tiers.create(Tiers(
      id: 0,
      code: await _tiers.prochainCode(type),
      nom: nom,
      type: type,
      niu: niu,
      rccm: rccm,
      telephone: telephone,
      email: email,
      ville: ville,
      adresse: adresse,
      plafondCreditUnites: plafondCredit?.unites,
    ));
  }

  Future<void> modifier(Tiers tiers) => _tiers.update(tiers);

  /// Le plafond de crédit, dans la devise de l'entreprise.
  Future<Montant?> plafondCredit(Tiers tiers) async {
    final unites = tiers.plafondCreditUnites;
    if (unites == null) return null;
    return Montant(unites, devise: await _parametres.devise());
  }

  Future<int> compterMouvements(int tiersId) =>
      _tiers.compterMouvements(tiersId);

  /// Retire un tiers de la saisie sans toucher à son historique.
  Future<void> desactiver(int id) => _tiers.desactiver(id);

  Future<void> reactiver(int id) => _tiers.reactiver(id);

  /// Réunit deux fiches qui désignent le même partenaire.
  ///
  /// Rend le nombre de mouvements déplacés, pour que l'écran puisse dire
  /// ce qui a bougé plutôt qu'un « terminé » muet.
  Future<int> fusionner({required int sourceId, required int cibleId}) =>
      _tiers.fusionner(sourceId: sourceId, cibleId: cibleId);
}
