import 'dart:async';
import 'dart:io';

import 'package:excel/excel.dart' hide Border, BorderStyle;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models/product_stock.dart';
import '../data/models/store.dart';
import '../data/models/view_models.dart';
import '../data/repositories/product_repository.dart';
import '../data/repositories/store_repository.dart';
import '../services/data_refresh_bus.dart';
import '../services/excel/stock_import_service.dart';
import '../theme/app_breakpoints.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../widgets/adaptive_table.dart';
import '../widgets/dialog_body.dart';
import '../widgets/empty_state.dart';
import '../widgets/page_header.dart';
import '../widgets/row_actions.dart';
import '../widgets/skeleton.dart';
import '../widgets/status_badge.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsData {
  final List<ProductOverview> products;
  final List<Store> stores;

  const _ProductsData({required this.products, required this.stores});
}

class _ProductsScreenState extends State<ProductsScreen> {
  final _productRepo = ProductRepository();
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
      final products = await _productRepo.getProductOverviews(search: _search);
      final stores = await _storeRepo.getAllStores();
      if (!mounted) return;
      setState(() {
        _data = _ProductsData(products: products, stores: stores);
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
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
          content: Text('Erreur import : $e'),
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
      builder: (context) => _ProductFormDialog(stores: data.stores),
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
      builder: (context) => _ProductFormDialog(stores: data.stores, existing: overview, existingStocks: stocks),
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
        child: _table(data.products),
      ),
    );
  }

  Widget _table(List<ProductOverview> rows) {
    return AdaptiveTable(
      actionsColumn: 6,
      columns: const [
        AppColumn('RÉFÉRENCE', flex: 11),
        AppColumn('DÉSIGNATION', flex: 20),
        AppColumn('UNITÉ', flex: 7),
        AppColumn('MAGASINS', flex: 13),
        AppColumn.number('STOCK INITIAL', flex: 10),
        AppColumn.number('STOCK ACTUEL', flex: 10),
        AppColumn.actions(flex: 11),
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
            accent: overview.status == StockStatus.rupture
                ? AppColors.error
                : null,
            cells: [
              Cells.identifier(overview.product.reference),
              Cells.text(overview.product.designation),
              Cells.muted(overview.product.unit),
              overview.storeNames.isEmpty
                  ? Cells.blank
                  : Cells.muted(overview.storeNames),
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

  const _ProductFormDialog({required this.stores, this.existing, this.existingStocks = const []});

  @override
  State<_ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends State<_ProductFormDialog> {
  final _productRepo = ProductRepository();
  late final TextEditingController _refController;
  late final TextEditingController _desController;
  late final TextEditingController _unitController;
  late final TextEditingController _initialController;
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
        await _productRepo.updateProduct(
          existing.product.copyWith(reference: ref, designation: des, unit: unit),
        );
        for (final row in _rows) {
          final value = int.tryParse(row.controller.text.trim()) ?? 0;
          if (row.original != null) {
            await _productRepo.updateProductStock(row.original!.id, storeId: row.storeId!, initialStock: value);
          } else {
            await _productRepo.upsertProductStock(productId: existing.product.id, storeId: row.storeId!, initialStock: value);
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
          if (await _productRepo.productStockExists(productId, _storeId!)) {
            final storeName = widget.stores.firstWhere((s) => s.id == _storeId!).name;
            setState(() {
              _error = 'Le produit « $ref » a déjà un stock dans le magasin $storeName.';
              _saving = false;
            });
            return;
          }
        } else {
          productId = await _productRepo.createProduct(reference: ref, designation: des, unit: unit);
        }
        await _productRepo.upsertProductStock(productId: productId, storeId: _storeId!, initialStock: initial);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _error = 'Erreur : $e';
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
