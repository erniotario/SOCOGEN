import 'package:flutter/material.dart';

import '../data/models/store.dart';
import '../data/models/view_models.dart';
import '../data/repositories/store_repository.dart';
import '../services/data_refresh_bus.dart';
import '../theme/app_breakpoints.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../widgets/adaptive_table.dart';
import '../widgets/empty_state.dart';
import '../widgets/page_header.dart';
import '../widgets/row_actions.dart';
import '../widgets/skeleton.dart';

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
    final size = context.windowSize;
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
              final padding = AppSpacing.pagePadding(size);
              if (snapshot.connectionState != ConnectionState.done) {
                return Padding(
                  padding: padding,
                  child: const SkeletonList(),
                );
              }
              if (snapshot.hasError) {
                return AppErrorState(
                  message: '${snapshot.error}',
                  onRetry: _refresh,
                );
              }
              final stores = snapshot.data!;
              return RefreshIndicator(
                onRefresh: _refresh,
                color: AppColors.accentLight,
                backgroundColor: AppColors.surface,
                child: Padding(
                  padding: padding,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final table = _table(stores);
                      final details =
                          _DetailsPanel(detailsFuture: _detailsFuture);

                      // The details sidebar only earns its place when the
                      // table still has room to breathe beside it.
                      if (constraints.maxWidth >= _detailsBreakpoint) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 3, child: table),
                            const SizedBox(width: AppSpacing.lg),
                            SizedBox(width: 260, child: details),
                          ],
                        );
                      }
                      // Stacked: both panes share the height. The details
                      // panel keeps its natural size when there is room
                      // (loose fit) and scrolls instead of overflowing on a
                      // short window, e.g. a phone in landscape.
                      return Column(
                        children: [
                          Expanded(flex: 3, child: table),
                          const SizedBox(height: AppSpacing.lg),
                          Flexible(
                            flex: 2,
                            fit: FlexFit.loose,
                            child: SingleChildScrollView(child: details),
                          ),
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

  Widget _table(List<StoreOverview> rows) {
    return AdaptiveTable(
      actionsColumn: 4,
      titleColumn: 1,
      subtitleColumn: null,
      minTableWidth: 560,
      columns: const [
        AppColumn('ID', flex: 8, align: Alignment.center),
        AppColumn('NOM DU MAGASIN', flex: 35),
        AppColumn('PRODUITS', flex: 15, align: Alignment.center),
        AppColumn.number('STOCK TOTAL', flex: 20),
        AppColumn.actions(flex: 14),
      ],
      empty: AppEmptyState(
        icon: Icons.store_outlined,
        title: 'Aucun magasin',
        message: 'Créez un magasin pour commencer à y affecter du stock.',
        action: ElevatedButton.icon(
          onPressed: _openAddDialog,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Nouveau magasin'),
        ),
      ),
      rows: [
        for (final overview in rows)
          AppRow(
            selected: overview.store.id == _selectedStoreId,
            onTap: () => _selectStore(overview.store.id),
            cells: [
              Cells.muted('${overview.store.id}'),
              Cells.identifier(overview.store.name),
              Cells.number(overview.productCount),
              Cells.number(
                overview.totalStock,
                strong: true,
                size: 14,
                color: overview.totalStock > 0
                    ? AppColors.success
                    : (overview.totalStock < 0
                        ? AppColors.error
                        : AppColors.textSecondary),
              ),
              RowActions(
                actions: [
                  RowAction(
                    icon: Icons.edit_outlined,
                    tooltip: 'Modifier',
                    onPressed: () => _openEditDialog(overview.store),
                  ),
                  RowAction(
                    icon: Icons.delete_outline,
                    tooltip: 'Supprimer',
                    destructive: true,
                    onPressed: () => _deleteStore(overview.store),
                  ),
                ],
              ),
            ],
          ),
      ],
    );
  }
}

// Below this content width, the details sidebar moves below the table
// instead of sitting beside it.
const double _detailsBreakpoint = 760;

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
