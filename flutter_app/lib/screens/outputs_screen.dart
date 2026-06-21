import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../data/models/stock_output.dart';
import '../data/models/store.dart';
import '../data/models/view_models.dart';
import '../data/repositories/product_repository.dart';
import '../data/repositories/stock_output_repository.dart';
import '../data/repositories/store_repository.dart';
import '../services/data_refresh_bus.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/page_header.dart';
import '../widgets/product_autocomplete.dart';

class OutputsScreen extends StatefulWidget {
  const OutputsScreen({super.key});

  @override
  State<OutputsScreen> createState() => _OutputsScreenState();
}

class _OutputsData {
  final List<StockOutputWithStore> outputs;
  final List<ProductOverview> products;
  final List<Store> stores;

  const _OutputsData({required this.outputs, required this.products, required this.stores});
}

class _OutputsScreenState extends State<OutputsScreen> {
  final _outputRepo = StockOutputRepository();
  final _productRepo = ProductRepository();
  final _storeRepo = StoreRepository();

  late Future<_OutputsData> _future;

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

  Future<_OutputsData> _load() async {
    final outputs = await _outputRepo.getAll();
    final products = await _productRepo.getProductOverviews();
    final stores = await _storeRepo.getAllStores();
    return _OutputsData(outputs: outputs, products: products, stores: stores);
  }

  Future<void> _refresh() async {
    final data = await _load();
    if (!mounted) return;
    setState(() {
      _future = Future.value(data);
    });
  }

