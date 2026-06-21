import 'package:flutter/material.dart';

import '../data/models/store.dart';
import '../data/models/view_models.dart';
import '../data/repositories/store_repository.dart';
import '../services/data_refresh_bus.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/page_header.dart';

class StoresScreen extends StatefulWidget {
  const StoresScreen({super.key});

  @override
  State<StoresScreen> createState() => _StoresScreenState();
}

class _StoresScreenState extends State<StoresScreen> {
  final _storeRepo = StoreRepository();

  late Future<List<StoreOverview>> _future;
  int? _selectedStoreId;
  Future<StoreDetails>? _detailsFuture;

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

  Future<List<StoreOverview>> _load() => _storeRepo.getStoreOverview();

  Future<void> _refresh() async {
    final stores = await _load();
    if (!mounted) return;
    setState(() {
      _future = Future.value(stores);
    });
    if (_selectedStoreId != null) {
      final stillExists = stores.any((o) => o.store.id == _selectedStoreId);
      if (stillExists) {
        _selectStore(_selectedStoreId!);
      } else {
        setState(() {
          _selectedStoreId = null;
          _detailsFuture = null;
        });
      }
    }
  }

  void _selectStore(int storeId) {
    setState(() {
      _selectedStoreId = storeId;
      _detailsFuture = _storeRepo.getStoreDetails(storeId);
    });
  }

  /// Refreshes this screen and signals every other screen to reload its
  /// own data (e.g. store dropdowns elsewhere need to pick up the change).
  void _onChanged() {
    _refresh();
    DataRefreshBus.instance.notifyChanged();
  }

  Future<void> _openAddDialog() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => const _StoreFormDialog(),
    );
    if (saved == true) _onChanged();
  }

  Future<void> _openEditDialog(Store store) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _StoreFormDialog(existing: store),
    );
    if (saved == true) _onChanged();
  }

  Future<void> _deleteStore(Store store) async {
    final hasLinked = await _storeRepo.hasLinkedData(store.id);
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer le magasin'),
        content: Text(
          hasLinked
              ? 'Le magasin « ${store.name} » contient des données de stock (produits, entrées ou sorties). '
                  'Supprimer quand même ?'
              : 'Voulez-vous vraiment supprimer le magasin « ${store.name} » ?',
        ),
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
    await _storeRepo.deleteStore(store.id);
    if (_selectedStoreId == store.id) {
      _selectedStoreId = null;
      _detailsFuture = null;
    }
    _onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        PageHeader(
          title: 'Magasins',
          subtitle: 'Gérer les points de stockage',
          actions: [
            ElevatedButton.icon(
              onPressed: _openAddDialog,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Nouveau magasin'),
            ),
          ],
        ),
        Expanded(
          child: FutureBuilder<List<StoreOverview>>(
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
              final stores = snapshot.data!;
              return RefreshIndicator(
                onRefresh: _refresh,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final table = _StoreTable(
                        rows: stores,
                        selectedStoreId: _selectedStoreId,
                        onSelect: (overview) => _selectStore(overview.store.id),
                        onEdit: (overview) => _openEditDialog(overview.store),
                        onDelete: (overview) => _deleteStore(overview.store),
                      );
                      final details = _DetailsPanel(detailsFuture: _detailsFuture);

                      // On narrow phone screens there isn't enough width for the
                      // table and the details sidebar side by side, so stack them
                      // vertically instead.
                      if (constraints.maxWidth >= _detailsBreakpoint) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 3, child: table),
                            const SizedBox(width: 16),
                            SizedBox(width: 240, child: details),
                          ],
                        );
                      }
                      return Column(
                        children: [
                          Expanded(child: table),
                          const SizedBox(height: 16),
                          details,
                        ],
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// Below this content width, the details sidebar moves below the table
// instead of sitting beside it.
const double _detailsBreakpoint = 700;

// Relative flex weights for the stores table columns. Using a flexible Row
// instead of fixed pixel widths means the table always fits the available
// width, even on narrow phone screens in portrait mode.
const int _colId = 8;
const int _colName = 35;
const int _colProducts = 15;
const int _colStock = 20;
const int _colActions = 14;
const double _cellPadding = 10;

class _StoreTable extends StatelessWidget {
  final List<StoreOverview> rows;
  final int? selectedStoreId;
  final void Function(StoreOverview) onSelect;
  final void Function(StoreOverview) onEdit;
  final void Function(StoreOverview) onDelete;

  const _StoreTable({
    required this.rows,
    required this.selectedStoreId,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
  });

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
                ? const Center(child: Text('Aucun magasin', style: AppTextStyles.bodyMuted))
                : ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (context, index) => _StoreRow(
                      overview: rows[index],
                      alternate: index.isOdd,
                      selected: rows[index].store.id == selectedStoreId,
                      onSelect: onSelect,
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
            flex: _colId,
            child: Text(
              'ID',
              style: AppTextStyles.tableHeader,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: _colName,
            child: Text('NOM DU MAGASIN', style: AppTextStyles.tableHeader, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            flex: _colProducts,
            child: Text(
              'PRODUITS',
              style: AppTextStyles.tableHeader,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: _colStock,
            child: Text(
              'STOCK TOTAL',
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

class _StoreRow extends StatelessWidget {
  final StoreOverview overview;
  final bool alternate;
  final bool selected;
  final void Function(StoreOverview) onSelect;
  final void Function(StoreOverview) onEdit;
  final void Function(StoreOverview) onDelete;

  const _StoreRow({
    required this.overview,
    required this.alternate,
    required this.selected,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final stock = overview.totalStock;
    final stockColor = stock > 0
        ? AppColors.success
        : (stock < 0 ? AppColors.error : AppColors.textSecondary);

    return InkWell(
      onTap: () => onSelect(overview),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: _cellPadding),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accent.withValues(alpha: 0.18)
              : (alternate ? AppColors.bg : AppColors.surface),
          border: const Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            Expanded(
              flex: _colId,
              child: Text(
                '${overview.store.id}',
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyMuted,
              ),
            ),
            Expanded(
              flex: _colName,
              child: Text(
                overview.store.name,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.accentLight),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: _colProducts,
              child: Text(
                '${overview.productCount}',
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.tableCell,
              ),
            ),
            Expanded(
              flex: _colStock,
              child: Text(
                '$stock',
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: stockColor),
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
      ),
    );
  }
}

class _DetailsPanel extends StatelessWidget {
  final Future<StoreDetails>? detailsFuture;

  const _DetailsPanel({required this.detailsFuture});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('DÉTAILS', style: AppTextStyles.sectionLabel),
          const SizedBox(height: 10),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 12),
          if (detailsFuture == null)
            const _DetailRows(
              name: '—',
              products: '—',
              entries: '—',
              outputs: '—',
              stock: '—',
              stockColor: AppColors.textSecondary,
            )
          else
            FutureBuilder<StoreDetails>(
              future: detailsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError || !snapshot.hasData) {
                  return const _DetailRows(
                    name: '—',
                    products: '—',
                    entries: '—',
                    outputs: '—',
                    stock: '—',
                    stockColor: AppColors.textSecondary,
                  );
                }
                final details = snapshot.data!;
                final stock = details.currentStock;
                final stockColor = stock > 0
                    ? AppColors.success
                    : (stock < 0 ? AppColors.error : AppColors.textSecondary);
                return _DetailRows(
                  name: details.store.name,
                  products: '${details.productCount}',
                  entries: '+${details.totalEntries}',
                  outputs: '-${details.totalOutputs}',
                  stock: '$stock',
                  stockColor: stockColor,
                );
              },
            ),
        ],
      ),
    );
  }
}

