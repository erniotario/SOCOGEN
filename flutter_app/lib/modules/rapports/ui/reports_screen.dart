import 'dart:async';

import 'package:flutter/material.dart';

import 'package:socogen/modules/stock/models/store.dart';
import 'package:socogen/shared/models/view_models.dart';
import 'package:socogen/modules/rapports/repositories/report_repository.dart';
import 'package:socogen/modules/stock/repositories/store_repository.dart';
import 'package:socogen/core/events/data_refresh_bus.dart';
import 'package:socogen/shared/ui/theme/app_breakpoints.dart';
import 'package:socogen/shared/ui/theme/app_colors.dart';
import 'package:socogen/shared/ui/theme/app_spacing.dart';
import 'package:socogen/shared/ui/theme/app_text_styles.dart';
import 'package:socogen/shared/ui/widgets/adaptive_table.dart';
import 'package:socogen/shared/ui/widgets/empty_state.dart';
import 'package:socogen/shared/ui/widgets/filter_bar.dart';
import 'package:socogen/shared/ui/widgets/kpi_card.dart';
import 'package:socogen/shared/ui/widgets/page_header.dart';
import 'package:socogen/shared/ui/widgets/skeleton.dart';
import 'package:socogen/shared/ui/widgets/status_badge.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

typedef _StatusCounts =
    ({int total, int enStock, int stockFaible, int rupture, int negatif});

class _ReportsData {
  final List<ReportRow> rows;
  final List<Store> stores;
  final _StatusCounts counts;

  const _ReportsData({
    required this.rows,
    required this.stores,
    required this.counts,
  });
}

class _ReportsScreenState extends State<ReportsScreen> {
  final _reportRepo = ReportRepository();
  final _storeRepo = StoreRepository();
  final _searchController = TextEditingController();

  _ReportsData? _data;
  String? _error;

  String _search = '';
  int? _storeId;
  StockStatus? _status;
  Timer? _searchDebounce;

  /// Set in [build] from the window size, read by [_buildBody].
  bool _scrollWholePage = false;

  bool get _hasFilters =>
      _search.isNotEmpty || _storeId != null || _status != null;

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

