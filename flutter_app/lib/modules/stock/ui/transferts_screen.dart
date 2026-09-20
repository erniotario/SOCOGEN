import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:socogen/core/errors/messages.dart';
import 'package:socogen/core/events/data_refresh_bus.dart';
import 'package:socogen/modules/catalogue/services/catalogue_service.dart';
import 'package:socogen/modules/stock/models/store.dart';
import 'package:socogen/modules/stock/repositories/store_repository.dart';
import 'package:socogen/modules/stock/services/stock_service.dart';
import 'package:socogen/modules/stock/services/transfert_service.dart';
import 'package:socogen/shared/models/transfert.dart';
import 'package:socogen/shared/models/view_models.dart';
import 'package:socogen/shared/ui/theme/app_breakpoints.dart';
import 'package:socogen/shared/ui/theme/app_colors.dart';
import 'package:socogen/shared/ui/theme/app_spacing.dart';
import 'package:socogen/shared/ui/theme/app_text_styles.dart';
import 'package:socogen/shared/ui/widgets/adaptive_table.dart';
import 'package:socogen/shared/ui/widgets/empty_state.dart';
import 'package:socogen/shared/ui/widgets/product_autocomplete.dart';
import 'package:socogen/shared/ui/widgets/page_header.dart';
import 'package:socogen/shared/ui/widgets/row_actions.dart';
import 'package:socogen/shared/ui/widgets/section_card.dart';
import 'package:socogen/shared/ui/widgets/skeleton.dart';
import 'package:socogen/shared/ui/widgets/status_badge.dart';

/// Déplacer des marchandises d'un magasin à l'autre.
///
/// L'écran a la forme de l'inventaire, et pour la même raison : on
/// compose un **brouillon** — plusieurs articles, parce qu'on charge une
/// camionnette et pas un article — et rien n'est écrit avant la
/// validation. Un transfert à moitié saisi ne doit pas exister en base.
class TransfertsScreen extends StatefulWidget {
  const TransfertsScreen({super.key});

  @override
  State<TransfertsScreen> createState() => _TransfertsScreenState();
}

class _Donnees {
  final List<ProductOverview> articles;
  final List<Store> magasins;
  final List<({Transfert transfert, String source, String destination, int lignes})>
      historique;

  const _Donnees({
    required this.articles,
    required this.magasins,
    required this.historique,
  });
}

class _TransfertsScreenState extends State<TransfertsScreen> {
  final _transferts = TransfertService();
  final _catalogue = CatalogueService();
  final _magasinsRepo = StoreRepository();
  final _stock = StockService();

  late Future<_Donnees> _future;

  int? _sourceId;
  int? _destinationId;
  final _brouillon = <LigneTransfert>[];

