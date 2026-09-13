import 'dart:async';

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
import '../theme/app_breakpoints.dart';
import '../theme/app_colors.dart';
import '../widgets/status_badge.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../utils/formatters.dart';
import '../widgets/adaptive_table.dart';
import '../widgets/dialog_body.dart';
import '../widgets/empty_state.dart';
import '../widgets/page_header.dart';
import '../widgets/product_autocomplete.dart';
import '../widgets/row_actions.dart';
import '../widgets/skeleton.dart';

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
    final (outputs, products, stores) = await (
      _outputRepo.getAll(),
      _productRepo.getProductOverviews(),
      _storeRepo.getAllStores(),
    ).wait;
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
    final size = context.windowSize;
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
              final padding = AppSpacing.pagePadding(size);
              if (snapshot.connectionState != ConnectionState.done) {
                return Padding(padding: padding, child: const SkeletonList());
              }
              if (snapshot.hasError) {
                return AppErrorState(
                  message: '${snapshot.error}',
                  onRetry: _refresh,
                );
              }
              final data = snapshot.data!;
              return RefreshIndicator(
                onRefresh: _refresh,
                color: AppColors.accentLight,
                backgroundColor: AppColors.surface,
                child: CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        padding.left,
                        padding.top,
                        padding.right,
                        0,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _OutputFormCard(
                              products: data.products,
                              stores: data.stores,
                              onSaved: _onChanged,
                            ),
                            const SizedBox(height: AppSpacing.xl),
                            Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    'HISTORIQUE DES SORTIES',
                                    style: AppTextStyles.sectionLabel,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Text(
                                  '${data.outputs.length} sortie(s)',
                                  style: AppTextStyles.captionMuted,
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.md),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        padding.left,
                        0,
                        padding.right,
                        padding.bottom,
                      ),
                      sliver: SliverAdaptiveTable(table: _table(data)),
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

  AdaptiveTable _table(_OutputsData data) {
    return AdaptiveTable(
      titleColumn: 1,
      subtitleColumn: 2,
      actionsColumn: 7,
      minTableWidth: 860,
      columns: const [
        AppColumn('DATE', flex: 9),
        AppColumn('RÉFÉRENCE', flex: 12),
        AppColumn('DÉSIGNATION', flex: 18),
        AppColumn('N° FACTURE', flex: 11),
        AppColumn('MAGASIN', flex: 13),
        AppColumn('DESTINATION', flex: 14),
        AppColumn.number('QUANTITÉ', flex: 10),
        AppColumn.actions(flex: 11),
      ],
      empty: const AppEmptyState(
        icon: Icons.call_made,
        title: 'Aucune sortie',
        message: 'Enregistrez une cession avec le formulaire ci-dessus '
            'pour la voir apparaître ici.',
      ),
      rows: [
        for (final row in data.outputs)
          AppRow(
            onTap: () => _openEditDialog(row, data),
            cells: [
              Cells.text(formatDisplayDate(row.output.date)),
              Cells.identifier(row.output.reference),
              Cells.text(row.output.designation),
              row.output.invoiceNumber.isEmpty
                  ? Cells.blank
                  : Cells.muted(row.output.invoiceNumber),
              Cells.muted(row.storeName),
              row.output.destination.isEmpty
                  ? Cells.blank
                  : Cells.muted(row.output.destination),
              Cells.number(
                '− ${row.output.quantity}',
                color: AppColors.error,
                strong: true,
              ),
              RowActions(
                actions: [
                  RowAction(
                    icon: Icons.edit_outlined,
                    tooltip: 'Modifier',
                    onPressed: () => _openEditDialog(row, data),
                  ),
                  RowAction(
                    icon: Icons.delete_outline,
                    tooltip: 'Supprimer',
                    destructive: true,
                    onPressed: () => _deleteOutput(row.output),
                  ),
                ],
              ),
            ],
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

  /// The chip under the product picker reads its colour from the same
  /// thresholds as every table, so a store already in the negative
  /// announces itself here too -- on the one screen where the next
  /// sortie would push it further down.
  Color _stockColor(int current) => StockStatus.fromCurrent(current).color;

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

    // Read for the chosen magasin at save time rather than trusting
    // _availability, which is loaded when the product is picked and
    // holds nothing for a magasin the product has no product_stocks row
    // in. The old fallback then compared the quantity against the total
    // across every other store and let the sortie through.
    final current = await _productRepo.balanceExcluding(
      reference: _selectedProduct!.product.reference,
      storeId: _storeId!,
    );
    if (qty > current) {
      if (!mounted) return;
      final after = current - qty;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Stock insuffisant'),
          content: Text(
            'Stock disponible dans ce magasin : $current. '
            'Quantité demandée : $qty.\n'
            'Cette sortie laisserait le stock à $after.\n\n'
            'Enregistrer quand même ? La ligne sera signalée dans les '
            'Rapports comme à régulariser.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Enregistrer'),
            ),
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
      content: DialogBody(
        maxWidth: 420,
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
