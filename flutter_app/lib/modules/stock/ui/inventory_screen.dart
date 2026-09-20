import 'package:flutter/material.dart';

import 'package:socogen/modules/stock/models/store.dart';
import 'package:socogen/shared/models/view_models.dart';
import 'package:socogen/modules/catalogue/services/catalogue_service.dart';
import 'package:socogen/modules/stock/services/stock_service.dart';
import 'package:socogen/modules/stock/repositories/store_repository.dart';
import 'package:socogen/core/events/data_refresh_bus.dart';
import 'package:socogen/modules/stock/services/inventory_service.dart';
import 'package:socogen/shared/ui/theme/app_breakpoints.dart';
import 'package:socogen/shared/ui/theme/app_colors.dart';
import 'package:socogen/shared/ui/theme/app_spacing.dart';
import 'package:socogen/shared/ui/theme/app_text_styles.dart';
import 'package:socogen/shared/ui/widgets/adaptive_table.dart';
import 'package:socogen/shared/ui/widgets/empty_state.dart';
import 'package:socogen/shared/ui/widgets/page_header.dart';
import 'package:socogen/shared/ui/widgets/product_autocomplete.dart';
import 'package:socogen/shared/ui/widgets/row_actions.dart';
import 'package:socogen/shared/ui/widgets/skeleton.dart';
import 'package:socogen/shared/ui/widgets/status_badge.dart';
import 'package:socogen/core/errors/messages.dart';

/// Physical inventory: count what the shelf actually holds, and let the
/// app post the difference as a corrective movement.
///
/// This is how a real stock is reconciled with its records, and the only
/// thing in the app that can *settle* a negative balance rather than
/// merely flag one.
///
/// A count session is a draft held in this screen's state: nothing is
/// written until "Valider l'inventaire". Articles absent from the list
/// are simply not counted -- never assumed to be zero, which on a
/// 400-article catalogue would be a catastrophic guess.
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryData {
  final List<ProductOverview> products;
  final List<Store> stores;

  const _InventoryData({required this.products, required this.stores});
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _catalogue = CatalogueService();
  final _stock = StockService();
  final _storeRepo = StoreRepository();
  final _inventory = InventoryService();

  late Future<_InventoryData> _future;

  /// The draft. One line per (article, magasin): recounting an article
  /// corrects its line rather than adding a second one for it.
  final List<InventoryCount> _counts = [];

  bool _posting = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_InventoryData> _load() async {
    final (products, stores) = await (
      _catalogue.listerArticles(),
      _storeRepo.getAllStores(),
    ).wait;
    return _InventoryData(products: products, stores: stores);
  }

  Future<void> _refresh() async {
    final future = _load();
    // Corps en bloc, pas en flèche : `() => _future = future` *retourne*
    // l'affectation, donc un Future, et Flutter refuse un callback de
    // setState qui en rend un. L'assertion ne tombe qu'en debug, mais le
    // rafraîchissement ne prenait effet dans aucun des deux modes.
    setState(() {
      _future = future;
    });
    await future;
  }

  void _addCount(InventoryCount count) {
    setState(() {
      final at = _counts.indexWhere(
        (c) => c.reference == count.reference && c.storeId == count.storeId,
      );
      if (at >= 0) {
        _counts[at] = count;
      } else {
        _counts.add(count);
      }
    });
  }

  void _removeCount(InventoryCount count) {
    setState(() => _counts.remove(count));
  }

  Future<void> _clearCounts() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Vider le comptage'),
        content: Text(
          '${_counts.length} ligne(s) comptée(s) seront abandonnées. '
          'Rien n\'a encore été enregistré.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Vider'),
          ),
        ],
      ),
    );
    if (confirmed == true) setState(_counts.clear);
  }

  Future<void> _validate() async {
    final surpluses = _counts.where((c) => c.variance > 0).length;
    final shortfalls = _counts.where((c) => c.variance < 0).length;
    final matching = _counts.length - surpluses - shortfalls;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Valider l\'inventaire'),
        content: Text(
          '${_counts.length} article(s) compté(s).\n\n'
          '• $surpluses excédent(s) : une entrée d\'ajustement sera '
          'enregistrée.\n'
          '• $shortfalls manquant(s) : une sortie d\'ajustement sera '
          'enregistrée.\n'
          '• $matching conforme(s) : aucun mouvement.\n\n'
          'Les mouvements d\'origine ne sont pas modifiés : la correction '
          's\'ajoute à l\'historique.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Valider'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _posting = true);
    try {
      final report = await _inventory.post(List.of(_counts));
      DataRefreshBus.instance.notifyChanged();
      if (!mounted) return;
      setState(_counts.clear);
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(report.summary),
          backgroundColor: report.problems.isEmpty ? null : AppColors.warning,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(messagePour(e, operation: "la validation de l'inventaire")),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = context.windowSize;
    return Column(
      children: [
        const PageHeader(
          title: 'Inventaire physique',
          subtitle: 'Compter le stock réel et régulariser les écarts',
        ),
        Expanded(
          child: FutureBuilder<_InventoryData>(
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
              return CustomScrollView(
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
                          _CountFormCard(
                            products: data.products,
                            stores: data.stores,
                            stockService: _stock,
                            onCounted: _addCount,
                          ),
                          if (_counts.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.lg),
                            _CountSummaryCard(
                              counts: _counts,
                              posting: _posting,
                              onValidate: _validate,
                              onClear: _clearCounts,
                            ),
                          ],
                          const SizedBox(height: AppSpacing.xl),
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'COMPTAGE EN COURS',
                                  style: AppTextStyles.sectionLabel,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Text(
                                '${_counts.length} ligne(s)',
                                style: AppTextStyles.captionMuted,
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.md),
                        ],
                      ),
                    ),
                  ),
                  if (_counts.isEmpty)
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        padding.left,
                        0,
                        padding.right,
                        padding.bottom,
                      ),
                      sliver: const SliverToBoxAdapter(
                        child: AppEmptyState(
                          icon: Icons.fact_check_outlined,
                          title: 'Aucun article compté',
                          message:
                              'Choisissez un magasin et un article, saisissez '
                              'la quantité réellement présente, puis ajoutez-la '
                              'au comptage. Les articles non comptés ne sont '
                              'pas modifiés.',
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        padding.left,
                        0,
                        padding.right,
                        padding.bottom,
                      ),
                      sliver: SliverAdaptiveTable(table: _table()),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  AdaptiveTable _table() {
    final short = context.showsShortProductList;
    return AdaptiveTable(
      columns: short
          ? const [
              AppColumn('DÉSIGNATION', flex: 20),
              AppColumn.number('COMPTÉ'),
              AppColumn.number('ÉCART'),
              AppColumn.actions(),
            ]
          : const [
              AppColumn('RÉFÉRENCE', flex: 12),
              AppColumn('DÉSIGNATION', flex: 22),
              AppColumn('MAGASIN', flex: 14),
              AppColumn.number('THÉORIQUE'),
              AppColumn.number('COMPTÉ'),
              AppColumn.number('ÉCART'),
              AppColumn.actions(),
            ],
      rows: [
        for (final count in _counts)
          AppRow(
            accent: count.variance == 0 ? null : varianceColor(count.variance),
            cells: short
                ? [
                    Cells.text(count.designation),
                    Cells.number(count.counted),
                    varianceCell(count.variance),
                    _removeAction(count),
                  ]
                : [
                    Cells.identifier(count.reference),
                    Cells.text(count.designation),
                    Cells.muted(count.storeName),
                    Cells.number(
                      count.theoretical,
                      color: AppColors.textSecondary,
                    ),
                    Cells.number(count.counted),
                    varianceCell(count.variance),
                    _removeAction(count),
                  ],
          ),
      ],
    );
  }

  Widget _removeAction(InventoryCount count) => RowActions(
        actions: [
          RowAction(
            icon: Icons.close,
            tooltip: 'Retirer du comptage',
            onPressed: () => _removeCount(count),
            destructive: true,
          ),
        ],
      );

  /// Green for a surplus, red for a shortfall: the same reading as
  /// everywhere else in the app, where red means stock is missing.
  static Color varianceColor(int variance) {
    if (variance > 0) return AppColors.success;
    if (variance < 0) return AppColors.error;
    return AppColors.textSecondary;
  }

  static Widget varianceCell(int variance) => Text(
        variance > 0 ? '+$variance' : '$variance',
        style: AppTextStyles.numericStrong.copyWith(
          color: varianceColor(variance),
        ),
      );
}

