import 'dart:async';
import 'dart:io';

import 'package:excel/excel.dart' hide Border, BorderStyle;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:socogen/modules/stock/models/product_stock.dart';
import 'package:socogen/modules/stock/models/store.dart';
import 'package:socogen/shared/models/view_models.dart';
import 'package:socogen/core/money/montant.dart';
import 'package:socogen/modules/catalogue/models/famille.dart';
import 'package:socogen/modules/catalogue/services/catalogue_service.dart';
import 'package:socogen/shared/models/taux_tva.dart';
import 'package:socogen/modules/parametres/services/parametres_service.dart';
import 'package:socogen/modules/catalogue/repositories/product_repository.dart';
import 'package:socogen/modules/stock/services/stock_service.dart';
import 'package:socogen/modules/stock/repositories/store_repository.dart';
import 'package:socogen/core/events/data_refresh_bus.dart';
import 'package:socogen/modules/stock/services/stock_import_service.dart';
import 'package:socogen/shared/ui/theme/app_breakpoints.dart';
import 'package:socogen/shared/ui/theme/app_colors.dart';
import 'package:socogen/shared/ui/theme/app_spacing.dart';
import 'package:socogen/shared/ui/theme/app_text_styles.dart';
import 'package:socogen/shared/ui/widgets/adaptive_table.dart';
import 'package:socogen/shared/ui/widgets/dialog_body.dart';
import 'package:socogen/shared/ui/widgets/empty_state.dart';
import 'package:socogen/shared/ui/widgets/page_header.dart';
import 'package:socogen/shared/ui/widgets/row_actions.dart';
import 'package:socogen/shared/ui/widgets/skeleton.dart';
import 'package:socogen/shared/ui/widgets/status_badge.dart';
import 'package:socogen/core/errors/messages.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsData {
  final List<ProductOverview> products;
  final List<Store> stores;

  /// Chargés une fois pour l'écran entier : la devise sert à formater
  /// chaque ligne, les taux et les familles à remplir les listes du
  /// formulaire. Les relire par article ferait une requête par ligne.
  final Devise devise;
  final List<TauxTva> tauxTva;
  final List<Famille> familles;

  /// Le seuil d'alerte de l'entreprise, affiché au formulaire pour dire
  /// ce qui s'appliquera si le champ de l'article reste vide.
  final int seuilParDefaut;

  const _ProductsData({
    required this.products,
    required this.stores,
    required this.devise,
    required this.tauxTva,
    required this.familles,
    required this.seuilParDefaut,
  });
}

class _ProductsScreenState extends State<ProductsScreen> {
  final _productRepo = ProductRepository();
  final _catalogue = CatalogueService();
  final _parametres = ParametresService();
  final _storeRepo = StoreRepository();
  final _searchController = TextEditingController();

