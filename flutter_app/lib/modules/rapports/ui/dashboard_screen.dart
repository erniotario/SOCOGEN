import 'dart:async';

import 'package:flutter/material.dart';

import 'package:socogen/shared/models/view_models.dart';
import 'package:socogen/modules/catalogue/services/catalogue_service.dart';
import 'package:socogen/modules/stock/repositories/stock_entry_repository.dart';
import 'package:socogen/modules/stock/repositories/stock_output_repository.dart';
import 'package:socogen/core/money/montant.dart';
import 'package:socogen/modules/parametres/services/parametres_service.dart';
import 'package:socogen/modules/stock/services/stock_service.dart';
import 'package:socogen/modules/stock/services/vente_service.dart';
import 'package:socogen/modules/stock/repositories/store_repository.dart';
import 'package:socogen/core/events/data_refresh_bus.dart';
import 'package:socogen/shared/ui/theme/app_breakpoints.dart';
import 'package:socogen/shared/ui/theme/app_colors.dart';
import 'package:socogen/shared/ui/theme/app_spacing.dart';
import 'package:socogen/shared/ui/theme/app_text_styles.dart';
import 'package:socogen/shared/ui/widgets/adaptive_table.dart';
import 'package:socogen/shared/ui/widgets/empty_state.dart';
import 'package:socogen/shared/ui/widgets/kpi_card.dart';
import 'package:socogen/shared/ui/widgets/page_header.dart';
import 'package:socogen/shared/ui/widgets/skeleton.dart';
import 'package:socogen/shared/ui/widgets/status_badge.dart';

class _DashboardData {
  final List<ProductOverview> products;
  final int storeCount;
  final int totalEntries;
  final int totalOutputs;

  /// Ce que la journée a encaissé, et ce que le stock vaut.
  ///
  /// Les deux ne couvrent que les lignes et les articles qui portent un
  /// prix : c'est pourquoi le nombre d'articles non valorisés voyage
  /// avec eux. Un total présenté seul laisserait croire qu'il couvre
  /// tout le catalogue.
  final Montant ventesDuJour;
  final Montant valeurStock;
  final int articlesSansPrix;

  const _DashboardData({
    required this.products,
    required this.storeCount,
    required this.totalEntries,
    required this.totalOutputs,
    required this.ventesDuJour,
    required this.valeurStock,
    required this.articlesSansPrix,
  });
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _catalogue = CatalogueService();
  final _storeRepo = StoreRepository();
  final _entryRepo = StockEntryRepository();
  final _outputRepo = StockOutputRepository();
  final _stock = StockService();
  final _ventes = VenteService();
  final _parametres = ParametresService();