  Future<void> _openEditDialog(StockOutputWithStore row, _OutputsData data) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _OutputFormDialog(output: row.output, products: data.products, stores: data.stores),
    );
    if (saved == true) _onChanged();
  }

  Future<void> _deleteOutput(StockOutput output) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer la sortie'),
        content: const Text('Voulez-vous supprimer cette sortie ?'),
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
    await _outputRepo.delete(output.id);
    _onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const PageHeader(
          title: 'Sorties de stock',
          subtitle: 'Enregistrer les cessions et distributions',
        ),
        Expanded(
          child: FutureBuilder<_OutputsData>(
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
                    _OutputFormCard(products: data.products, stores: data.stores, onSaved: _onChanged),
                    const SizedBox(height: 20),
                    const Text('HISTORIQUE DES SORTIES', style: AppTextStyles.sectionLabel),
                    const SizedBox(height: 10),
                    _OutputsTable(
                      rows: data.outputs,
                      onEdit: (row) => _openEditDialog(row, data),
                      onDelete: (row) => _deleteOutput(row.output),
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

class _OutputFormCard extends StatefulWidget {
  final List<ProductOverview> products;
  final List<Store> stores;
  final VoidCallback onSaved;

  const _OutputFormCard({required this.products, required this.stores, required this.onSaved});

  @override
  State<_OutputFormCard> createState() => _OutputFormCardState();
}

class _OutputFormCardState extends State<_OutputFormCard> {
  final _outputRepo = StockOutputRepository();
  final _productRepo = ProductRepository();
  final _refController = TextEditingController();
  final _invoiceController = TextEditingController();
  final _destinationController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  DateTime _date = DateTime.now();
  ProductOverview? _selectedProduct;
  List<StoreAvailability>? _availability;
  String _storeHint = '';
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
    _refController.dispose();
    _invoiceController.dispose();
    _destinationController.dispose();
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

  List<DropdownMenuItem<int>> get _storeItems {
    final availability = _availability;
    if (availability != null) {
      final available = availability.where((a) => a.available > 0).toList();
      if (available.isNotEmpty) {
        return available
            .map((a) => DropdownMenuItem(
                  value: a.storeId,
                  child: Text(
                    '${a.storeName}  (${a.available} disponible${a.available > 1 ? 's' : ''})',
                    overflow: TextOverflow.ellipsis,
                  ),
                ))
            .toList();
      }
    }
    return widget.stores.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList();
  }

  Future<void> _onProductSelected(ProductOverview overview) async {
    final availability = await _productRepo.getStoreAvailability(overview.product.reference, overview.product.id);
    if (!mounted) return;
    final available = availability.where((a) => a.available > 0).toList();
    setState(() {
      _selectedProduct = overview;
      _availability = availability;
      if (available.isNotEmpty) {
        _storeId = available.first.storeId;
        _storeHint = '${available.length} magasin(s) avec stock disponible';
      } else if (availability.isNotEmpty) {
        _storeId = widget.stores.isNotEmpty ? widget.stores.first.id : null;
        _storeHint = 'Aucun stock disponible dans aucun magasin';
      } else {
        _storeId = widget.stores.isNotEmpty ? widget.stores.first.id : null;
        _storeHint = '';
      }
    });
  }

  Color _stockColor(int current) {
    if (current > 10) return AppColors.success;
    if (current > 0) return AppColors.warning;
    return AppColors.error;
  }

  Future<void> _save() async {
    final invoice = _invoiceController.text.trim();
    final destination = _destinationController.text.trim();
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

    final storeAvail = _availability?.where((a) => a.storeId == _storeId).firstOrNull;
    final current = storeAvail?.available ?? _selectedProduct!.currentStock;
    if (qty > current) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Stock insuffisant'),
          content: Text('Stock disponible dans ce magasin : $current. Quantité demandée : $qty.\nContinuer quand même ?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Non')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Oui')),
          ],
        ),
      );
      if (proceed != true) return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _outputRepo.create(StockOutput(
        id: 0,
        date: DateFormat('yyyy-MM-dd').format(_date),
        reference: _selectedProduct!.product.reference,
        designation: _selectedProduct!.product.designation,
        invoiceNumber: invoice,
        storeId: _storeId!,
        destination: destination,
        quantity: qty,
      ));
      _refController.clear();
      _invoiceController.clear();
      _destinationController.clear();
      _quantityController.text = '1';
      setState(() {
        _selectedProduct = null;
        _availability = null;
        _storeHint = '';
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
    final product = _selectedProduct;
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
          const Text('NOUVELLE SORTIE', style: AppTextStyles.sectionLabel),
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
                width: 260,
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
                    product?.product.designation ?? '—',
                    style: const TextStyle(color: AppColors.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              SizedBox(
                width: 160,
                child: TextField(
                  controller: _invoiceController,
                  decoration: const InputDecoration(labelText: 'N° facture', hintText: 'Ex: FAC-2025-001'),
                ),
              ),
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<int>(
                  initialValue: _storeId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Magasin *'),
                  items: _storeItems,
                  onChanged: (value) => setState(() => _storeId = value),
                ),
              ),
              SizedBox(
                width: 220,
                child: TextField(
                  controller: _destinationController,
                  decoration: const InputDecoration(labelText: 'Destination', hintText: 'Ex: Chantier Bastos'),
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
          if (_storeHint.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_storeHint, style: const TextStyle(color: AppColors.error, fontSize: 11)),
          ],
          if (product != null) ...[
            const SizedBox(height: 8),
            Builder(builder: (context) {
              final storeAvail = _availability?.where((a) => a.storeId == _storeId).firstOrNull;
              final displayStock = storeAvail?.available ?? product.currentStock;
              final label = storeAvail != null
                  ? 'Stock (${storeAvail.storeName}) : $displayStock ${product.product.unit}'
                  : 'Stock total : $displayStock ${product.product.unit}';
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _stockColor(displayStock).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: _stockColor(displayStock),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            }),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
          ],
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.remove, size: 18),
              label: Text(_saving ? 'Enregistrement…' : 'Enregistrer la sortie'),
            ),
          ),
        ],
      ),
    );
  }
}

// Relative flex weights for the outputs table columns. Using a flexible Row
// instead of fixed pixel widths means the table always fits the available
// width, even on narrow phone screens in portrait mode.
const int _colDate = 9;
const int _colReference = 12;
const int _colDesignation = 18;
const int _colInvoice = 11;
const int _colStore = 13;
const int _colDestination = 14;
const int _colQty = 10;
const int _colActions = 11;
const double _cellPadding = 10;

class _OutputsTable extends StatelessWidget {
  final List<StockOutputWithStore> rows;
  final void Function(StockOutputWithStore) onEdit;
  final void Function(StockOutputWithStore) onDelete;