  _ProductsData? _data;
  String? _error;
  String _search = '';
  Timer? _searchDebounce;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _load();
    DataRefreshBus.instance.addListener(_refresh);
  }

  @override
  void dispose() {
    DataRefreshBus.instance.removeListener(_refresh);
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// Refreshes this screen and signals every other screen to reload its
  /// own data (e.g. product/store lists used elsewhere need updating).
  void _onChanged() {
    _refresh();
    DataRefreshBus.instance.notifyChanged();
  }

  Future<void> _load() async {
    try {
      final (products, stores, devise, taux, familles, seuil) = await (
        _productRepo.getProductOverviews(search: _search),
        _storeRepo.getAllStores(),
        _parametres.devise(),
        _parametres.tauxTva(),
        _catalogue.listerFamilles(),
        _parametres.seuilStockParDefaut(),
      ).wait;
      if (!mounted) return;
      setState(() {
        _data = _ProductsData(
          products: products,
          stores: stores,
          devise: devise,
          tauxTva: taux,
          familles: familles,
          seuilParDefaut: seuil,
        );
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = messagePour(e, operation: 'le chargement des produits'));
    }
  }

  Future<void> _refresh() => _load();

  void _onSearchChanged(String value) {
    setState(() => _search = value);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), _load);
  }

  void _clearSearch() {
    _searchController.clear();
    _onSearchChanged('');
  }

  /// Imports a Sage-style export workbook: the catalogue with its opening
  /// stock per store, plus the movement sheets. Sheets are routed by name
  /// (*Produits*, *Entrées*, *Sorties*); a workbook matching none of those
  /// is read as a catalogue, as it was before movements were supported.
  Future<void> _importProducts() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls', 'xlsm'],
    );
    final path = result?.files.single.path;
    if (path == null) return;

    setState(() => _importing = true);
    try {
      final bytes = await File(path).readAsBytes();
      final report =
          await StockImportService().importWorkbook(Excel.decodeBytes(bytes));

      await _load();
      DataRefreshBus.instance.notifyChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(report.summary),
          action: report.problems.isEmpty
              ? null
              : SnackBarAction(
                  label: 'Détails',
                  onPressed: () => _showImportProblems(report),
                ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(messagePour(e, operation: "l'import")),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  /// Lists what the import refused, so an unreadable date, an unknown
  /// magasin or a sheet read under the wrong role is something you can go
  /// and fix rather than a silent gap in the stock. The sheets that were
  /// read come first: most surprises turn out to be a sheet the import
  /// never opened at all.
  Future<void> _showImportProblems(ImportReport report) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Détails de l\'import'),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: [
              const Text('Feuilles lues', style: AppTextStyles.sectionLabel),
              for (final sheet in report.sheetsRead)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(sheet, style: AppTextStyles.bodyMuted),
                ),
              const SizedBox(height: AppSpacing.md),
              const Text('Lignes ignorées', style: AppTextStyles.sectionLabel),
              for (final problem in report.problems.take(50))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(problem, style: AppTextStyles.bodyMuted),
                ),
              if (report.problems.length > 50)
                Text(
                  '… et ${report.problems.length - 50} autre(s).',
                  style: AppTextStyles.bodyMuted,
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  Future<void> _openAddDialog() async {
    final data = _data;
    if (data == null) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _ProductFormDialog(
        stores: data.stores,
        devise: data.devise,
        tauxTva: data.tauxTva,
        familles: data.familles,
        seuilParDefaut: data.seuilParDefaut,
      ),
    );
    if (saved == true) _onChanged();
  }

  Future<void> _openEditDialog(ProductOverview overview) async {
    final data = _data;
    if (data == null) return;
    final stocks = await _productRepo.getProductStocks(overview.product.id);
    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _ProductFormDialog(
        stores: data.stores,
        devise: data.devise,
        tauxTva: data.tauxTva,
        familles: data.familles,
        seuilParDefaut: data.seuilParDefaut,
        existing: overview,
        existingStocks: stocks,
      ),
    );
    if (saved == true) _onChanged();
  }

  Future<void> _deleteProduct(ProductOverview overview) async {
    final hasMovements = await _productRepo.hasMovements(overview.product.reference);
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer le produit'),
        content: Text(
          hasMovements
              ? 'Le produit « ${overview.product.reference} » possède des mouvements de stock '
                  '(entrées/sorties). Ces mouvements seront conservés, mais le produit sera '
                  'supprimé du catalogue. Continuer ?'
              : 'Voulez-vous vraiment supprimer le produit « ${overview.product.reference} » ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _productRepo.deleteProduct(overview.product.id);
    _onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final size = context.windowSize;
    final gutter = AppSpacing.pageGutter(size);
    final data = _data;

    return Column(
      children: [
        PageHeader(
          title: 'Produits',
          subtitle: 'Gérer le catalogue de produits',
          actions: [
            OutlinedButton.icon(
              onPressed: data == null || _importing ? null : _importProducts,
              icon: _importing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file_outlined, size: 18),
              label: const Text('Importer Excel'),
            ),
            const SizedBox(width: AppSpacing.sm),
            ElevatedButton.icon(
              onPressed: data == null ? null : _openAddDialog,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Nouveau produit'),
            ),
          ],
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            gutter,
            AppSpacing.md,
            gutter,
            AppSpacing.md,
          ),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search, size: 20),
              hintText: 'Rechercher par référence ou désignation…',
              suffixIcon: _search.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Effacer',
                      onPressed: _clearSearch,
                    ),
            ),
            onChanged: _onSearchChanged,
          ),
        ),
        Expanded(child: _buildBody(gutter)),
      ],
    );
  }

  Widget _buildBody(double gutter) {
    if (_error != null) {
      return AppErrorState(message: _error!, onRetry: _refresh);
    }

    final data = _data;
    if (data == null) {
      return Padding(
        padding: EdgeInsets.fromLTRB(gutter, 0, gutter, gutter),
        child: const SkeletonList(),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppColors.accentLight,
      backgroundColor: AppColors.surface,
      child: Padding(
        padding: EdgeInsets.fromLTRB(gutter, 0, gutter, gutter),
        child: _table(data.products, data.devise),
      ),
    );
  }

  /// Le prix tel qu'il se lit dans une colonne.
  ///
  /// Null n'est pas zéro : un tiret dit « pas encore tarifé », un
  /// « 0 FCFA » dirait « gratuit ». Les 723 articles hérités sont dans
  /// le premier cas, et la nuance décide de ce qui est vendable.
  static Widget _cellulePrix(int? unites, Devise devise) {
    if (unites == null) {
      return const Text(
        '—',
        textAlign: TextAlign.right,
        style: TextStyle(color: AppColors.textMuted),
      );
    }
    return Text(
      Montant(unites, devise: devise).formate(),
      textAlign: TextAlign.right,
      style: AppTextStyles.numeric,
    );
  }

  Widget _table(List<ProductOverview> rows, Devise devise) {
    return AdaptiveTable(
      actionsColumn: 7,
      columns: const [
        AppColumn('RÉFÉRENCE', flex: 11),
        AppColumn('DÉSIGNATION', flex: 19),
        AppColumn('UNITÉ', flex: 6),
        AppColumn('MAGASINS', flex: 12),
        AppColumn.number('PRIX DE VENTE', flex: 11),
        AppColumn.number('STOCK INITIAL', flex: 9),
        AppColumn.number('STOCK ACTUEL', flex: 9),
        AppColumn.actions(flex: 10),
      ],
      empty: AppEmptyState(
        icon: _search.isEmpty
            ? Icons.inventory_2_outlined
            : Icons.search_off_outlined,
        title: _search.isEmpty ? 'Aucun produit' : 'Aucun résultat',
        message: _search.isEmpty
            ? 'Créez votre premier produit ou importez un catalogue Excel.'
            : 'Aucun produit ne correspond à « $_search ».',
        action: _search.isEmpty
            ? ElevatedButton.icon(
                onPressed: _openAddDialog,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nouveau produit'),
              )
            : OutlinedButton.icon(
                onPressed: _clearSearch,
                icon: const Icon(Icons.close, size: 16),
                label: const Text('Effacer la recherche'),
              ),
      ),
      rows: [
        for (final overview in rows)
          AppRow(
            onTap: () => _openEditDialog(overview),
            accent: overview.status.isDepleted ? overview.status.color : null,
            cells: [
              Cells.identifier(overview.product.reference),
              Cells.text(overview.product.designation),
              Cells.muted(overview.product.unit),
              overview.storeNames.isEmpty
                  ? Cells.blank
                  : Cells.muted(overview.storeNames),
              // Un article sans prix affiche un tiret, pas « 0 FCFA » :
              // il n'est pas gratuit, il n'est pas encore tarifé.
              _cellulePrix(overview.product.prixVenteUnites, devise),
              Cells.number(
                overview.initialStock,
                color: AppColors.textSecondary,
              ),
              Cells.number(
                overview.currentStock,
                color: overview.status.color,
                strong: true,
                size: 14,
              ),
              RowActions(
                actions: [
                  RowAction(
                    icon: Icons.edit_outlined,
                    tooltip: 'Modifier',
                    onPressed: () => _openEditDialog(overview),
                  ),
                  RowAction(
                    icon: Icons.delete_outline,
                    tooltip: 'Supprimer',
                    destructive: true,
                    onPressed: () => _deleteProduct(overview),
                  ),
                ],
              ),
            ],
          ),
      ],
    );
  }
}

