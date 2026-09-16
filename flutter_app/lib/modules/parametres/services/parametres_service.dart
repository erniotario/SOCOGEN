import 'package:socogen/core/money/montant.dart';
import 'package:socogen/modules/parametres/models/company_settings.dart';
import 'package:socogen/modules/parametres/repositories/settings_repository.dart';
import 'package:socogen/modules/parametres/repositories/tva_repository.dart';
import 'package:socogen/shared/models/taux_tva.dart';

/// Ce que les autres modules ont le droit de demander aux paramètres.
///
/// Les dépôts restent internes : un module qui veut la devise ou un taux
/// passe par ici. C'est peu de chose aujourd'hui, et c'est justement le
/// moment de le poser — quand les ventes, le POS et la comptabilité
/// réclameront tous la même règle fiscale, elle sera déjà à un seul
/// endroit.
class ParametresService {
  ParametresService({
    SettingsRepository? settingsRepository,
    TvaRepository? tvaRepository,
  })  : _settings = settingsRepository ?? SettingsRepository(),
        _tva = tvaRepository ?? TvaRepository();

  final SettingsRepository _settings;
  final TvaRepository _tva;

  /// La devise dans laquelle l'entreprise compte.
  ///
  /// Le franc CFA par défaut : c'est le marché de cette application, et
  /// une devise inconnue vaut mieux lue comme la plus probable que comme
  /// une erreur bloquante au milieu d'un encaissement.
  Future<Devise> devise() async {
    final societe = await _settings.getSettings();
    return switch (societe.devise) {
      'EUR' => Devise.eur,
      _ => Devise.xaf,
    };
  }

  Future<CompanySettings> societe() => _settings.getSettings();

  /// Les taux de TVA applicables, de l'exonéré au plus élevé.
  Future<List<TauxTva>> tauxTva() => _tva.getAll();

  Future<TauxTva?> tauxTvaParId(int id) => _tva.getById(id);

  /// Le taux proposé par défaut à la création d'un article, s'il existe.
  Future<TauxTva?> tauxTvaParDefaut() => _tva.getDefaut();
}
