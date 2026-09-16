import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Les frontières entre modules, rendues exécutoires.
///
/// Dart ne sait pas empêcher un fichier d'en importer un autre à
/// l'intérieur du même package : la règle « un module ne touche pas les
/// internes d'un autre » ne tient donc que si quelque chose la vérifie.
/// C'est ce test, et c'est la seule chose qui distingue une architecture
/// modulaire d'un rangement de dossiers.
///
/// Les règles :
///   * un module n'importe d'un autre module que son dossier `services/`,
///     jamais ses `models/` ni ses `repositories/` ;
///   * `core/` ne porte aucun métier et n'importe aucun module ;
///   * `shared/` non plus — c'est du vocabulaire et du design system ;
///   * `core/` peut utiliser `shared/` : l'écran de connexion a le droit
///     au design system de l'application ;
///   * `shell/` échappe à tout, c'est la racine de composition et son
///     rôle est précisément d'assembler les modules entre eux.
///
/// [_detteConnue] gèle les manquements hérités de l'organisation
/// précédente, où ces frontières n'existaient pas. La liste ne peut que
/// rétrécir : un manquement nouveau fait échouer le test, et une entrée
/// devenue inutile le fait échouer aussi. Chaque phase qui crée les
/// services manquants en retire les lignes correspondantes.
const Set<String> _detteConnue = {
  'core/auth/auth_provider.dart -> modules/utilisateurs/models/user.dart',
  'core/auth/auth_provider.dart -> modules/utilisateurs/repositories/user_repository.dart',
  'core/sync/sync_server.dart -> modules/rapports/services/web_report_pages.dart',
  'modules/catalogue/repositories/product_repository.dart -> modules/stock/models/product_stock.dart',
  'modules/catalogue/ui/products_screen.dart -> modules/stock/models/product_stock.dart',
  'modules/catalogue/ui/products_screen.dart -> modules/stock/models/store.dart',
  'modules/catalogue/ui/products_screen.dart -> modules/stock/repositories/store_repository.dart',
  'modules/parametres/ui/company_setup_screen.dart -> modules/stock/repositories/store_repository.dart',
  'modules/rapports/services/transactions_pdf_service.dart -> modules/parametres/models/company_settings.dart',
  'modules/rapports/services/web_report_pages.dart -> modules/parametres/repositories/settings_repository.dart',
  'modules/rapports/services/web_report_pages.dart -> modules/stock/repositories/transaction_repository.dart',
  'modules/rapports/ui/dashboard_screen.dart -> modules/stock/repositories/stock_entry_repository.dart',
  'modules/rapports/ui/dashboard_screen.dart -> modules/stock/repositories/stock_output_repository.dart',
  'modules/rapports/ui/dashboard_screen.dart -> modules/stock/repositories/store_repository.dart',
  'modules/rapports/ui/reports_screen.dart -> modules/stock/models/store.dart',
  'modules/rapports/ui/reports_screen.dart -> modules/stock/repositories/store_repository.dart',
  'modules/stock/services/stock_import_service.dart -> modules/rapports/repositories/report_repository.dart',
  'modules/stock/ui/transactions_screen.dart -> modules/parametres/repositories/settings_repository.dart',
  'shared/models/view_models.dart -> modules/catalogue/models/product.dart',
  'shared/models/view_models.dart -> modules/stock/models/store.dart',
};

String _couche(String chemin) {
  if (chemin.startsWith('modules/')) return 'module:${chemin.split('/')[1]}';
  for (final racine in ['core', 'shared', 'shell']) {
    if (chemin.startsWith('$racine/')) return racine;
  }
  return 'racine';
}

/// Dit pourquoi un import est interdit, ou null s'il est permis.
String? _motifInterdiction(String source, String cible) {
  final de = _couche(source);
  final vers = _couche(cible);
  if (de == vers || de == 'shell') return null;

  if (de.startsWith('module:') && vers.startsWith('module:')) {
    if (!cible.contains('/services/')) {
      return "$de atteint l'intérieur de $vers au lieu de passer par ses services";
    }
    return null;
  }
  if ((de == 'core' || de == 'shared') && vers.startsWith('module:')) {
    return '$de ne doit porter aucun métier, or il importe $vers';
  }
  return null;
}

void main() {
  test("aucun module ne contourne les services d'un autre", () {
    final lib = Directory('lib');
    expect(
      lib.existsSync(),
      isTrue,
      reason: 'à lancer depuis flutter_app/',
    );

    final importRe = RegExp(
      r"^\s*(?:import|export)\s+'package:socogen/([^']+)'",
      multiLine: true,
    );

    final trouves = <String, String>{};
    for (final entite in lib.listSync(recursive: true)) {
      if (entite is! File || !entite.path.endsWith('.dart')) continue;
      final source = entite.path
          .replaceAll(r'\', '/')
          .replaceFirst(RegExp(r'^lib/'), '');
      for (final m in importRe.allMatches(entite.readAsStringSync())) {
        final cible = m.group(1)!;
        final motif = _motifInterdiction(source, cible);
        if (motif != null) trouves['$source -> $cible'] = motif;
      }
    }

    final nouveaux = trouves.keys
        .where((cle) => !_detteConnue.contains(cle))
        .toList()
      ..sort();
    expect(
      nouveaux,
      isEmpty,
      reason: 'Frontière de module franchie :\n'
          '${nouveaux.map((c) => '  $c\n      ${trouves[c]}').join('\n')}\n'
          'Passez par les services du module visé, ou exposez-en un.',
    );

    final resolus = _detteConnue
        .where((cle) => !trouves.containsKey(cle))
        .toList()
      ..sort();
    expect(
      resolus,
      isEmpty,
      reason: 'Dette déjà réglée, à retirer de _detteConnue :\n'
          '${resolus.map((c) => '  $c').join('\n')}',
    );
  });
}
