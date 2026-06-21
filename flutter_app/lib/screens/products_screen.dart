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
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/page_header.dart';
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
    _search = value;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), _load);
  }

  /// Imports products from an Excel file (.xlsx/.xls/.xlsm), mirroring the
  /// PySide6 `_import_products` logic: maps header columns (référence,
  /// désignation, unité, stock initial, magasin), creates missing products,
  /// and skips product/magasin pairs that already have a stock row.
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
      final workbook = Excel.decodeBytes(bytes);
      if (workbook.tables.isEmpty) {
        throw Exception('Le fichier Excel est vide.');
      }
      final rows = workbook.tables[workbook.tables.keys.first]!.rows;
      if (rows.isEmpty) {
        throw Exception('Le fichier Excel est vide.');
      }

      final headers = rows.first.map((c) => (_cellText(c?.value) ?? '').trim().toLowerCase()).toList();
      int? referenceCol, designationCol, unitCol, initialStockCol, storeCol;
      for (var i = 0; i < headers.length; i++) {
        final h = headers[i];
        if (h == 'reference' || h == 'référence' || h == 'ref') {
          referenceCol = i;
        } else if (h == 'designation' || h == 'désignation' || h == 'description') {
          designationCol = i;
        } else if (h == 'unite' || h == 'unité' || h == 'unit') {
          unitCol = i;
        } else if (h == 'stock initial' || h == 'initial_stock' || h == 'initial stock') {
          initialStockCol = i;
        } else if (h == 'magasin' || h == 'store' || h == 'store name' || h == 'nom magasin') {
          storeCol = i;
        }
      }
      if (referenceCol == null || designationCol == null) {
        throw Exception('Colonnes obligatoires manquantes : référence et désignation.');
      }

      final stores = await _storeRepo.getAllStores();
      final defaultStoreId = stores.isNotEmpty ? stores.first.id : null;

      var imported = 0;
      var skipped = 0;
      for (var r = 1; r < rows.length; r++) {
        final row = rows[r];
        if (referenceCol >= row.length) continue;
        final ref = _cellText(row[referenceCol]?.value)?.trim();
        if (ref == null || ref.isEmpty) continue;

        final designation = designationCol < row.length ? (_cellText(row[designationCol]?.value)?.trim() ?? '') : '';
        if (designation.isEmpty) continue;

        var unit = 'unité';
        if (unitCol != null && unitCol < row.length) {
          final v = _cellText(row[unitCol]?.value)?.trim();
          if (v != null && v.isNotEmpty) unit = v;
        }

        var initialStock = 0;
        if (initialStockCol != null && initialStockCol < row.length) {
          initialStock = _cellInt(row[initialStockCol]?.value) ?? 0;
        }

        int? storeId;
        if (storeCol != null && storeCol < row.length) {
          final sname = _cellText(row[storeCol]?.value)?.trim();
          if (sname != null && sname.isNotEmpty) {
            for (final s in stores) {
              if (s.name.toLowerCase() == sname.toLowerCase()) {
                storeId = s.id;
                break;
              }
            }
          }
        }
        storeId ??= defaultStoreId;
        if (storeId == null) {
          skipped++;
          continue;
        }

        final existing = await _productRepo.getByReference(ref);
        final productId = existing?.id ?? await _productRepo.createProduct(reference: ref, designation: designation, unit: unit);

        if (await _productRepo.productStockExists(productId, storeId)) {
          skipped++;
          continue;
        }
        await _productRepo.upsertProductStock(productId: productId, storeId: storeId, initialStock: initialStock);
        imported++;
      }

      await _load();
      DataRefreshBus.instance.notifyChanged();
      if (!mounted) return;
      var msg = '$imported ligne(s) importée(s).';
      if (skipped > 0) msg += ' $skipped doublon(s) ignoré(s).';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur import : $e'), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
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
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: data == null ? null : _openAddDialog,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Nouveau produit'),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
          child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search, size: 20),
              hintText: 'Rechercher par référence ou désignation…',
              isDense: true,
            ),
            onChanged: _onSearchChanged,
          ),
        ),
        Expanded(
          child: _error != null
              ? Center(
                  child: Text(
                    'Erreur de chargement : $_error',
                    style: const TextStyle(color: AppColors.error),
                  ),
                )
              : data == null
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _refresh,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                        child: _ProductTable(
                          rows: data.products,
                          onEdit: _openEditDialog,
                          onDelete: _deleteProduct,
                        ),
                      ),
                    ),
        ),
      ],
    );
  }
}