/// One editable (magasin, stock initial) row in the edit dialog.
/// [original] is null for a newly-added row (no `product_stocks` id yet).
class _StockRowEdit {
  ProductStock? original;
  int? storeId;
  final TextEditingController controller;

  _StockRowEdit({this.original, this.storeId, String initial = '0'}) : controller = TextEditingController(text: initial);
}

class _ProductFormDialog extends StatefulWidget {
  final List<Store> stores;
  final ProductOverview? existing;
  final List<({ProductStock stock, String storeName})> existingStocks;
  final Devise devise;
  final List<TauxTva> tauxTva;
  final List<Famille> familles;
  final int seuilParDefaut;

  const _ProductFormDialog({
    required this.stores,
    required this.devise,
    required this.tauxTva,
    required this.familles,
    required this.seuilParDefaut,
    this.existing,
    this.existingStocks = const [],
  });

  @override
  State<_ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends State<_ProductFormDialog> {
  final _productRepo = ProductRepository();
  final _stock = StockService();
  late final TextEditingController _refController;
  late final TextEditingController _desController;
  late final TextEditingController _unitController;
  late final TextEditingController _initialController;
  late final TextEditingController _prixVenteController;
  late final TextEditingController _prixAchatController;
  late final TextEditingController _codeBarreController;
  late final TextEditingController _seuilController;
  int? _tvaId;
  int? _familleId;
  int? _storeId;
  late List<_StockRowEdit> _rows;
  final List<int> _removedStockIds = [];
  String? _error;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _refController = TextEditingController(text: existing?.product.reference ?? '');
    _desController = TextEditingController(text: existing?.product.designation ?? '');
    _unitController = TextEditingController(text: existing?.product.unit ?? 'unité');
    _initialController = TextEditingController(text: '${existing?.firstStoreInitialStock ?? 0}');

    // Une case vide veut dire « pas de prix ». Y mettre 0 par défaut
    // transformerait chaque article non tarifé en article gratuit au
    // premier enregistrement.
    final article = existing?.product;
    _prixVenteController = TextEditingController(
      text: article?.prixVenteUnites == null
          ? ''
          : Montant(article!.prixVenteUnites!, devise: widget.devise)
              .formate(avecSymbole: false),
    );
    _prixAchatController = TextEditingController(
      text: article?.prixAchatUnites == null
          ? ''
          : Montant(article!.prixAchatUnites!, devise: widget.devise)
              .formate(avecSymbole: false),
    );
    _codeBarreController = TextEditingController(text: article?.codeBarre ?? '');
    // Vide quand l'article n'a pas de seuil à lui : le champ dit alors
    // par son texte d'aide lequel s'applique.
    _seuilController =
        TextEditingController(text: article?.stockMin?.toString() ?? '');
    _tvaId = article?.tvaId ??
        (widget.tauxTva.where((t) => t.estDefaut).firstOrNull)?.id;
    _familleId = article?.familleId;
    _storeId = existing?.firstStoreId ?? (widget.stores.isNotEmpty ? widget.stores.first.id : null);

    _rows = widget.existingStocks
        .map((e) => _StockRowEdit(original: e.stock, storeId: e.stock.storeId, initial: '${e.stock.initialStock}'))
        .toList();
    if (_isEdit && _rows.isEmpty) {
      _rows.add(_StockRowEdit(storeId: widget.stores.isNotEmpty ? widget.stores.first.id : null));
    }
  }

