import 'package:flutter/material.dart';

import '../data/models/view_models.dart';
import '../data/repositories/product_repository.dart';
import '../data/repositories/stock_entry_repository.dart';
import '../data/repositories/stock_output_repository.dart';
import '../data/repositories/store_repository.dart';
import '../services/data_refresh_bus.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/kpi_card.dart';
import '../widgets/page_header.dart';
import '../widgets/status_badge.dart';

class _DashboardData {
  final List<ProductOverview> products;
  final int storeCount;
  final int totalEntries;
  final int totalOutputs;

  const _DashboardData({
    required this.products,
    required this.storeCount,
    required this.totalEntries,
    required this.totalOutputs,
  });
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _productRepo = ProductRepository();
  final _storeRepo = StoreRepository();
  final _entryRepo = StockEntryRepository();
  final _outputRepo = StockOutputRepository();

  late Future<_DashboardData> _future;

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

  Future<_DashboardData> _load() async {
    final products = await _productRepo.getProductOverviews();
    final stores = await _storeRepo.getAllStores();
    final totalEntries = await _entryRepo.getTotalQuantity();
    final totalOutputs = await _outputRepo.getTotalQuantity();
    return _DashboardData(
      products: products,
      storeCount: stores.length,
      totalEntries: totalEntries,
      totalOutputs: totalOutputs,
    );
  }

  Future<void> _refresh() async {
    final data = await _load();
    if (!mounted) return;
    setState(() {
      _future = Future.value(data);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const PageHeader(
          title: 'Tableau de bord',
          subtitle: "Vue d'ensemble du stock",
        ),
        Expanded(
          child: FutureBuilder<_DashboardData>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    'Erreur de chargement: ${snapshot.error}',
                    style: const TextStyle(color: AppColors.error),
                  ),
                );
              }
              final data = snapshot.data!;
              return RefreshIndicator(
                onRefresh: _refresh,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      KpiRow(cards: [
                        KpiCard(
                          icon: Icons.inventory_2_outlined,
                          label: 'Produits',
                          value: '${data.products.length}',
                          color: AppColors.accentLight,
                        ),
                        KpiCard(
                          icon: Icons.call_received,
                          label: 'Entrées totales',
                          value: '${data.totalEntries}',
                          color: AppColors.success,
                        ),
                        KpiCard(
                          icon: Icons.call_made,
                          label: 'Sorties totales',
                          value: '${data.totalOutputs}',
                          color: AppColors.error,
                        ),
                        KpiCard(
                          icon: Icons.store_outlined,
                          label: 'Magasins',
                          value: '${data.storeCount}',
                          color: AppColors.warning,
                        ),
                      ]),
                      const SizedBox(height: 20),
                      const Text('STOCK ACTUEL PAR PRODUIT', style: AppTextStyles.sectionLabel),
                      const SizedBox(height: 10),
                      Expanded(child: _ProductTable(rows: data.products)),
                    ],
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

// Relative flex weights for the dashboard product table columns. Using a
// flexible Row instead of fixed pixel widths means the table always fits
// the available width, even on narrow phone screens in portrait mode.
const int _colReference = 12;
const int _colDesignation = 22;
const int _colUnit = 7;
const int _colInitial = 11;
const int _colEntries = 10;
const int _colOutputs = 10;
const int _colCurrent = 11;
const double _cellPadding = 10;

class _ProductTable extends StatelessWidget {
  final List<ProductOverview> rows;

  const _ProductTable({required this.rows});

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
                ? const Center(
                    child: Text('Aucun produit', style: AppTextStyles.bodyMuted),
                  )
                : ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (context, index) => _ProductRow(
                      overview: rows[index],
                      alternate: index.isOdd,
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
            flex: _colInitial,
            child: Text(
              'STOCK INITIAL',
              style: AppTextStyles.tableHeader,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: _colEntries,
            child: Text(
              'ENTRÉES',
              style: AppTextStyles.tableHeader,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: _colOutputs,
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
        ],
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  final ProductOverview overview;
  final bool alternate;

  const _ProductRow({required this.overview, required this.alternate});

  @override
  Widget build(BuildContext context) {
    final product = overview.product;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: _cellPadding),
      decoration: BoxDecoration(
        color: alternate ? AppColors.bg : AppColors.surface,
        border: const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: _colReference,
            child: Text(
              product.reference,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.accentLight,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: _colDesignation,
            child: Text(
              product.designation,
              style: AppTextStyles.tableCell,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: _colUnit,
            child: Text(product.unit, style: AppTextStyles.tableCell, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            flex: _colInitial,
            child: Text(
              '${overview.initialStock}',
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            flex: _colEntries,
            child: Text(
              '+ ${overview.entriesTotal}',
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.success,
              ),
            ),
          ),
          Expanded(
            flex: _colOutputs,
            child: Text(
              '− ${overview.outputsTotal}',
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.error,
              ),
            ),
          ),
          Expanded(
            flex: _colCurrent,
            child: Text(
              '${overview.currentStock}',
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: overview.status.color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