// Relative flex weights for the products table columns. Using a flexible
// Row instead of fixed pixel widths means the table always fits the
// available width, even on narrow phone screens in portrait mode.
const int _colReference = 11;
const int _colDesignation = 20;
const int _colUnit = 7;
const int _colStores = 13;
const int _colInitial = 10;
const int _colCurrent = 10;
const int _colActions = 11;
const double _cellPadding = 10;

class _ProductTable extends StatelessWidget {
  final List<ProductOverview> rows;
  final void Function(ProductOverview) onEdit;
  final void Function(ProductOverview) onDelete;

  const _ProductTable({required this.rows, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          const _TableHeaderRow(),
          Expanded(
            child: rows.isEmpty
                ? const Center(
                    child: Text('Aucun produit', style: AppTextStyles.bodyMuted),
                  )
                : ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (context, index) => _ProductRow(
                      overview: rows[index],
                      alternate: index.isOdd,
                      onEdit: onEdit,
                      onDelete: onDelete,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TableHeaderRow extends StatelessWidget {
  const _TableHeaderRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: _cellPadding),
      decoration: const BoxDecoration(
        color: AppColors.elevated,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: const [
          Expanded(
            flex: _colReference,
            child: Text('RÉFÉRENCE', style: AppTextStyles.tableHeader, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            flex: _colDesignation,
            child: Text('DÉSIGNATION', style: AppTextStyles.tableHeader, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            flex: _colUnit,
            child: Text('UNITÉ', style: AppTextStyles.tableHeader, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            flex: _colStores,
            child: Text('MAGASINS', style: AppTextStyles.tableHeader, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            flex: _colInitial,
            child: Text(
              'STOCK INITIAL',
              style: AppTextStyles.tableHeader,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: _colCurrent,
            child: Text(
              'STOCK ACTUEL',
              style: AppTextStyles.tableHeader,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: _colActions,
            child: Text(
              'ACTIONS',
              style: AppTextStyles.tableHeader,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  final ProductOverview overview;
  final bool alternate;
  final void Function(ProductOverview) onEdit;
  final void Function(ProductOverview) onDelete;

  const _ProductRow({
    required this.overview,
    required this.alternate,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final product = overview.product;
    final isLow = overview.status == StockStatus.rupture;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: _cellPadding),
      decoration: BoxDecoration(
        color: isLow
            ? AppColors.errorBg.withValues(alpha: 0.45)
            : (alternate ? AppColors.bg : AppColors.surface),
        border: const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: _colReference,
            child: Text(
              product.reference,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.accentLight,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: _colDesignation,
            child: Text(product.designation, style: AppTextStyles.tableCell, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            flex: _colUnit,
            child: Text(product.unit, style: AppTextStyles.tableCell, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            flex: _colStores,
            child: Text(
              overview.storeNames.isEmpty ? '—' : overview.storeNames,
              style: AppTextStyles.bodyMuted,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: _colInitial,
            child: Text(
              '${overview.initialStock}',
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            flex: _colCurrent,
            child: Text(
              '${overview.currentStock}',
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: overview.status.color),
            ),
          ),
          Expanded(
            flex: _colActions,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  color: AppColors.textSecondary,
                  tooltip: 'Modifier',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () => onEdit(overview),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: AppColors.error,
                  tooltip: 'Supprimer',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () => onDelete(overview),
                ),
              ],
            ),
          ),
        ],
      ),
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
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
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

/// Reads a cell's value as plain text, regardless of its underlying
/// [CellValue] type (text, number, bool…).
String? _cellText(CellValue? value) {
  return switch (value) {
    null => null,
    TextCellValue v => v.value.toString().trim(),
    IntCellValue v => '${v.value}',
    DoubleCellValue v => '${v.value}',
    BoolCellValue v => '${v.value}',
    _ => value.toString(),
  };
}

/// Reads a cell's value as an integer, returning `null` if it can't be
/// interpreted as one.
int? _cellInt(CellValue? value) {
  return switch (value) {
    null => null,
    IntCellValue v => v.value,
    DoubleCellValue v => v.value.toInt(),
    TextCellValue v => int.tryParse(v.value.toString().trim()),
    _ => null,
  };
}
