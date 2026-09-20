import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:socogen/core/errors/messages.dart';
import 'package:socogen/core/events/data_refresh_bus.dart';
import 'package:socogen/core/money/montant.dart';
import 'package:socogen/modules/catalogue/services/catalogue_service.dart';
import 'package:socogen/modules/parametres/services/parametres_service.dart';
import 'package:socogen/modules/stock/models/store.dart';
import 'package:socogen/modules/stock/repositories/store_repository.dart';
import 'package:socogen/modules/stock/services/stock_service.dart';
import 'package:socogen/modules/stock/services/vente_service.dart';
import 'package:socogen/modules/tiers/services/tiers_service.dart';
import 'package:socogen/shared/models/tiers.dart';
import 'package:socogen/shared/models/vente.dart';
import 'package:socogen/shared/models/view_models.dart';
import 'package:socogen/shared/ui/theme/app_breakpoints.dart';
import 'package:socogen/shared/ui/theme/app_colors.dart';
import 'package:socogen/shared/ui/theme/app_spacing.dart';
import 'package:socogen/shared/ui/theme/app_text_styles.dart';
import 'package:socogen/shared/ui/widgets/adaptive_table.dart';
import 'package:socogen/shared/ui/widgets/product_autocomplete.dart';
import 'package:socogen/shared/ui/widgets/empty_state.dart';
import 'package:socogen/shared/ui/widgets/page_header.dart';
import 'package:socogen/shared/ui/widgets/row_actions.dart';
import 'package:socogen/shared/ui/widgets/section_card.dart';
import 'package:socogen/shared/ui/widgets/skeleton.dart';
import 'package:socogen/shared/ui/widgets/status_badge.dart';
import 'package:socogen/shared/ui/widgets/tiers_autocomplete.dart';

/// La caisse du point de vente.
///
/// « La vente est la sortie dans le magasin de la boutique » : cet écran
/// compose un panier et l'écrit en autant de sorties, toutes marquées du
/// même numéro de ticket. Rien n'est enregistré avant l'encaissement,
/// comme l'inventaire et les transferts.
///
/// Le prix est **toujours saisissable**, prérempli depuis le catalogue
/// quand l'article en a un. C'est le compromis entre deux exigences
/// contraires : 583 articles n'ont pas encore de tarif et refuser de les
/// vendre rendrait la caisse inutilisable, tandis qu'accepter une vente
/// sans prix rendrait le chiffre d'affaires inconnaissable. Le prix est
/// donc obligatoire à la ligne, mais il n'a pas à venir de la fiche.
class CaisseScreen extends StatefulWidget {
  const CaisseScreen({super.key});

  @override
  State<CaisseScreen> createState() => _CaisseScreenState();
}

class _DonneesCaisse {
  final List<ProductOverview> articles;
  final List<Store> magasins;
  final List<Tiers> clients;
  final Devise devise;

  const _DonneesCaisse({
    required this.articles,
    required this.magasins,
    required this.clients,
    required this.devise,
  });
}

class _CaisseScreenState extends State<CaisseScreen> {
  final _caisse = VenteService();
  final _catalogue = CatalogueService();
  final _magasinsRepo = StoreRepository();
  final _tiers = TiersService();
  final _parametres = ParametresService();
  final _stock = StockService();

  late Future<_DonneesCaisse> _future;

  int? _magasinId;
  final _panier = <LigneVente>[];

  final _refController = TextEditingController();
  final _quantiteController = TextEditingController(text: '1');
  final _prixController = TextEditingController();
  final _clientController = TextEditingController();
  ProductOverview? _article;
  int? _clientId;
  int? _disponible;
  String? _erreur;
  bool _enCours = false;

  @override
  void initState() {
    super.initState();
    _future = _charger();
    DataRefreshBus.instance.addListener(_rafraichir);
  }

  @override
  void dispose() {
    DataRefreshBus.instance.removeListener(_rafraichir);
    _refController.dispose();
    _quantiteController.dispose();
    _prixController.dispose();
    _clientController.dispose();
    super.dispose();
  }

  Future<_DonneesCaisse> _charger() async {
    final (articles, magasins, clients, devise) = await (
      _catalogue.listerArticles(),
      _magasinsRepo.getAllStores(),
      _tiers.listerClients(),
      _parametres.devise(),
    ).wait;
    return _DonneesCaisse(
      articles: articles,
      magasins: magasins,
      clients: clients,
      devise: devise,
    );
  }

  Future<void> _rafraichir() async {
    final donnees = await _charger();
    if (!mounted) return;
    setState(() {
      _future = Future.value(donnees);
    });
  }