class _DetailRows extends StatelessWidget {
  final String name;
  final String products;
  final String entries;
  final String outputs;
  final String stock;
  final Color stockColor;

  const _DetailRows({
    required this.name,
    required this.products,
    required this.entries,
    required this.outputs,
    required this.stock,
    required this.stockColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DetailRow(label: 'Magasin', value: name, color: AppColors.textPrimary),
        _DetailRow(label: 'Produits', value: products, color: AppColors.textPrimary),
        _DetailRow(label: 'Total entrées', value: entries, color: AppColors.success),
        _DetailRow(label: 'Total sorties', value: outputs, color: AppColors.error),
        _DetailRow(label: 'Stock actuel', value: stock, color: stockColor),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _DetailRow({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: AppTextStyles.kpiLabel),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}

class _StoreFormDialog extends StatefulWidget {
  final Store? existing;

  const _StoreFormDialog({this.existing});

  @override
  State<_StoreFormDialog> createState() => _StoreFormDialogState();
}

class _StoreFormDialogState extends State<_StoreFormDialog> {
  final _storeRepo = StoreRepository();
  late final TextEditingController _nameController;
  String? _error;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Le nom du magasin est obligatoire.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final exists = await _storeRepo.nameExists(name, excludeId: widget.existing?.id);
      if (exists) {
        setState(() {
          _error = 'Le magasin « $name » existe déjà.';
          _saving = false;
        });
        return;
      }
      if (_isEdit) {
        await _storeRepo.updateStore(widget.existing!.id, name);
      } else {
        await _storeRepo.createStore(name);
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
      title: Text(_isEdit ? 'Modifier le magasin' : 'Nouveau magasin'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Nom du magasin *',
                hintText: 'Ex : Magasin Central, Entrepôt Nord…',
              ),
              autofocus: true,
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
              : Text(_isEdit ? 'Enregistrer' : 'Ajouter'),
        ),
      ],
    );
  }
}
