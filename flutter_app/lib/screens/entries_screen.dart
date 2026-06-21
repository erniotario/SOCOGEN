import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../data/models/stock_entry.dart';
import '../data/models/store.dart';
import '../data/models/view_models.dart';
import '../data/repositories/product_repository.dart';
import '../data/repositories/stock_entry_repository.dart';
import '../data/repositories/store_repository.dart';
import '../services/data_refresh_bus.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/page_header.dart';
import '../widgets/product_autocomplete.dart';

class EntriesScreen extends StatefulWidget {
  const EntriesScreen({super.key});

  @override
  State<EntriesScreen> createState() => _EntriesScreenState();
}

class _EntriesData {
  final List<StockEntryWithStore> entries;
  final List<ProductOverview> products;
  final List<Store> stores;

  const _EntriesData({required this.entries, required this.products, required this.stores});
}

class _EntriesScreenState extends State<EntriesScreen> {
  final _entryRepo = StockEntryRepository();
  final _productRepo = ProductRepository();
  final _storeRepo = StoreRepository();

  late Future<_EntriesData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
    DataRefreshBus.instance.addListener(_refresh);
  }

  @override
  void dispose() {
    DataRefreshBus.instance.removeListener(_refresh);
    super.dispose();
  }

  /// Refreshes this screen and signals every other screen to reload its
  /// own data (e.g. product stock totals shown elsewhere need updating).
  void _onChanged() {
    _refresh();
    DataRefreshBus.instance.notifyChanged();
  }

  Future<_EntriesData> _load() async {
    final entries = await _entryRepo.getAll();
    final products = await _productRepo.getProductOverviews();
    final stores = await _storeRepo.getAllStores();
    return _EntriesData(entries: entries, products: products, stores: stores);
  }

  Future<void> _refresh() async {
    final data = await _load();
    if (!mounted) return;
    setState(() {
      _future = Future.value(data);
    });
  }

  Future<void> _openEditDialog(StockEntryWithStore row, _EntriesData data) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _EntryFormDialog(entry: row.entry, products: data.products, stores: data.stores),
    );
    if (saved == true) _onChanged();
  }

  Future<void> _deleteEntry(StockEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Supprimer l'entrée"),
        content: const Text('Voulez-vous supprimer cette entrée ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _entryRepo.delete(entry.id);
    _onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const PageHeader(
          title: 'Entrées de stock',
          subtitle: 'Enregistrer les réceptions et approvisionnements',
        ),
        Expanded(
          child: FutureBuilder<_EntriesData>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    'Erreur de chargement : ${snapshot.error}',
                    style: const TextStyle(color: AppColors.error),
                  ),
                );
              }
              final data = snapshot.data!;
              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    _EntryFormCard(products: data.products, stores: data.stores, onSaved: _onChanged),
                    const SizedBox(height: 20),
                    const Text('HISTORIQUE DES ENTRÉES', style: AppTextStyles.sectionLabel),
                    const SizedBox(height: 10),
                    _EntriesTable(
                      rows: data.entries,
                      onEdit: (row) => _openEditDialog(row, data),
                      onDelete: (row) => _deleteEntry(row.entry),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _EntryFormCard extends StatefulWidget {
  final List<ProductOverview> products;
  final List<Store> stores;
  final VoidCallback onSaved;

  const _EntryFormCard({required this.products, required this.stores, required this.onSaved});

  @override
  State<_EntryFormCard> createState() => _EntryFormCardState();
}

class _EntryFormCardState extends State<_EntryFormCard> {
  final _entryRepo = StockEntryRepository();
  final _supplierController = TextEditingController();
  final _refController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  DateTime _date = DateTime.now();
  ProductOverview? _selectedProduct;
  int? _storeId;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _storeId = widget.stores.isNotEmpty ? widget.stores.first.id : null;
  }

  @override
  void dispose() {
    _supplierController.dispose();
    _refController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _onProductSelected(ProductOverview overview) {
    setState(() {
      _selectedProduct = overview;
      if (overview.firstStoreId != null) _storeId = overview.firstStoreId;
    });
  }

  Future<void> _save() async {
    final supplier = _supplierController.text.trim();
    final qty = int.tryParse(_quantityController.text.trim()) ?? 0;

    if (_selectedProduct == null) {
      setState(() => _error = 'Sélectionnez une référence produit.');
      return;
    }
    if (_storeId == null) {
      setState(() => _error = 'Sélectionnez un magasin.');
      return;
    }
    if (qty <= 0) {
      setState(() => _error = 'La quantité doit être supérieure à 0.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _entryRepo.create(StockEntry(
        id: 0,
        date: DateFormat('yyyy-MM-dd').format(_date),
        supplier: supplier,
        reference: _selectedProduct!.product.reference,
        designation: _selectedProduct!.product.designation,
        storeId: _storeId!,
        quantity: qty,
      ));
      _supplierController.clear();
      _refController.clear();
      _quantityController.text = '1';
      setState(() {
        _selectedProduct = null;
        _saving = false;
      });
      widget.onSaved();
    } catch (e) {
      setState(() {
        _error = 'Erreur : $e';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('NOUVELLE ENTRÉE', style: AppTextStyles.sectionLabel),
          const SizedBox(height: 16),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              SizedBox(
                width: 150,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: _pickDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Date *'),
                    child: Text(DateFormat('dd/MM/yyyy').format(_date)),
                  ),
                ),
              ),
              SizedBox(
                width: 200,
                child: TextField(
                  controller: _supplierController,
                  decoration: const InputDecoration(labelText: 'Fournisseur', hintText: 'Ex: CIMENCAM'),
                ),
              ),
              SizedBox(
                width: 280,
                child: ProductAutocomplete(
                  products: widget.products,
                  controller: _refController,
                  onSelected: _onProductSelected,
                ),
              ),
              SizedBox(
                width: 220,
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Désignation'),
                  child: Text(
                    _selectedProduct?.product.designation ?? '—',
                    style: const TextStyle(color: AppColors.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<int>(
                  initialValue: _storeId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Magasin *'),
                  items: widget.stores
                      .map((s) => DropdownMenuItem(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (value) => setState(() => _storeId = value),
                ),
              ),
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _quantityController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Quantité *'),
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
          ],
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.add, size: 18),
              label: Text(_saving ? 'Enregistrement…' : "Enregistrer l'entrée"),
            ),
          ),
        ],
      ),
    );
  }
}