  /// Relit le disponible du magasin choisi.
  ///
  /// Il change sous les doigts du caissier — une autre caisse, une
  /// livraison — donc il se relit à chaque changement d'article ou de
  /// magasin plutôt que de se déduire d'une liste chargée au départ.
  Future<void> _relireDisponible() async {
    final article = _article;
    final magasin = _magasinId;
    if (article == null || magasin == null) {
      setState(() => _disponible = null);
      return;
    }
    final solde = await _stock.solde(
      reference: article.product.reference,
      magasinId: magasin,
    );
    if (!mounted) return;
    setState(() => _disponible = solde);
  }

  void _choisirArticle(ProductOverview article, Devise devise) {
    setState(() {
      _article = article;
      // Prérempli, pas imposé : la ligne porte ce qui est réellement
      // pratiqué, et le champ reste vide quand la fiche n'a pas de prix.
      final prix = article.product.prixVenteUnites;
      _prixController.text =
          prix == null ? '' : Montant(prix, devise: devise).formate(avecSymbole: false);
      _erreur = null;
    });
    _relireDisponible();
  }

  void _ajouterAuPanier(Devise devise) {
    final article = _article;
    if (article == null) {
      setState(() => _erreur = 'Choisissez un article.');
      return;
    }
    final quantite = int.tryParse(_quantiteController.text.trim()) ?? 0;
    if (quantite <= 0) {
      setState(() => _erreur = 'La quantité doit être supérieure à 0.');
      return;
    }
    final prix = Montant.depuisSaisie(_prixController.text, devise: devise);
    if (prix == null) {
      // Exigé ici et non au service : une vente sans prix rendrait le
      // chiffre d'affaires inconnaissable, et l'article n'a pas
      // forcément de tarif au catalogue.
      setState(() => _erreur =
          'Saisissez un prix : cet article n\'en a pas au catalogue.');
      return;
    }
    if (prix.estNegatif) {
      setState(() => _erreur = 'Le prix ne peut pas être négatif.');
      return;
    }

    final reference = article.product.reference;
    final deja = _panier.indexWhere(
      (l) => l.reference == reference && l.prixUnitaire == prix,
    );
    setState(() {
      if (deja >= 0) {
        // Même article au même prix : on cumule. Au même article vendu à
        // deux prix différents on laisse deux lignes, parce que c'est ce
        // qui s'est passé.
        final ancienne = _panier[deja];
        _panier[deja] = LigneVente(
          reference: reference,
          designation: ancienne.designation,
          quantite: ancienne.quantite + quantite,
          prixUnitaire: prix,
        );
      } else {
        _panier.add(LigneVente(
          reference: reference,
          designation: article.product.designation,
          quantite: quantite,
          prixUnitaire: prix,
        ));
      }
      _refController.clear();
      _quantiteController.text = '1';
      _prixController.clear();
      _article = null;
      _disponible = null;
      _erreur = null;
    });
  }

  Montant _total(Devise devise) {
    var somme = Montant(0, devise: devise);
    for (final ligne in _panier) {
      somme = somme + ligne.total;
    }
    return somme;
  }