  @override
  void dispose() {
    _refController.dispose();
    _desController.dispose();
    _unitController.dispose();
    _initialController.dispose();
    _prixVenteController.dispose();
    _prixAchatController.dispose();
    _codeBarreController.dispose();
    _seuilController.dispose();
    for (final row in _rows) {
      row.controller.dispose();
    }
    super.dispose();
  }

  void _addStockRow() {
    final usedIds = _rows.map((r) => r.storeId).toSet();
    final available = widget.stores.where((s) => !usedIds.contains(s.id)).toList();
    final defaultStoreId = available.isNotEmpty
        ? available.first.id
        : (widget.stores.isNotEmpty ? widget.stores.first.id : null);
    setState(() => _rows.add(_StockRowEdit(storeId: defaultStoreId)));
  }

  void _removeStockRow(_StockRowEdit row) {
    setState(() {
      if (row.original != null) _removedStockIds.add(row.original!.id);
      row.controller.dispose();
      _rows.remove(row);
    });
  }

  /// Le seuil saisi : null si le champ est vide — l'article retombe
  /// alors sur celui de l'entreprise. Rend `(null, erreur)` si la
  /// saisie n'est pas un entier positif.
  (int?, String?) _lireSeuil() {
    final texte = _seuilController.text.trim();
    if (texte.isEmpty) return (null, null);
    final valeur = int.tryParse(texte);
    if (valeur == null) {
      return (null, "Le seuil d'alerte doit être un nombre entier.");
    }
    if (valeur < 0) {
      return (null, "Un seuil d'alerte ne peut pas être négatif.");
    }
    return (valeur, null);
  }

