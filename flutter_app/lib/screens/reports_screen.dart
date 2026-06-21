import 'dart:async';

import 'package:flutter/material.dart';

import '../data/models/store.dart';
import '../data/models/view_models.dart';
import '../data/repositories/report_repository.dart';
import '../data/repositories/store_repository.dart';
import '../services/data_refresh_bus.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/kpi_card.dart';
import '../widgets/page_header.dart';
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

  const _ReportsData({required this.rows, required this.stores, required this.counts});
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
    _search = value;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), _load);
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Column(
      children: [
        const PageHeader(
          title: 'Rapport des Produits',
          subtitle: 'État des stocks par produit et par magasin',
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
                      child: ListView(
                        padding: const EdgeInsets.all(24),
                        children: [
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
                          const SizedBox(height: 16),
                          _FiltersPanel(
                            searchController: _searchController,
                            stores: data.stores,
                            storeId: _storeId,
                            status: _status,
                            onSearchChanged: _onSearchChanged,
                            onStoreChanged: (value) {
                              setState(() => _storeId = value);
                              _reapply();
                            },
                            onStatusChanged: (value) {
                              setState(() => _status = value);
                              _reapply();
                            },
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              const Text('DÉTAIL PAR PRODUIT', style: AppTextStyles.sectionLabel),
                              const Spacer(),
                              Text('${data.rows.length} produit(s) affiché(s)', style: AppTextStyles.bodyMuted),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _ReportTable(rows: data.rows),
                        ],
                      ),
                    ),
        ),
      ],
    );
  }
}

class _FiltersPanel extends StatelessWidget {
  final TextEditingController searchController;
  final List<Store> stores;
  final int? storeId;
  final StockStatus? status;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<int?> onStoreChanged;
  final ValueChanged<StockStatus?> onStatusChanged;

  const _FiltersPanel({
    required this.searchController,
    required this.stores,
    required this.storeId,
    required this.status,
    required this.onSearchChanged,
    required this.onStoreChanged,
    required this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.elevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Wrap(
        spacing: 14,
        runSpacing: 14,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 260,
            child: TextField(
              controller: searchController,
              decoration: const InputDecoration(
                labelText: 'Rechercher',
                prefixIcon: Icon(Icons.search, size: 20),
                hintText: 'Référence, désignation…',
                isDense: true,
              ),
              onChanged: onSearchChanged,
            ),
          ),
          SizedBox(
            width: 180,
            child: DropdownButtonFormField<int?>(
              initialValue: storeId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Magasin'),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('Tous les magasins')),
                ...stores.map((s) => DropdownMenuItem<int?>(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis))),
              ],
              onChanged: onStoreChanged,
            ),
          ),
          SizedBox(
            width: 170,
            child: DropdownButtonFormField<StockStatus?>(
              initialValue: status,
              decoration: const InputDecoration(labelText: 'Statut'),
              items: const [
                DropdownMenuItem<StockStatus?>(value: null, child: Text('Tous')),
                DropdownMenuItem<StockStatus?>(value: StockStatus.enStock, child: Text('En stock')),
                DropdownMenuItem<StockStatus?>(value: StockStatus.stockFaible, child: Text('Stock faible')),
                DropdownMenuItem<StockStatus?>(value: StockStatus.rupture, child: Text('Rupture')),
              ],
              onChanged: onStatusChanged,
            ),
          ),
        ],
      ),
    );
  }
}

// Relative flex weights for the report table columns. Using a flexible
// Row instead of fixed pixel widths means the table always fits the
// available width (no horizontal scrollbar cutting off the STATUT column).
const int _colReference = 11;
const int _colDesignation = 22;
const int _colUnit = 7;
const int _colStore = 13;
const int _colInitial = 11;
const int _colMove = 9;
const int _colCurrent = 11;
const int _colStatus = 12;
const double _cellPadding = 10;

class _ReportTable extends StatelessWidget {
  final List<ReportRow> rows;

  const _ReportTable({required this.rows});

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
                  child: Center(child: Text('Aucun produit', style: AppTextStyles.bodyMuted)),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: rows.length,
                  itemBuilder: (context, index) => _ReportRowWidget(row: rows[index], alternate: index.isOdd),
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
      child: const Row(
        children: [
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
            flex: _colStore,
            child: Text('MAGASIN', style: AppTextStyles.tableHeader, overflow: TextOverflow.ellipsis),
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
            flex: _colMove,
            child: Text(
              'ENTRÉES',
              style: AppTextStyles.tableHeader,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: _colMove,
            child: Text(
              'SORTIES',
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
            flex: _colStatus,
            child: Text(
              'STATUT',
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

class _ReportRowWidget extends StatelessWidget {
  final ReportRow row;
  final bool alternate;

  const _ReportRowWidget({required this.row, required this.alternate});

  @override
  Widget build(BuildContext context) {
    final isRupture = row.status == StockStatus.rupture;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: _cellPadding),
      decoration: BoxDecoration(
        color: isRupture
            ? AppColors.errorBg.withValues(alpha: 0.45)
            : (alternate ? AppColors.bg : AppColors.surface),
        border: const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: _colReference,
            child: Text(
              row.reference,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.accentLight),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: _colDesignation,
            child: Text(row.designation, style: AppTextStyles.tableCell, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            flex: _colUnit,
            child: Text(row.unit, style: AppTextStyles.tableCell, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            flex: _colStore,
            child: Text(row.storeName, style: AppTextStyles.bodyMuted, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            flex: _colInitial,
            child: Text(
              '${row.initialStock}',
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            flex: _colMove,
            child: Text(
              '+ ${row.entries}',
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.success),
            ),
          ),
          Expanded(
            flex: _colMove,
            child: Text(
              '− ${row.outputs}',
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.error),
            ),
          ),
          Expanded(
            flex: _colCurrent,
            child: Text(
              '${row.current}',
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: row.status.color),
            ),
          ),
          Expanded(
            flex: _colStatus,
            child: Center(child: StatusBadge(status: row.status)),
          ),
        ],
      ),
    );
  }
}
