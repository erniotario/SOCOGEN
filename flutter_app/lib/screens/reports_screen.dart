import 'dart:async';

import 'package:flutter/material.dart';

import '../data/models/store.dart';
import '../data/models/view_models.dart';
import '../data/repositories/report_repository.dart';
import '../data/repositories/store_repository.dart';
import '../services/data_refresh_bus.dart';
import '../theme/app_breakpoints.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../widgets/adaptive_table.dart';
import '../widgets/empty_state.dart';
import '../widgets/filter_bar.dart';
import '../widgets/kpi_card.dart';
import '../widgets/page_header.dart';
import '../widgets/skeleton.dart';
import '../widgets/status_badge.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

typedef _StatusCounts = ({int total, int enStock, int stockFaible, int rupture});

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
      final rows = await _reportRepo.getReportRows(
        search: _search.isEmpty ? null : _search,
        storeId: _storeId,
        status: _status,
      );
      final stores = await _storeRepo.getAllStores();
      final counts = await _reportRepo.getStatusCounts();
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
      const SizedBox(height: AppSpacing.lg),
      _buildFilters(data.stores),
      const SizedBox(height: AppSpacing.lg),
      Row(
        children: [
          const Text('DÉTAIL PAR PRODUIT', style: AppTextStyles.sectionLabel),
          const Spacer(),
          Text(
            '${data.rows.length} produit(s)',
            style: AppTextStyles.captionMuted,
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.sm),
    ];

    // On a phone the whole page scrolls as one column; on wider windows
    // the summary and filters stay put while the table scrolls under its
    // own sticky header.
    if (size.isCompact) {
      return RefreshIndicator(
        onRefresh: _refresh,
        color: AppColors.accentLight,
        backgroundColor: AppColors.surface,
        child: ListView(
          padding: padding,
          children: [...header, _table(data.rows, shrinkWrap: true)],
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

  Widget _table(List<ReportRow> rows, {required bool shrinkWrap}) {
    return AdaptiveTable(
      shrinkWrap: shrinkWrap,
      minTableWidth: 820,
      columns: const [
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
            accent: row.status == StockStatus.rupture ? AppColors.error : null,
            cells: [
              Cells.identifier(row.reference),
              Cells.text(row.designation),
              Cells.muted(row.unit),
              Cells.muted(row.storeName),
              Cells.number(row.initialStock, color: AppColors.textSecondary),
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