  const _OutputsTable({required this.rows, required this.onEdit, required this.onDelete});

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
                  child: Center(child: Text('Aucune sortie', style: AppTextStyles.bodyMuted)),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: rows.length,
                  itemBuilder: (context, index) => _OutputRow(
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
            flex: _colReference,
            child: Text('RÉFÉRENCE', style: AppTextStyles.tableHeader, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            flex: _colDesignation,
            child: Text('DÉSIGNATION', style: AppTextStyles.tableHeader, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            flex: _colInvoice,
            child: Text('N° FACTURE', style: AppTextStyles.tableHeader, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            flex: _colStore,
            child: Text('MAGASIN', style: AppTextStyles.tableHeader, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            flex: _colDestination,
            child: Text('DESTINATION', style: AppTextStyles.tableHeader, overflow: TextOverflow.ellipsis),
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

class _OutputRow extends StatelessWidget {
  final StockOutputWithStore row;
  final bool alternate;
  final void Function(StockOutputWithStore) onEdit;
  final void Function(StockOutputWithStore) onDelete;

  const _OutputRow({required this.row, required this.alternate, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final output = row.output;
    var displayDate = output.date;
    try {
      displayDate = DateFormat('dd/MM/yyyy').format(DateTime.parse(output.date));
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
            flex: _colReference,
            child: Text(
              output.reference,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.accentLight),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: _colDesignation,
            child: Text(output.designation, style: AppTextStyles.tableCell, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            flex: _colInvoice,
            child: Text(
              output.invoiceNumber.isEmpty ? '—' : output.invoiceNumber,
              style: AppTextStyles.bodyMuted,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: _colStore,
            child: Text(row.storeName, style: AppTextStyles.bodyMuted, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            flex: _colDestination,
            child: Text(
              output.destination.isEmpty ? '—' : output.destination,
              style: AppTextStyles.bodyMuted,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: _colQty,
            child: Text(
              '− ${output.quantity}',
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.error),
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

class _OutputFormDialog extends StatefulWidget {
  final StockOutput output;
  final List<ProductOverview> products;
  final List<Store> stores;

  const _OutputFormDialog({required this.output, required this.products, required this.stores});

  @override
  State<_OutputFormDialog> createState() => _OutputFormDialogState();
}

class _OutputFormDialogState extends State<_OutputFormDialog> {
  final _outputRepo = StockOutputRepository();
  late final TextEditingController _refController;
  late final TextEditingController _invoiceController;
  late final TextEditingController _destinationController;
  late final TextEditingController _quantityController;
  late DateTime _date;
  ProductOverview? _selectedProduct;
  int? _storeId;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final output = widget.output;
    _invoiceController = TextEditingController(text: output.invoiceNumber);
    _destinationController = TextEditingController(text: output.destination);
    _quantityController = TextEditingController(text: '${output.quantity}');

    ProductOverview? found;
    for (final o in widget.products) {
      if (o.product.reference == output.reference) {
        found = o;
        break;
      }
    }
    _selectedProduct = found;
    _refController = TextEditingController(
      text: found != null ? '${found.product.reference} — ${found.product.designation}' : '${output.reference} — ${output.designation}',
    );
    _storeId = output.storeId;
    try {
      _date = DateTime.parse(output.date);
    } catch (_) {
      _date = DateTime.now();
    }
  }

  @override
  void dispose() {
    _refController.dispose();
    _invoiceController.dispose();
    _destinationController.dispose();
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
      await _outputRepo.update(StockOutput(
        id: widget.output.id,
        date: DateFormat('yyyy-MM-dd').format(_date),
        reference: _selectedProduct!.product.reference,
        designation: _selectedProduct!.product.designation,
        invoiceNumber: _invoiceController.text.trim(),
        storeId: _storeId!,
        destination: _destinationController.text.trim(),
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
      title: const Text('Modifier la sortie'),
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
            ProductAutocomplete(
              products: widget.products,
              controller: _refController,
              onSelected: (overview) => setState(() => _selectedProduct = overview),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _invoiceController,
              decoration: const InputDecoration(labelText: 'N° facture'),
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
              controller: _destinationController,
              decoration: const InputDecoration(labelText: 'Destination'),
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