  // Holding the resolved data (rather than a Future) keeps the previous
  // contents on screen while a refresh runs, so nothing flashes.
  _DashboardData? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
    DataRefreshBus.instance.addListener(_refresh);
  }

  @override
  void dispose() {
    DataRefreshBus.instance.removeListener(_refresh);
    super.dispose();
  }

  Future<_DashboardData> _load() async {
    final aujourdhui = _iso(DateTime.now());
    final (products, stores, totalEntries, totalOutputs, devise, ventes, stock) =
        await (
      _catalogue.listerArticles(),
      _storeRepo.getAllStores(),
      _entryRepo.getTotalQuantity(),
      _outputRepo.getTotalQuantity(),
      _parametres.devise(),
      _ventes.chiffreDAffaires(du: aujourdhui, au: aujourdhui),
      _stock.valeurDuStock(),
    ).wait;
    return _DashboardData(
      products: products,
      storeCount: stores.length,
      totalEntries: totalEntries,
      totalOutputs: totalOutputs,
      ventesDuJour: Montant(ventes.total, devise: devise),
      valeurStock: Montant(stock.valeur, devise: devise),
      articlesSansPrix: stock.articlesSansPrix,
    );
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> _refresh() async {
    try {
      final data = await _load();
      if (!mounted) return;
      setState(() {
        _data = data;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = context.windowSize;
    final padding = AppSpacing.pagePadding(size);

    return Column(
      children: [
        PageHeader(
          title: 'Tableau de bord',
          subtitle: "Vue d'ensemble du stock",
          actions: [
            if (!size.isCompact)
              IconButton(
                tooltip: 'Actualiser',
                onPressed: _refresh,
                icon: const Icon(Icons.refresh, size: 18),
              ),
          ],
        ),
        Expanded(child: _buildBody(padding)),
      ],
    );
  }

  Widget _buildBody(EdgeInsets padding) {
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
            SizedBox(height: AppSpacing.xl),
            Expanded(child: SkeletonList()),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppColors.accentLight,
      backgroundColor: AppColors.surface,
      child: Padding(
        padding: padding,
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
              KpiCard(
                icon: Icons.point_of_sale_outlined,
                label: "Ventes aujourd'hui",
                value: data.ventesDuJour.formate(),
                color: AppColors.success,
              ),
              KpiCard(
                icon: Icons.savings_outlined,
                label: 'Valeur du stock',
                value: data.valeurStock.formate(),
                color: AppColors.accentLight,
              ),
            ]),
            if (data.articlesSansPrix > 0) ...[
              const SizedBox(height: AppSpacing.sm),
              // Dit, et non tu : une valeur calculée sur une partie du
              // catalogue présentée seule laisserait croire qu'elle les
              // couvre tous.
              _ReserveSurLaValeur(articlesSansPrix: data.articlesSansPrix),
            ],
            const SizedBox(height: AppSpacing.xl),
            const Text(
              'STOCK ACTUEL PAR PRODUIT',
              style: AppTextStyles.sectionLabel,
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(child: _productTable(context, data.products)),
          ],
        ),
      ),
    );
  }

  Widget _productTable(BuildContext context, List<ProductOverview> rows) {
    final short = context.showsShortProductList;
    return AdaptiveTable(
      // Three columns need far less room before they are worth
      // scrolling sideways for.
      minTableWidth: short ? 420 : 720,
      columns: short
          ? const [
              AppColumn('DÉSIGNATION', flex: 26),
              AppColumn('MAGASIN', flex: 18),
              AppColumn.number('STOCK ACTUEL', flex: 12),
            ]
          : const [
              AppColumn('RÉFÉRENCE', flex: 12),
              AppColumn('DÉSIGNATION', flex: 22),
              AppColumn('UNITÉ', flex: 7),
              AppColumn.number('STOCK INITIAL', flex: 11),
              AppColumn.number('ENTRÉES', flex: 10),
              AppColumn.number('SORTIES', flex: 10),
              AppColumn.number('STOCK ACTUEL', flex: 11),
            ],
      empty: const AppEmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'Aucun produit',
        message: 'Ajoutez des produits depuis la page Produits pour voir '
            'leur stock apparaître ici.',
      ),
      rows: [
        for (final overview in rows)
          AppRow(
            cells: short
                ? [
                    Cells.text(overview.product.designation),
                    Cells.muted(overview.storeNames.isEmpty
                        ? '—'
                        : overview.storeNames),
                    Cells.number(
                      overview.currentStock,
                      color: overview.status.color,
                      strong: true,
                      size: 14,
                    ),
                  ]
                : [
                    Cells.identifier(overview.product.reference),
                    Cells.text(overview.product.designation),
                    Cells.muted(overview.product.unit),
                    Cells.number(
                      overview.initialStock,
                      color: AppColors.textSecondary,
                    ),
                    Cells.number(
                      '+ ${overview.entriesTotal}',
                      color: AppColors.success,
                      strong: true,
                    ),
                    Cells.number(
                      '− ${overview.outputsTotal}',
                      color: AppColors.error,
                      strong: true,
                    ),
                    Cells.number(
                      overview.currentStock,
                      color: overview.status.color,
                      strong: true,
                      size: 14,
                    ),
                  ],
          ),
      ],
    );
  }
}


/// Ce que la valeur du stock ne couvre pas.
///
/// Un article sans prix d'achat a un stock réel et une valeur inconnue.
/// Le compter pour zéro donnerait un total plus petit que la vérité, et
/// le taire donnerait un total qui a l'air complet — le second est pire.
class _ReserveSurLaValeur extends StatelessWidget {
  final int articlesSansPrix;

  const _ReserveSurLaValeur({required this.articlesSansPrix});

  @override
  Widget build(BuildContext context) {
    final pluriel = articlesSansPrix > 1 ? 's' : '';
    return Row(
      children: [
        const Icon(Icons.info_outline, size: 14, color: AppColors.textMuted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Valeur hors $articlesSansPrix article$pluriel sans prix '
            "d'achat : leur stock est réel, sa valeur est inconnue.",
            style: AppTextStyles.bodyMuted,
          ),
        ),
      ],
    );
  }
}