  Future<void> _save() async {
    final ref = _refController.text.trim();
    final des = _desController.text.trim();
    final unit = _unitController.text.trim().isEmpty ? 'unité' : _unitController.text.trim();

    if (ref.isEmpty) {
      setState(() => _error = 'La référence est obligatoire.');
      return;
    }
    if (des.isEmpty) {
      setState(() => _error = 'La désignation est obligatoire.');
      return;
    }

    final (seuil, erreurSeuil) = _lireSeuil();
    if (erreurSeuil != null) {
      setState(() => _error = erreurSeuil);
      return;
    }

    if (_isEdit) {
      final seenStoreIds = <int>{};
      for (final row in _rows) {
        if (row.storeId == null) {
          setState(() => _error = 'Sélectionnez un magasin pour chaque ligne de stock.');
          return;
        }
        if (!seenStoreIds.add(row.storeId!)) {
          setState(() => _error = 'Un même magasin est sélectionné plusieurs fois.');
          return;
        }
      }
    } else if (_storeId == null) {
      setState(() => _error = 'Sélectionnez un magasin.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      if (_isEdit) {
        final existing = widget.existing!;
        final exists = await _productRepo.referenceExists(ref, excludeId: existing.product.id);
        if (exists) {
          setState(() {
            _error = 'La référence « $ref » existe déjà.';
            _saving = false;
          });
          return;
        }
        final prixVente =
            Montant.depuisSaisie(_prixVenteController.text, devise: widget.devise);
        final prixAchat =
            Montant.depuisSaisie(_prixAchatController.text, devise: widget.devise);
        final codeBarre = _codeBarreController.text.trim();
        await _productRepo.updateProduct(
          existing.product.copyWith(
            reference: ref,
            designation: des,
            unit: unit,
            // Une case vidée retire le prix ; sans ces drapeaux, null
            // voudrait dire « ne change rien » et le prix resterait.
            prixVenteUnites: prixVente?.unites,
            effacerPrixVente: prixVente == null,
            prixAchatUnites: prixAchat?.unites,
            effacerPrixAchat: prixAchat == null,
            tvaId: _tvaId,
            effacerTva: _tvaId == null,
            familleId: _familleId,
            effacerFamille: _familleId == null,
            codeBarre: codeBarre.isEmpty ? null : codeBarre,
            effacerCodeBarre: codeBarre.isEmpty,
            // Champ vidé : l'article n'a plus de seuil à lui et repasse
            // sous celui de l'entreprise. Sans le drapeau, null voudrait
            // dire « ne change rien » et l'ancien seuil resterait.
            stockMin: seuil,
            effacerStockMin: seuil == null,
          ),
        );
        for (final row in _rows) {
          final value = int.tryParse(row.controller.text.trim()) ?? 0;
          if (row.original != null) {
            await _productRepo.updateProductStock(row.original!.id, storeId: row.storeId!, initialStock: value);
          } else {
            await _stock.definirStockOuverture(
                articleId: existing.product.id, magasinId: row.storeId!, quantite: value);
          }
        }
        for (final id in _removedStockIds) {
          await _productRepo.deleteProductStock(id);
        }
      } else {
        final initial = int.tryParse(_initialController.text.trim()) ?? 0;
        // Une référence existante peut être ajoutée dans un autre magasin :
        // on réutilise le produit et on crée juste une nouvelle ligne de
        // stock, sauf si ce produit a déjà un stock dans ce magasin précis.
        final existingProduct = await _productRepo.getByReference(ref);
        int productId;
        if (existingProduct != null) {
          productId = existingProduct.id;
          if (await _stock.ligneDeStockExiste(
              articleId: productId, magasinId: _storeId!)) {
            final storeName = widget.stores.firstWhere((s) => s.id == _storeId!).name;
            setState(() {
              _error = 'Le produit « $ref » a déjà un stock dans le magasin $storeName.';
              _saving = false;
            });
            return;
          }
        } else {
          final codeBarre = _codeBarreController.text.trim();
          productId = await _productRepo.createProduct(
            reference: ref,
            designation: des,
            unit: unit,
            familleId: _familleId,
            tvaId: _tvaId,
            prixVenteUnites: Montant.depuisSaisie(
              _prixVenteController.text,
              devise: widget.devise,
            )?.unites,
            prixAchatUnites: Montant.depuisSaisie(
              _prixAchatController.text,
              devise: widget.devise,
            )?.unites,
            codeBarre: codeBarre.isEmpty ? null : codeBarre,
            stockMin: seuil,
          );
        }
        await _stock.definirStockOuverture(
            articleId: productId, magasinId: _storeId!, quantite: initial);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _error = messagePour(e, operation: "l'enregistrement de l'article");
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Modifier le produit' : 'Nouveau produit'),
      content: DialogBody(
        maxWidth: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _refController,
              decoration: const InputDecoration(labelText: 'Référence *', hintText: 'REF-001'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _desController,
              decoration: const InputDecoration(labelText: 'Désignation *', hintText: 'Ex : Ciment Portland'),
            ),
            const SizedBox(height: 16),
            const Text('Tarif', style: AppTextStyles.sectionLabel),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _prixVenteController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Prix de vente',
                      suffixText: widget.devise.symbole,
                      // Laisser vide se lit, et se dit.
                      hintText: 'Laisser vide si inconnu',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _prixAchatController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: "Prix d'achat",
                      suffixText: widget.devise.symbole,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              initialValue: _tvaId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'TVA'),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('Aucune'),
                ),
                for (final taux in widget.tauxTva)
                  DropdownMenuItem<int?>(
                    value: taux.id,
                    child: Text(taux.libelle, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() => _tvaId = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              initialValue: _familleId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Famille'),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('Non classé'),
                ),
                for (final famille in widget.familles)
                  DropdownMenuItem<int?>(
                    value: famille.id,
                    child: Text(famille.nom, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() => _familleId = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _codeBarreController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Code-barres',
                hintText: 'Ex : 6161100000123',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _seuilController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: "Seuil d'alerte",
                // Le texte d'aide porte la distinction : vide n'est pas
                // zéro. Zéro veut dire « n'alerte jamais », et c'est une
                // décision qu'on doit pouvoir prendre.
                helperText: "Vide : celui de l'entreprise "
                    "(${widget.seuilParDefaut})",
                suffixText: 'en stock',
              ),
            ),
            const SizedBox(height: 12),
            if (_isEdit) ...[
              TextField(
                controller: _unitController,
                decoration: const InputDecoration(labelText: 'Unité', hintText: 'Ex : sac, kg, litre'),
              ),
              const SizedBox(height: 16),
              const Text('Stock par magasin', style: AppTextStyles.sectionLabel),
              const SizedBox(height: 8),
              for (final row in _rows)
                Padding(
                  key: ValueKey(row),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: row.storeId,
                          isExpanded: true,
                          isDense: true,
                          decoration: const InputDecoration(labelText: 'Magasin *'),
                          items: widget.stores
                              .map((s) => DropdownMenuItem(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis)))
                              .toList(),
                          onChanged: (value) => setState(() => row.storeId = value),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 100,
                        child: TextField(
                          controller: row.controller,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: const InputDecoration(labelText: 'Stock initial', isDense: true),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        color: AppColors.error,
                        tooltip: 'Retirer ce magasin',
                        onPressed: _rows.length > 1 ? () => _removeStockRow(row) : null,
                      ),
                    ],
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _rows.length >= widget.stores.length ? null : _addStockRow,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Ajouter un magasin'),
                ),
              ),
            ] else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _unitController,
                      decoration: const InputDecoration(labelText: 'Unité', hintText: 'Ex : sac, kg, litre'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _initialController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: 'Stock initial'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _storeId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Magasin *'),
                items: widget.stores
                    .map((s) => DropdownMenuItem(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: (value) => setState(() => _storeId = value),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_isEdit ? 'Enregistrer' : 'Ajouter'),
        ),
      ],
    );
  }
}