// Relative flex weights for the entries table columns. Using a flexible Row
// instead of fixed pixel widths means the table always fits the available
// width, even on narrow phone screens in portrait mode.
const int _colDate = 10;
const int _colSupplier = 15;
const int _colReference = 13;
const int _colDesignation = 20;
const int _colStore = 14;
const int _colQty = 10;
const int _colActions = 11;
const double _cellPadding = 10;

class _EntriesTable extends StatelessWidget {
  final List<StockEntryWithStore> rows;
  final void Function(StockEntryWithStore) onEdit;
  final void Function(StockEntryWithStore) onDelete;

  const _EntriesTable({required this.rows, required this.onEdit, required this.onDelete});

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
          rows.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: Text('Aucune entrée', style: AppTextStyles.bodyMuted)),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: rows.length,
                  itemBuilder: (context, index) => _EntryRow(
                    row: rows[index],
                    alternate: index.isOdd,
                    onEdit: onEdit,
                    onDelete: onDelete,
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
            flex: _colDate,
            child: Text('DATE', style: AppTextStyles.tableHeader, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            flex: _colSupplier,
            child: Text('FOURNISSEUR', style: AppTextStyles.tableHeader, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            flex: _colReference,
            child: Text('RÉFÉRENCE', style: AppTextStyles.tableHeader, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            flex: _colDesignation,
            child: Text('DÉSIGNATION', style: AppTextStyles.tableHeader, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            flex: _colStore,
            child: Text('MAGASIN', style: AppTextStyles.tableHeader, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            flex: _colQty,
            child: Text(
              'QUANTITÉ',
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

class _EntryRow extends StatelessWidget {
  final StockEntryWithStore row;
  final bool alternate;
  final void Function(StockEntryWithStore) onEdit;
  final void Function(StockEntryWithStore) onDelete;

  const _EntryRow({required this.row, required this.alternate, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final entry = row.entry;
    var displayDate = entry.date;
    try {
      displayDate = DateFormat('dd/MM/yyyy').format(DateTime.parse(entry.date));
    } catch (_) {}

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: _cellPadding),
      decoration: BoxDecoration(
        color: alternate ? AppColors.bg : AppColors.surface,
        border: const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: _colDate,
            child: Text(displayDate, style: AppTextStyles.tableCell, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            flex: _colSupplier,
            child: Text(
              entry.supplier.isEmpty ? '—' : entry.supplier,
              style: AppTextStyles.bodyMuted,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: _colReference,
            child: Text(
              entry.reference,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.accentLight),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: _colDesignation,
            child: Text(entry.designation, style: AppTextStyles.tableCell, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            flex: _colStore,
            child: Text(row.storeName, style: AppTextStyles.bodyMuted, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            flex: _colQty,
            child: Text(
              '+ ${entry.quantity}',
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.success),
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
                  onPressed: () => onEdit(row),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: AppColors.error,
                  tooltip: 'Supprimer',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () => onDelete(row),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryFormDialog extends StatefulWidget {
  final StockEntry entry;
  final List<ProductOverview> products;
  final List<Store> stores;

  const _EntryFormDialog({required this.entry, required this.products, required this.stores});

  @override
  State<_EntryFormDialog> createState() => _EntryFormDialogState();
}

class _EntryFormDialogState extends State<_EntryFormDialog> {
  final _entryRepo = StockEntryRepository();
  late final TextEditingController _supplierController;
  late final TextEditingController _refController;
  late final TextEditingController _quantityController;
  late DateTime _date;
  ProductOverview? _selectedProduct;
  int? _storeId;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    _supplierController = TextEditingController(text: entry.supplier);
    _quantityController = TextEditingController(text: '${entry.quantity}');

    ProductOverview? found;
    for (final o in widget.products) {
      if (o.product.reference == entry.reference) {
        found = o;
        break;
      }
    }
    _selectedProduct = found;
    _refController = TextEditingController(
      text: found != null ? '${found.product.reference} — ${found.product.designation}' : '${entry.reference} — ${entry.designation}',
    );
    _storeId = entry.storeId;
    try {
      _date = DateTime.parse(entry.date);
    } catch (_) {
      _date = DateTime.now();
    }
  }

  @override
  void dispose() {
    _supplierController.dispose();
    _refController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final qty = int.tryParse(_quantityController.text.trim()) ?? 0;

    if (_selectedProduct == null) {
      setState(() => _error = 'Sélectionnez une référence produit.');
      return;
    }
    if (_storeId == null) {
      setState(() => _error = 'Sélectionnez un magasin.');
      return;
    }
    if (qty <= 0) {
      setState(() => _error = 'La quantité doit être supérieure à 0.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _entryRepo.update(StockEntry(
        id: widget.entry.id,
        date: DateFormat('yyyy-MM-dd').format(_date),
        supplier: _supplierController.text.trim(),
        reference: _selectedProduct!.product.reference,
        designation: _selectedProduct!.product.designation,
        storeId: _storeId!,
        quantity: qty,
      ));
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
      title: const Text("Modifier l'entrée"),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Date'),
                child: Text(DateFormat('dd/MM/yyyy').format(_date)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _supplierController,
              decoration: const InputDecoration(labelText: 'Fournisseur'),
            ),
            const SizedBox(height: 12),
            ProductAutocomplete(
              products: widget.products,
              controller: _refController,
              onSelected: (overview) => setState(() => _selectedProduct = overview),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _storeId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Magasin'),
              items: widget.stores
                  .map((s) => DropdownMenuItem(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (value) => setState(() => _storeId = value),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _quantityController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Quantité'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Annuler')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Enregistrer'),
        ),
      ],
    );
  }
}