  Future<void> _encaisser() async {
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      final resultat = await _caisse.encaisser(
        magasinId: _magasinId!,
        lignes: List.of(_panier),
        tiersId: _clientId,
        client: _clientController.text.trim().isEmpty
            ? null
            : _clientController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _panier.clear();
        _clientController.clear();
        _clientId = null;
        _enCours = false;
      });
      DataRefreshBus.instance.notifyChanged();
      await _rafraichir();
      if (!mounted) return;
      _annoncer(resultat);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = messagePour(e, operation: "l'encaissement");
        _enCours = false;
      });
    }
  }

  void _annoncer(ResultatVente resultat) {
    final base = 'Ticket ${resultat.numeroTicket} — ${resultat.total.formate()}';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: resultat.aDesNegatifs ? AppColors.anomaly : null,
        duration: Duration(seconds: resultat.aDesNegatifs ? 8 : 4),
        content: Text(
          resultat.aDesNegatifs
              ? '$base. Stock négatif : ${resultat.negatifs.join(' ')}'
              : base,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final taille = context.windowSize;
    return Column(
      children: [
        const PageHeader(
          title: 'Caisse',
          subtitle: 'Encaisser au comptoir',
        ),
        Expanded(
          child: FutureBuilder<_DonneesCaisse>(
            future: _future,
            builder: (context, snapshot) {
              final padding = AppSpacing.pagePadding(taille);
              if (snapshot.connectionState != ConnectionState.done) {
                return Padding(padding: padding, child: const SkeletonList());
              }
              if (snapshot.hasError) {
                return AppErrorState(
                  message: messagePour(snapshot.error!,
                      operation: 'le chargement de la caisse'),
                  onRetry: _rafraichir,
                );
              }
              final donnees = snapshot.data!;
              return SingleChildScrollView(
                padding: padding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _formulaire(donnees),
                    const SizedBox(height: AppSpacing.lg),
                    _ticket(donnees),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _formulaire(_DonneesCaisse donnees) {
    return SectionCard(
      icon: Icons.point_of_sale_outlined,
      title: 'ARTICLE',
      children: [
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          crossAxisAlignment: WrapCrossAlignment.start,
          children: [
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<int>(
                initialValue: _magasinId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Point de vente *'),
                items: [
                  for (final m in donnees.magasins)
                    DropdownMenuItem(value: m.id, child: Text(m.name)),
                ],
                onChanged: (v) {
                  setState(() => _magasinId = v);
                  _relireDisponible();
                },
              ),
            ),
            SizedBox(
              width: 300,
              child: ProductAutocomplete(
                products: donnees.articles,
                controller: _refController,
                labelText: 'Article *',
                onSelected: (a) => _choisirArticle(a, donnees.devise),
              ),
            ),
            SizedBox(
              width: 120,
              child: TextField(
                controller: _quantiteController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Quantité *'),
              ),
            ),
            SizedBox(
              width: 160,
              child: TextField(
                controller: _prixController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Prix unitaire *',
                  suffixText: donnees.devise.symbole,
                  helperText: _article?.product.prixVenteUnites == null
                      ? 'Aucun tarif au catalogue'
                      : 'Tarif catalogue, modifiable',
                ),
              ),
            ),
            SizedBox(
              width: 130,
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'En stock'),
                child: Text(
                  _disponible?.toString() ?? '—',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _disponible == null
                        ? AppColors.textSecondary
                        : StockStatus.pour(
                            _disponible!,
                            seuil: _article?.stockMin ??
                                StockStatus.seuilParDefaut,
                          ).color,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: ElevatedButton.icon(
                onPressed: () => _ajouterAuPanier(donnees.devise),
                icon: const Icon(Icons.add_shopping_cart, size: 18),
                label: const Text('Ajouter'),
              ),
            ),
          ],
        ),
        if (_erreur != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(_erreur!,
              style: const TextStyle(color: AppColors.error, fontSize: 12)),
        ],
      ],
    );
  }

  Widget _ticket(_DonneesCaisse donnees) {
    final pret = _magasinId != null && _panier.isNotEmpty && !_enCours;
    return SectionCard(
      icon: Icons.receipt_long_outlined,
      title: 'TICKET',
      children: [
        if (_panier.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Text(
              'Panier vide. Choisissez le point de vente, puis ajoutez les '
              'articles. Rien n\'est encaissé avant la validation.',
              style: AppTextStyles.bodyMuted,
            ),
          )
        else ...[
          AdaptiveTable(
            actionsColumn: 4,
            titleColumn: 1,
            subtitleColumn: 0,
            minTableWidth: 560,
            columns: const [
              AppColumn('RÉFÉRENCE', flex: 18),
              AppColumn('DÉSIGNATION', flex: 32),
              AppColumn.number('QTÉ', flex: 10),
              AppColumn.number('PRIX', flex: 16),
              AppColumn.number('TOTAL', flex: 16),
              AppColumn.actions(flex: 10),
            ],
            rows: [
              for (final ligne in _panier)
                AppRow(
                  cells: [
                    Cells.identifier(ligne.reference),
                    Cells.text(ligne.designation),
                    Cells.number(ligne.quantite),
                    Cells.text(
                      ligne.prixUnitaire.formate(avecSymbole: false),
                      style: AppTextStyles.numeric,
                    ),
                    Cells.text(
                      ligne.total.formate(avecSymbole: false),
                      style: AppTextStyles.numericStrong,
                    ),
                    RowActions(
                      actions: [
                        RowAction(
                          icon: Icons.delete_outline,
                          tooltip: 'Retirer du ticket',
                          destructive: true,
                          onPressed: () =>
                              setState(() => _panier.remove(ligne)),
                        ),
                      ],
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 260,
                child: TiersAutocomplete(
                  tiers: donnees.clients,
                  controller: _clientController,
                  labelText: 'Client (facultatif)',
                  hintText: 'Passant, ou une fiche',
                  onTiersChoisi: (t) => setState(() => _clientId = t.id),
                  onChoixAbandonne: () {
                    if (_clientId != null) setState(() => _clientId = null);
                  },
                ),
              ),
              _Total(montant: _total(donnees.devise)),
              TextButton(
                onPressed: _enCours ? null : () => setState(_panier.clear),
                child: const Text('Vider'),
              ),
              FilledButton.icon(
                onPressed: pret ? _encaisser : null,
                icon: _enCours
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check, size: 18),
                label: const Text('Encaisser'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Le total, assez gros pour se lire d'un coup d'œil au comptoir.
class _Total extends StatelessWidget {
  final Montant montant;

  const _Total({required this.montant});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.accentLight.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.accentLight.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('TOTAL', style: AppTextStyles.sectionLabel),
          const SizedBox(width: AppSpacing.md),
          Text(
            montant.formate(),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.accentLight,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