  Future<void> _load() async {
    try {
      final (rows, stores, counts) = await (
        _reportRepo.getReportRows(
          search: _search.isEmpty ? null : _search,
          storeId: _storeId,
          status: _status,
        ),
        _storeRepo.getAllStores(),
        _reportRepo.getStatusCounts(),
      ).wait;
      if (!mounted) return;
      setState(() {
        _data = _ReportsData(rows: rows, stores: stores, counts: counts);
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  Future<void> _refresh() => _load();

  void _reapply() => _load();

  void _onSearchChanged(String value) {
    setState(() => _search = value);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), _load);
  }

  void _showNegativeOnly() {
    setState(() => _status = StockStatus.stockNegatif);
    _reapply();
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _search = '';
      _storeId = null;
      _status = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final size = context.windowSize;
    _scrollWholePage = size.isCompact || context.isShort;
    return Column(
      children: [
        PageHeader(
          title: 'Rapport des Produits',
          subtitle: 'État des stocks par produit et par magasin',
          actions: [
            if (!size.isCompact)
              IconButton(
                tooltip: 'Actualiser',
                onPressed: _refresh,
                icon: const Icon(Icons.refresh, size: 18),
              ),
          ],
        ),
        Expanded(child: _buildBody(size)),
      ],
    );
  }

  Widget _buildBody(WindowSize size) {
    final padding = AppSpacing.pagePadding(size);

    if (_error != null) {
      return AppErrorState(message: _error!, onRetry: _refresh);
    }

    final data = _data;
    if (data == null) {
      return Padding(
        padding: padding,
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonKpiRow(),
            SizedBox(height: AppSpacing.lg),
            Expanded(child: SkeletonList()),
          ],
        ),
      );
    }

    final header = <Widget>[
      KpiRow(cards: [
        KpiCard(
          icon: Icons.inventory_2_outlined,
          label: 'Produits total',
          value: '${data.counts.total}',
          color: AppColors.accentLight,
        ),
        KpiCard(
          icon: Icons.check_circle_outline,
          label: 'En stock',
          value: '${data.counts.enStock}',
          color: AppColors.success,
        ),
        KpiCard(
          icon: Icons.warning_amber_outlined,
          label: 'Stock faible',
          value: '${data.counts.stockFaible}',
          color: AppColors.warning,
        ),
        KpiCard(
          icon: Icons.error_outline,
          label: 'Rupture de stock',
          value: '${data.counts.rupture}',
          color: AppColors.error,
        ),
      ]),
      if (data.counts.negatif > 0) ...[
        const SizedBox(height: AppSpacing.lg),
        _NegativeStockBanner(
          count: data.counts.negatif,
          showing: _status == StockStatus.stockNegatif,
          onShow: _showNegativeOnly,
        ),
      ],
      const SizedBox(height: AppSpacing.lg),
      _buildFilters(data.stores),
      const SizedBox(height: AppSpacing.lg),
      Row(
        children: [
          // The count is short and always worth reading; the label is
          // the half that gives way on a narrow phone.
          const Expanded(
            child: Text(
              'DÉTAIL PAR PRODUIT',
              style: AppTextStyles.sectionLabel,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '${data.rows.length} produit(s)',
            style: AppTextStyles.captionMuted,
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.sm),
    ];

    // On a phone -- and in any window too short to hold the summary,
    // filters and a usable table at once -- the whole page scrolls as one
    // column; on roomier windows the summary and filters stay put while
    // the table scrolls under its own sticky header.
    if (_scrollWholePage) {
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
                  children: header,
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
              sliver: SliverAdaptiveTable(
                table: _table(data.rows, shrinkWrap: false),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...header,
          Expanded(child: _table(data.rows, shrinkWrap: false)),
        ],
      ),
    );
  }

  Widget _buildFilters(List<Store> stores) {
    return FilterBar(
      onClear: _hasFilters ? _clearFilters : null,
      fields: [
        FilterField(
          flex: 3,
          child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              labelText: 'Rechercher',
              prefixIcon: Icon(Icons.search, size: 20),
              hintText: 'Référence, désignation…',
            ),
            onChanged: _onSearchChanged,
          ),
        ),
        FilterField(
          flex: 2,
          child: DropdownButtonFormField<int?>(
            initialValue: _storeId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Magasin'),
            items: [
              const DropdownMenuItem<int?>(
                value: null,
                child: Text('Tous les magasins'),
              ),
              ...stores.map(
                (s) => DropdownMenuItem<int?>(
                  value: s.id,
                  child: Text(s.name, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
            onChanged: (value) {
              setState(() => _storeId = value);
              _reapply();
            },
          ),
        ),
        FilterField(
          flex: 2,
          child: DropdownButtonFormField<StockStatus?>(
            initialValue: _status,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Statut'),
            items: const [
              DropdownMenuItem<StockStatus?>(value: null, child: Text('Tous')),
              DropdownMenuItem<StockStatus?>(
                value: StockStatus.enStock,
                child: Text('En stock'),
              ),
              DropdownMenuItem<StockStatus?>(
                value: StockStatus.stockFaible,
                child: Text('Stock faible'),
              ),
              DropdownMenuItem<StockStatus?>(
                value: StockStatus.rupture,
                child: Text('Rupture'),
              ),
              DropdownMenuItem<StockStatus?>(
                value: StockStatus.stockNegatif,
                child: Text('Stock négatif'),
              ),
            ],
            onChanged: (value) {
              setState(() => _status = value);
              _reapply();
            },
          ),
        ),
      ],
    );
  }

  AdaptiveTable _table(List<ReportRow> rows, {required bool shrinkWrap}) {
    final short = context.showsShortProductList;
    return AdaptiveTable(
      shrinkWrap: shrinkWrap,
      minTableWidth: short ? 420 : 820,
      columns: short
          ? const [
              AppColumn('DÉSIGNATION', flex: 26),
              AppColumn('MAGASIN', flex: 18),
              AppColumn.number('STOCK ACTUEL', flex: 12),
            ]
          : const [
              AppColumn('RÉFÉRENCE', flex: 11),
              AppColumn('DÉSIGNATION', flex: 22),
              AppColumn('UNITÉ', flex: 7),
              AppColumn('MAGASIN', flex: 13),
              AppColumn.number('STOCK INITIAL', flex: 11),
              AppColumn.number('ENTRÉES', flex: 9),
              AppColumn.number('SORTIES', flex: 9),
              AppColumn.number('STOCK ACTUEL', flex: 11),
              AppColumn('STATUT', flex: 12, align: Alignment.center),
            ],
      empty: AppEmptyState(
        icon: _hasFilters ? Icons.filter_alt_off_outlined : Icons.bar_chart,
        title: _hasFilters ? 'Aucun résultat' : 'Aucun produit',
        message: _hasFilters
            ? 'Aucun produit ne correspond aux filtres appliqués.'
            : 'Le rapport se remplira dès que des produits seront créés.',
        action: _hasFilters
            ? OutlinedButton.icon(
                onPressed: _clearFilters,
                icon: const Icon(Icons.close, size: 16),
                label: const Text('Effacer les filtres'),
              )
            : null,
      ),
      rows: [
        for (final row in rows)
          AppRow(
            accent: row.status.isDepleted ? row.status.color : null,
            // The status badge goes with the columns it stood next to;
            // the stock figure is still tinted by it, so a rupture is
            // as visible on three columns as on nine.
            cells: short
                ? [
                    Cells.text(row.designation),
                    Cells.muted(row.storeName),
                    Cells.number(
                      row.current,
                      color: row.status.color,
                      strong: true,
                      size: 14,
                    ),
                  ]
                : [
                    Cells.identifier(row.reference),
                    Cells.text(row.designation),
                    Cells.muted(row.unit),
                    Cells.muted(row.storeName),
                    Cells.number(row.initialStock,
                        color: AppColors.textSecondary),
                    Cells.number('+ ${row.entries}',
                        color: AppColors.success, strong: true),
                    Cells.number('− ${row.outputs}',
                        color: AppColors.error, strong: true),
                    Cells.number(
                      row.current,
                      color: row.status.color,
                      strong: true,
                      size: 14,
                    ),
                    StatusBadge(status: row.status),
                  ],
          ),
      ],
    );
  }
}

/// Raised above the Rapports table when the ledger holds a stock below
/// zero. Such a figure is not a low stock but an impossible one -- a
/// sortie recorded that never happened, or an entrée never entered --
/// and it used to be indistinguishable from the hundreds of articles
/// legitimately sitting at zero. The button narrows the table down to
/// exactly those rows, so the list to settle is one tap away.
class _NegativeStockBanner extends StatelessWidget {
  final int count;

  /// True once the table is already filtered to these rows, in which
  /// case the button is dropped rather than offering a filter that is
  /// already applied; the banner itself stays, as the count is still
  /// worth reading.
  final bool showing;
  final VoidCallback onShow;

  const _NegativeStockBanner({
    required this.count,
    required this.showing,
    required this.onShow,
  });

  @override
  Widget build(BuildContext context) {
    final plural = count > 1 ? 's' : '';
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.anomalyBg,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.anomaly.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(
            Icons.report_problem_outlined,
            size: 16,
            color: AppColors.anomaly,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              '$count ligne$plural de stock en négatif — '
              'un mouvement manque ou est en trop. À régulariser.',
              style: const TextStyle(fontSize: 12, color: AppColors.anomaly),
            ),
          ),
          if (!showing) ...[
            const SizedBox(width: AppSpacing.sm),
            TextButton(
              onPressed: onShow,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.anomaly,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Afficher'),
            ),
          ],
        ],
      ),
    );
  }
}