/// The count entry form: one article, in one magasin, at a time.
///
/// Deliberately not an editable grid over the whole catalogue. A phone
/// is read standing in an aisle, and a blank cell in such a grid is
/// ambiguous between "not counted" and "counted zero" -- the kind of
/// guess this project refuses to make.
class _CountFormCard extends StatefulWidget {
  final List<ProductOverview> products;
  final List<Store> stores;
  final StockService stockService;
  final ValueChanged<InventoryCount> onCounted;

  const _CountFormCard({
    required this.products,
    required this.stores,
    required this.stockService,
    required this.onCounted,
  });

  @override
  State<_CountFormCard> createState() => _CountFormCardState();
}

class _CountFormCardState extends State<_CountFormCard> {
  final _refController = TextEditingController();
  final _countedController = TextEditingController();

  ProductOverview? _product;
  int? _storeId;

  /// What the ledger says for the chosen (article, magasin), or null
  /// while nothing is chosen yet.
  int? _theoretical;
  bool _loadingTheoretical = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _storeId = widget.stores.isNotEmpty ? widget.stores.first.id : null;
  }

  @override
  void dispose() {
    _refController.dispose();
    _countedController.dispose();
    super.dispose();
  }

  Store? get _store => widget.stores.where((s) => s.id == _storeId).firstOrNull;

  Future<void> _refreshTheoretical() async {
    final product = _product;
    final storeId = _storeId;
    if (product == null || storeId == null) {
      setState(() => _theoretical = null);
      return;
    }
    setState(() => _loadingTheoretical = true);
    final balance = await widget.stockService.solde(
      reference: product.product.reference,
      magasinId: storeId,
    );
    if (!mounted) return;
    setState(() {
      _theoretical = balance;
      _loadingTheoretical = false;
    });
  }

  Future<void> _onProductSelected(ProductOverview product) async {
    setState(() => _product = product);
    await _refreshTheoretical();
  }

  Future<void> _onStoreChanged(int? storeId) async {
    setState(() => _storeId = storeId);
    await _refreshTheoretical();
  }

  void _add() {
    final product = _product;
    final store = _store;
    final counted = int.tryParse(_countedController.text.trim());

    if (product == null) {
      setState(() => _error = 'Sélectionnez un article.');
      return;
    }
    if (store == null) {
      setState(() => _error = 'Sélectionnez un magasin.');
      return;
    }
    if (counted == null || counted < 0) {
      setState(() => _error = 'Saisissez la quantité comptée (0 ou plus).');
      return;
    }

    widget.onCounted(InventoryCount(
      reference: product.product.reference,
      designation: product.product.designation,
      storeId: store.id,
      storeName: store.name,
      theoretical: _theoretical ?? 0,
      counted: counted,
    ));

    setState(() {
      _error = null;
      _product = null;
      _theoretical = null;
      _refController.clear();
      _countedController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theoretical = _theoretical;
    final counted = int.tryParse(_countedController.text.trim());
    final variance =
        (theoretical != null && counted != null) ? counted - theoretical : null;

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
          const Text('COMPTER UN ARTICLE', style: AppTextStyles.sectionLabel),
          const SizedBox(height: 16),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<int>(
                  initialValue: _storeId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Magasin *'),
                  items: widget.stores
                      .map((s) => DropdownMenuItem(
                            value: s.id,
                            child:
                                Text(s.name, overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: _onStoreChanged,
                ),
              ),
              SizedBox(
                width: 260,
                child: ProductAutocomplete(
                  products: widget.products,
                  controller: _refController,
                  onSelected: _onProductSelected,
                  labelText: 'Article *',
                ),
              ),
              SizedBox(
                width: 220,
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Désignation'),
                  child: Text(
                    _product?.product.designation ?? '—',
                    style: const TextStyle(color: AppColors.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              SizedBox(
                width: 150,
                child: InputDecorator(
                  decoration:
                      const InputDecoration(labelText: 'Stock théorique'),
                  child: Text(
                    _loadingTheoretical
                        ? '…'
                        : theoretical == null
                            ? '—'
                            : '$theoretical',
                    style: TextStyle(
                      color: theoretical == null
                          ? AppColors.textSecondary
                          : StockStatus.fromCurrent(theoretical).color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 150,
                child: TextField(
                  controller: _countedController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Quantité comptée *',
                    hintText: 'Ex : 42',
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _add(),
                ),
              ),
              SizedBox(
                width: 150,
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Écart'),
                  child: Text(
                    variance == null
                        ? '—'
                        : variance > 0
                            ? '+$variance'
                            : '$variance',
                    style: TextStyle(
                      color: variance == null
                          ? AppColors.textSecondary
                          : _InventoryScreenState.varianceColor(variance),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              _error!,
              style: const TextStyle(color: AppColors.error, fontSize: 12),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _add,
              icon: const Icon(Icons.playlist_add, size: 18),
              label: const Text('Ajouter au comptage'),
            ),
          ),
        ],
      ),
    );
  }
}

/// What the draft adds up to, and the two things that can be done with
/// it. Shown only once something has been counted.
class _CountSummaryCard extends StatelessWidget {
  final List<InventoryCount> counts;
  final bool posting;
  final VoidCallback onValidate;
  final VoidCallback onClear;

  const _CountSummaryCard({
    required this.counts,
    required this.posting,
    required this.onValidate,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final surpluses = counts.where((c) => c.variance > 0).length;
    final shortfalls = counts.where((c) => c.variance < 0).length;
    final matching = counts.length - surpluses - shortfalls;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      // Wrap, not Row: four tallies plus two French button labels do not
      // fit one line on a phone, and this project has shipped that
      // overflow before.
      child: Wrap(
        spacing: AppSpacing.lg,
        runSpacing: AppSpacing.md,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _Tally(
            label: 'comptés',
            value: counts.length,
            color: AppColors.textPrimary,
          ),
          _Tally(label: 'excédents', value: surpluses, color: AppColors.success),
          _Tally(label: 'manquants', value: shortfalls, color: AppColors.error),
          _Tally(
            label: 'conformes',
            value: matching,
            color: AppColors.textSecondary,
          ),
          TextButton(
            onPressed: posting ? null : onClear,
            child: const Text('Vider'),
          ),
          FilledButton.icon(
            onPressed: posting ? null : onValidate,
            icon: posting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check, size: 18),
            label: const Text('Valider l\'inventaire'),
          ),
        ],
      ),
    );
  }
}

class _Tally extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _Tally({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$value',
          style: AppTextStyles.numericStrong.copyWith(color: color),
        ),
        Text(label, style: AppTextStyles.captionMuted),
      ],
    );
  }
}
