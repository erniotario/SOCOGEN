import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:socogen/modules/stock/models/stock_entry.dart';
import 'package:socogen/modules/stock/models/store.dart';
import 'package:socogen/shared/models/view_models.dart';
import 'package:socogen/modules/catalogue/services/catalogue_service.dart';
import 'package:socogen/modules/stock/repositories/stock_entry_repository.dart';
import 'package:socogen/modules/stock/repositories/store_repository.dart';
import 'package:socogen/core/events/data_refresh_bus.dart';
import 'package:socogen/shared/ui/theme/app_breakpoints.dart';
import 'package:socogen/shared/ui/theme/app_colors.dart';
import 'package:socogen/shared/ui/theme/app_spacing.dart';
import 'package:socogen/shared/ui/theme/app_text_styles.dart';
import 'package:socogen/core/utils/formatters.dart';
import 'package:socogen/shared/ui/widgets/adaptive_table.dart';
import 'package:socogen/shared/ui/widgets/dialog_body.dart';
import 'package:socogen/shared/ui/widgets/empty_state.dart';
import 'package:socogen/shared/ui/widgets/page_header.dart';
import 'package:socogen/shared/ui/widgets/product_autocomplete.dart';
import 'package:socogen/shared/ui/widgets/row_actions.dart';
import 'package:socogen/shared/ui/widgets/skeleton.dart';
import 'package:socogen/core/errors/messages.dart';

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
  final _catalogue = CatalogueService();
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
    final (entries, products, stores) = await (
      _entryRepo.getAll(),
      _catalogue.listerArticles(),
      _storeRepo.getAllStores(),
    ).wait;
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
    final size = context.windowSize;
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
                            _EntryFormCard(
                              products: data.products,
                              stores: data.stores,
                              onSaved: _onChanged,
                            ),
                            const SizedBox(height: AppSpacing.xl),
                            Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    'HISTORIQUE DES ENTRÉES',
                                    style: AppTextStyles.sectionLabel,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Text(
                                  '${data.entries.length} entrée(s)',
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

  AdaptiveTable _table(_EntriesData data) {
    return AdaptiveTable(
      titleColumn: 2,
      subtitleColumn: 3,
      actionsColumn: 6,
      minTableWidth: 760,
      columns: const [
        AppColumn('DATE', flex: 10),
        AppColumn('FOURNISSEUR', flex: 15),
        AppColumn('RÉFÉRENCE', flex: 13),
        AppColumn('DÉSIGNATION', flex: 20),
        AppColumn('MAGASIN', flex: 14),
        AppColumn.number('QUANTITÉ', flex: 10),
        AppColumn.actions(flex: 11),
      ],
      empty: const AppEmptyState(
        icon: Icons.call_received,
        title: 'Aucune entrée',
        message: 'Enregistrez une réception avec le formulaire ci-dessus '
            'pour la voir apparaître ici.',
      ),
      rows: [
        for (final row in data.entries)
          AppRow(
            onTap: () => _openEditDialog(row, data),
            cells: [
              Cells.text(formatDisplayDate(row.entry.date)),
              row.entry.supplier.isEmpty
                  ? Cells.blank
                  : Cells.muted(row.entry.supplier),
              Cells.identifier(row.entry.reference),
              Cells.text(row.entry.designation),
              Cells.muted(row.storeName),
              Cells.number(
                '+ ${row.entry.quantity}',
                color: AppColors.success,
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
                    onPressed: () => _deleteEntry(row.entry),
                  ),
                ],
              ),
            ],
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
        _error = messagePour(e, operation: "l'enregistrement de l'entrée");
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
        _error = messagePour(e, operation: "l'enregistrement de l'entrée");
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Modifier l'entrée"),
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