  final _refController = TextEditingController();
  final _quantiteController = TextEditingController(text: '1');
  ProductOverview? _articleChoisi;
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
    super.dispose();
  }

  Future<_Donnees> _charger() async {
    final (articles, magasins, historique) = await (
      _catalogue.listerArticles(),
      _magasinsRepo.getAllStores(),
      _transferts.lister(limite: 50),
    ).wait;
    return _Donnees(
      articles: articles,
      magasins: magasins,
      historique: historique,
    );
  }

  Future<void> _rafraichir() async {
    final donnees = await _charger();
    if (!mounted) return;
    setState(() {
      _future = Future.value(donnees);
    });
  }

  /// Le disponible dans le magasin d'origine, relu à chaque changement
  /// d'article ou de magasin : c'est ce qui dit si le transfert va
  /// creuser un négatif, et il change sous les pieds de l'opérateur.
  Future<void> _relireDisponible() async {
    final article = _articleChoisi;
    final source = _sourceId;
    if (article == null || source == null) {
      setState(() => _disponible = null);
      return;
    }
    final solde = await _stock.solde(
      reference: article.product.reference,
      magasinId: source,
    );
    if (!mounted) return;
    setState(() => _disponible = solde);
  }

  void _ajouterAuBrouillon() {
    final article = _articleChoisi;
    if (article == null) {
      setState(() => _erreur = 'Choisissez un article.');
      return;
    }
    final quantite = int.tryParse(_quantiteController.text.trim()) ?? 0;
    if (quantite <= 0) {
      setState(() => _erreur = 'La quantité doit être supérieure à 0.');
      return;
    }
    final deja = _brouillon
        .indexWhere((l) => l.reference == article.product.reference);
    setState(() {
      final ligne = LigneTransfert(
        reference: article.product.reference,
        designation: article.product.designation,
        // Le même article ajouté deux fois cumule plutôt que de créer
        // deux lignes : deux lignes pour un article se liraient comme
        // deux déplacements distincts.
        quantite: deja >= 0 ? _brouillon[deja].quantite + quantite : quantite,
      );
      if (deja >= 0) {
        _brouillon[deja] = ligne;
      } else {
        _brouillon.add(ligne);
      }
      _refController.clear();
      _quantiteController.text = '1';
      _articleChoisi = null;
      _disponible = null;
      _erreur = null;
    });
  }

  Future<void> _valider(List<Store> magasins) async {
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      final resultat = await _transferts.effectuer(
        sourceId: _sourceId!,
        destinationId: _destinationId!,
        lignes: List.of(_brouillon),
      );
      if (!mounted) return;
      setState(() {
        _brouillon.clear();
        _enCours = false;
      });
      DataRefreshBus.instance.notifyChanged();
      await _rafraichir();
      if (!mounted) return;
      _annoncer(resultat);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = messagePour(e, operation: "l'enregistrement du transfert");
        _enCours = false;
      });
    }
  }

  /// Dit ce qui s'est passé, et nomme les négatifs creusés.
  ///
  /// Le transfert a eu lieu — la politique est de prévenir, pas de
  /// refuser — mais un écart passé sous zéro ne doit pas se découvrir
  /// trois semaines plus tard dans Rapports.
  void _annoncer(ResultatTransfert resultat) {
    final lignes = resultat.lignesDeplacees;
    final base = '$lignes article${lignes > 1 ? 's' : ''} '
        'transféré${lignes > 1 ? 's' : ''}.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: resultat.aDesNegatifs ? AppColors.anomaly : null,
        duration: Duration(seconds: resultat.aDesNegatifs ? 8 : 4),
        content: Text(
          resultat.aDesNegatifs
              ? '$base Stock négatif : ${resultat.negatifs.join(' ')}'
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
          title: 'Transferts',
          subtitle: 'Déplacer du stock entre magasins',
        ),
        Expanded(
          child: FutureBuilder<_Donnees>(
            future: _future,
            builder: (context, snapshot) {
              final padding = AppSpacing.pagePadding(taille);
              if (snapshot.connectionState != ConnectionState.done) {
                return Padding(padding: padding, child: const SkeletonList());
              }
              if (snapshot.hasError) {
                return AppErrorState(
                  message: messagePour(snapshot.error!,
                      operation: 'le chargement des transferts'),
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
                    _brouillonEnCours(donnees.magasins),
                    const SizedBox(height: AppSpacing.lg),
                    _historique(donnees),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _formulaire(_Donnees donnees) {
    final magasins = donnees.magasins;
    return SectionCard(
      icon: Icons.swap_horiz,
      title: 'NOUVEAU TRANSFERT',
      children: [
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          crossAxisAlignment: WrapCrossAlignment.start,
          children: [
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<int>(
                initialValue: _sourceId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Depuis *'),
                items: [
                  for (final m in magasins)
                    DropdownMenuItem(value: m.id, child: Text(m.name)),
                ],
                onChanged: (v) {
                  setState(() => _sourceId = v);
                  _relireDisponible();
                },
              ),
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<int>(
                initialValue: _destinationId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Vers *'),
                items: [
                  for (final m in magasins)
                    // Le magasin d'origine ne se propose pas comme
                    // destination : un transfert vers soi-même n'en est
                    // pas un, et le service le refuse de toute façon.
                    if (m.id != _sourceId)
                      DropdownMenuItem(value: m.id, child: Text(m.name)),
                ],
                onChanged: (v) => setState(() => _destinationId = v),
              ),
            ),
            SizedBox(
              width: 300,
              child: ProductAutocomplete(
                products: donnees.articles,
                controller: _refController,
                labelText: 'Article *',
                onSelected: (article) {
                  setState(() => _articleChoisi = article);
                  _relireDisponible();
                },
              ),
            ),
            SizedBox(
              width: 140,
              child: TextField(
                controller: _quantiteController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Quantité *'),
              ),
            ),
            SizedBox(
              width: 150,
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Disponible'),
                child: Text(
                  _disponible?.toString() ?? '—',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _disponible == null
                        ? AppColors.textSecondary
                        : StockStatus.pour(
                            _disponible!,
                            seuil: _articleChoisi?.stockMin ??
                                StockStatus.seuilParDefaut,
                          ).color,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: ElevatedButton.icon(
                onPressed: _ajouterAuBrouillon,
                icon: const Icon(Icons.playlist_add, size: 18),
                label: const Text('Ajouter au transfert'),
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

  Widget _brouillonEnCours(List<Store> magasins) {
    final pret = _sourceId != null &&
        _destinationId != null &&
        _brouillon.isNotEmpty &&
        !_enCours;
    return SectionCard(
      icon: Icons.local_shipping_outlined,
      title: 'À TRANSFÉRER',
      children: [
        if (_brouillon.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Text(
              'Aucun article. Choisissez les deux magasins, puis ajoutez '
              'les articles à déplacer. Rien n\'est enregistré avant la '
              'validation.',
              style: AppTextStyles.bodyMuted,
            ),
          )
        else ...[
          AdaptiveTable(
            actionsColumn: 3,
            titleColumn: 1,
            subtitleColumn: 0,
            minTableWidth: 480,
            columns: const [
              AppColumn('RÉFÉRENCE', flex: 22),
              AppColumn('DÉSIGNATION', flex: 44),
              AppColumn.number('QUANTITÉ', flex: 20),
              AppColumn.actions(flex: 14),
            ],
            rows: [
              for (final ligne in _brouillon)
                AppRow(
                  cells: [
                    Cells.identifier(ligne.reference),
                    Cells.text(ligne.designation),
                    Cells.number(ligne.quantite, strong: true),
                    RowActions(
                      actions: [
                        RowAction(
                          icon: Icons.delete_outline,
                          tooltip: 'Retirer du transfert',
                          destructive: true,
                          onPressed: () =>
                              setState(() => _brouillon.remove(ligne)),
                        ),
                      ],
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed:
                    _enCours ? null : () => setState(_brouillon.clear),
                child: const Text('Vider'),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton.icon(
                onPressed: pret ? () => _valider(magasins) : null,
                icon: _enCours
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check, size: 18),
                label: const Text('Valider le transfert'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _historique(_Donnees donnees) {
    return SectionCard(
      icon: Icons.history,
      title: 'DERNIERS TRANSFERTS',
      children: [
        if (donnees.historique.isEmpty)
          const AppEmptyState(
            icon: Icons.swap_horiz,
            title: 'Aucun transfert',
            message: 'Les déplacements entre magasins apparaîtront ici.',
          )
        else
          AdaptiveTable(
            actionsColumn: null,
            titleColumn: 1,
            subtitleColumn: 0,
            minTableWidth: 520,
            columns: const [
              AppColumn('DATE', flex: 20),
              AppColumn('DEPUIS', flex: 28),
              AppColumn('VERS', flex: 28),
              AppColumn.number('ARTICLES', flex: 24),
            ],
            rows: [
              for (final t in donnees.historique)
                AppRow(
                  cells: [
                    Cells.muted(t.transfert.date),
                    Cells.text(t.source),
                    Cells.text(t.destination),
                    Cells.number(t.lignes),
                  ],
                ),
            ],
          ),
      ],
    );
  }
}
