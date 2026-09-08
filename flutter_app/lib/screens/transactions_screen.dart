import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../data/models/stock_entry.dart';
import '../data/models/stock_output.dart';
import '../data/models/store.dart';
import '../data/models/view_models.dart';
import '../data/repositories/product_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/stock_entry_repository.dart';
import '../data/repositories/stock_output_repository.dart';
import '../data/repositories/store_repository.dart';
import '../data/repositories/transaction_repository.dart';
import '../services/data_refresh_bus.dart';
import '../services/transactions_pdf_service.dart';
import '../theme/app_breakpoints.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../utils/formatters.dart';
import '../widgets/adaptive_table.dart';
import '../widgets/dialog_body.dart';
import '../widgets/empty_state.dart';
import '../widgets/kpi_card.dart';
import '../widgets/page_header.dart';
import '../widgets/row_actions.dart';
import '../widgets/skeleton.dart';
import '../widgets/status_badge.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsData {
  final List<TransactionRow> rows;
  final List<ProductOverview> products;
  final List<Store> stores;
  final StoreAvailability? storeAvailability;

  const _TransactionsData({required this.rows, required this.products, required this.stores, this.storeAvailability});
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final _transactionRepo = TransactionRepository();
  final _entryRepo = StockEntryRepository();
  final _outputRepo = StockOutputRepository();
  final _productRepo = ProductRepository();
  final _storeRepo = StoreRepository();
  final _settingsRepo = SettingsRepository();
  final _searchController = TextEditingController();

  _TransactionsData? _data;
  String? _error;

  /// True while a PDF report is being generated, so the export buttons
  /// can show progress and refuse a second run.
  bool _exporting = false;

  String? _reference;
  int? _storeId;
  TransactionType? _type;
  DateTime _dateFrom = DateTime(DateTime.now().year, 1, 1);
  DateTime _dateTo = DateTime.now();
  String _search = '';
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

  /// Refreshes this screen and signals every other screen to reload its
  /// own data (e.g. product stock totals shown elsewhere need updating).
  void _onChanged() {
    _refresh();
    DataRefreshBus.instance.notifyChanged();
  }

  Future<void> _load() async {
    try {
      final (rows, products, stores) = await (
        _transactionRepo.getTransactions(
          reference: _reference,
          search: _search.isEmpty ? null : _search,
          storeId: _storeId,
          type: _type,
          dateFrom: DateFormat('yyyy-MM-dd').format(_dateFrom),
          dateTo: DateFormat('yyyy-MM-dd').format(_dateTo),
        ),
        _productRepo.getProductOverviews(),
        _storeRepo.getAllStores(),
      ).wait;

      StoreAvailability? storeAvailability;
      final ref = _reference;
      final sid = _storeId;
      if (ref != null && sid != null) {
        final overview = products.where((p) => p.product.reference == ref).firstOrNull;
        if (overview != null) {
          final avList = await _productRepo.getStoreAvailability(ref, overview.product.id);
          storeAvailability = avList.where((a) => a.storeId == sid).firstOrNull;
        }
      }

      if (!mounted) return;
      setState(() {
        _data = _TransactionsData(rows: rows, products: products, stores: stores, storeAvailability: storeAvailability);
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

  void _resetFilters() {
    setState(() {
      _reference = null;
      _storeId = null;
      _type = null;
      _dateFrom = DateTime(DateTime.now().year, 1, 1);
      _dateTo = DateTime.now();
      _search = '';
      _searchController.clear();
    });
    _load();
  }

  Future<void> _openEditDialog(TransactionRow row, List<Store> stores) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _TransactionFormDialog(row: row, stores: stores),
    );
    if (saved == true) _onChanged();
  }

  Future<void> _deleteTransaction(TransactionRow row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer la transaction'),
        content: const Text('Voulez-vous supprimer cette transaction ?'),
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
    if (row.type == TransactionType.entry) {
      await _entryRepo.delete(row.id);
    } else {
      await _outputRepo.delete(row.id);
    }
    _onChanged();
  }

  ProductOverview? _selectedOverview(List<ProductOverview> products) {
    final ref = _reference;
    if (ref == null) return null;
    for (final o in products) {
      if (o.product.reference == ref) return o;
    }
    return null;
  }

  Future<void> _exportPdf(_TransactionsData data) async {
    if (_reference == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sélectionnez un produit dans le filtre avant d\'exporter le rapport PDF.')),
      );
      return;
    }
    final ref = _reference!;
    await _exportPdfReport(data, defaultName: 'transactions_${ref}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf');
  }

  Future<void> _exportPdfAll(_TransactionsData data) async {
    await _exportPdfReport(data, defaultName: 'transactions_tous_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf');
  }

  /// Builds the report off the UI isolate, holding [_exporting] for the
  /// duration. Returns null when there is nothing to report or the build
  /// failed, having already told the operator why.
  Future<Uint8List?> _buildReport(_TransactionsData data) async {
    if (data.rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucune transaction à exporter.')),
      );
      return null;
    }

    // A few thousand movements take seconds to lay out even off the UI
    // thread, so say so rather than leaving a window that looks hung.
    setState(() => _exporting = true);
    try {
      final company = await _settingsRepo.getSettings();
      final overview = _selectedOverview(data.products);
      return await TransactionsPdfService.buildInBackground(
        TransactionsPdfRequest(
          productRef: _reference,
          transactions: data.rows,
          overview: overview,
          storeAvailability: data.storeAvailability,
          company: company,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur rapport PDF : $e')),
        );
      }
      return null;
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportPdfReport(_TransactionsData data, {required String defaultName}) async {
    final bytes = await _buildReport(data);
    if (bytes == null || !mounted) return;

    try {
      final savePath = await FilePicker.saveFile(
        dialogTitle: 'Enregistrer le rapport PDF',
        fileName: defaultName,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        bytes: bytes,
      );
      if (savePath == null) return;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rapport PDF enregistré : $savePath')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur export PDF : $e')),
      );
    }
  }

  /// Sends the same report straight to a printer through the system
  /// print dialog, so a paper copy needs no detour through a saved file.
  Future<void> _printReport(_TransactionsData data) async {
    final bytes = await _buildReport(data);
    if (bytes == null) return;

    final ref = _reference;
    final name = ref == null
        ? 'Rapport de transactions'
        : 'Rapport produit $ref';
    try {
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: name,
        format: PdfPageFormat.a4,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impression impossible : $e')),
      );
    }
  }

  /// Swaps the export button's icon for a spinner while a report is
  /// being generated.
  Widget _exportIcon(Widget icon) => _exporting
      ? const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      : icon;

  @override
  Widget build(BuildContext context) {
    final size = context.windowSize;
    final padding = AppSpacing.pagePadding(size);
    final data = _data;

    if (_error != null) {
      return Column(
        children: [
          const PageHeader(
            title: 'Transactions',
            subtitle: 'Historique des entrées et sorties',
          ),
          Expanded(child: AppErrorState(message: _error!, onRetry: _refresh)),
        ],
      );
    }
    if (data == null) {
      return Column(
        children: [
          const PageHeader(
            title: 'Transactions',
            subtitle: 'Historique des entrées et sorties',
          ),
          Expanded(
            child: Padding(padding: padding, child: const SkeletonList()),
          ),
        ],
      );
    }

    final overview = _selectedOverview(data.products);
    return Column(
      children: [
        PageHeader(
          title: 'Transactions',
          subtitle: 'Historique des entrées et sorties',
          actions: [
            OutlinedButton.icon(
              onPressed: data.rows.isNotEmpty && !_exporting
                  ? () => _printReport(data)
                  : null,
              icon: _exportIcon(const Icon(Icons.print_outlined, size: 18)),
              label: const Text('Imprimer'),
            ),
            const SizedBox(width: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: data.rows.isNotEmpty && !_exporting
                  ? () => _exportPdfAll(data)
                  : null,
              icon: _exportIcon(const Icon(Icons.picture_as_pdf_outlined, size: 18)),
              label: Text(_exporting ? 'Génération…' : 'Rapport PDF (tout)'),
            ),
            const SizedBox(width: AppSpacing.sm),
            ElevatedButton.icon(
              onPressed: _reference != null && data.rows.isNotEmpty && !_exporting
                  ? () => _exportPdf(data)
                  : null,
              icon: _exportIcon(const Icon(Icons.picture_as_pdf, size: 18)),
              label: Text(_exporting ? 'Génération…' : 'Rapport PDF'),
            ),
          ],
        ),
        Expanded(
          child: RefreshIndicator(
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
                            _InfoCard(
                              overview: overview,
                              storeAvailability: data.storeAvailability,
                              rows: data.rows,
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            _FiltersPanel(
                              products: data.products,
                              stores: data.stores,
                              reference: _reference,
                              storeId: _storeId,
                              type: _type,
                              dateFrom: _dateFrom,
                              dateTo: _dateTo,
                              searchController: _searchController,
                              onReferenceChanged: (value) {
                                setState(() => _reference = value);
                                _reapply();
                              },
                              onStoreChanged: (value) {
                                setState(() => _storeId = value);
                                _reapply();
                              },
                              onTypeChanged: (value) {
                                setState(() => _type = value);
                                _reapply();
                              },
                              onDateFromChanged: (value) {
                                setState(() => _dateFrom = value);
                                _reapply();
                              },
                              onDateToChanged: (value) {
                                setState(() => _dateTo = value);
                                _reapply();
                              },
                              onSearchChanged: _onSearchChanged,
                              onReset: _resetFilters,
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            _StatsRow(rows: data.rows),
                            const SizedBox(height: AppSpacing.lg),
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
          ),
        ),
      ],
    );
  }

  AdaptiveTable _table(_TransactionsData data) {
    final short = context.showsShortProductList;
    return AdaptiveTable(
      // On Android every movement is a card, and eight detail fields made
      // one card fill most of a phone screen. Keep what identifies the
      // movement and what it did to the stock, tighten the card, and
      // roughly twice as many fit. Nothing is lost that the card does not
      // already say another way: entree or sortie is in the coloured edge
      // and in the sign on the quantity.
      titleColumn: 2,
      subtitleColumn: 3,
      actionsColumn: short ? 6 : 10,
      minTableWidth: short ? 620 : 1000,
      dense: short,
      columns: short
          ? const [
              AppColumn('DATE', flex: 12),
              AppColumn('TYPE', flex: 9, align: Alignment.center),
              AppColumn('DÉSIGNATION', flex: 24),
              AppColumn('MAGASIN', flex: 14),
              AppColumn.number('QUANTITÉ', flex: 11),
              AppColumn.number('STOCK APRÈS', flex: 13),
              AppColumn.actions(flex: 10),
            ]
          : const [
              AppColumn('DATE', flex: 9),
              AppColumn('TYPE', flex: 7, align: Alignment.center),
              AppColumn('RÉFÉRENCE', flex: 10),
              AppColumn('DÉSIGNATION', flex: 18),
              AppColumn('MAGASIN', flex: 10),
              AppColumn('PARTENAIRE', flex: 12),
              AppColumn('N° FACTURE', flex: 9),
              AppColumn.number('ENTRÉE', flex: 8),
              AppColumn.number('SORTIE', flex: 8),
              // Wider than its neighbours: the heading is three times
              // their length and reads as part of SORTIE when clipped.
              AppColumn.number('STOCK APRÈS', flex: 12),
              AppColumn.actions(flex: 9),
            ],
      empty: const AppEmptyState(
        icon: Icons.swap_horiz,
        title: 'Aucune transaction',
        message: 'Aucun mouvement ne correspond aux filtres sélectionnés.',
      ),
      rows: [
        for (final row in data.rows) _transactionRow(row, data, short: short),
      ],
    );
  }

  Widget _typeCell(bool isEntry, Color typeColor) => Text(
        isEntry ? 'Entrée' : 'Sortie',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: typeColor,
        ),
      );

  Widget _balanceCell(TransactionRow row) => Cells.number(
        row.balance,
        strong: true,
        color: StockStatus.fromCurrent(row.balance).color,
      );

  Widget _actionsCell(TransactionRow row, _TransactionsData data) => RowActions(
        actions: [
          RowAction(
            icon: Icons.edit_outlined,
            tooltip: 'Modifier',
            onPressed: () => _openEditDialog(row, data.stores),
          ),
          RowAction(
            icon: Icons.delete_outline,
            tooltip: 'Supprimer',
            destructive: true,
            onPressed: () => _deleteTransaction(row),
          ),
        ],
      );

  AppRow _transactionRow(
    TransactionRow row,
    _TransactionsData data, {
    required bool short,
  }) {
    final isEntry = row.type == TransactionType.entry;
    final typeColor = isEntry ? AppColors.success : AppColors.error;

    if (short) {
      return AppRow(
        accent: typeColor,
        onTap: () => _openEditDialog(row, data.stores),
        cells: [
          Cells.muted(formatDisplayDate(row.date)),
          _typeCell(isEntry, typeColor),
          Cells.text(row.designation),
          Cells.muted(row.storeName),
          // One signed figure rather than a column each for in and out:
          // the sign and the colour already say which it was.
          Cells.number(
            isEntry ? '+ ${row.inQty}' : '− ${row.outQty}',
            color: typeColor,
            strong: true,
          ),
          _balanceCell(row),
          _actionsCell(row, data),
        ],
      );
    }

    return AppRow(
      accent: typeColor,
      onTap: () => _openEditDialog(row, data.stores),
      cells: [
        Cells.muted(formatDisplayDate(row.date)),
        _typeCell(isEntry, typeColor),
        Cells.identifier(row.reference),
        Cells.text(row.designation),
        Cells.muted(row.storeName),
        row.partner.isEmpty ? Cells.blank : Cells.muted(row.partner),
        row.invoiceNumber.isEmpty
            ? Cells.blank
            : Cells.muted(row.invoiceNumber),
        row.inQty > 0
            ? Cells.number('+ ${row.inQty}',
                color: AppColors.success, strong: true)
            : Cells.blank,
        row.outQty > 0
            ? Cells.number('− ${row.outQty}',
                color: AppColors.error, strong: true)
            : Cells.blank,
        _balanceCell(row),
        _actionsCell(row, data),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final ProductOverview? overview;
  final StoreAvailability? storeAvailability;
  final List<TransactionRow> rows;

  const _InfoCard({required this.overview, required this.storeAvailability, required this.rows});

  @override
  Widget build(BuildContext context) {
    final title = overview != null ? overview!.product.reference : 'Toutes les transactions';
    final sa = storeAvailability;

    final int initialStock;
    final int entriesTotal;
    final int outputsTotal;
    final int currentStock;
    final String storeLabel;

    if (sa != null) {
      initialStock = sa.initialStock;
      entriesTotal = rows.fold(0, (s, r) => s + r.inQty);
      outputsTotal = rows.fold(0, (s, r) => s + r.outQty);
      currentStock = sa.available;
      storeLabel = sa.storeName;
    } else if (overview != null) {
      initialStock = overview!.initialStock;
      entriesTotal = overview!.entriesTotal;
      outputsTotal = overview!.outputsTotal;
      currentStock = overview!.currentStock;
      storeLabel = overview!.storeNames;
    } else {
      initialStock = 0;
      entriesTotal = 0;
      outputsTotal = 0;
      currentStock = 0;
      storeLabel = '';
    }

    final stockStatus = StockStatus.fromCurrent(currentStock);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('PRODUIT SÉLECTIONNÉ', style: AppTextStyles.sectionLabel),
        const SizedBox(height: 6),
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.accentLight),
        ),
        if (storeLabel.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(storeLabel, style: AppTextStyles.bodyMuted),
        ],
        const SizedBox(height: 12),
        KpiRow(cards: [
          KpiCard(
            icon: Icons.inventory_2_outlined,
            label: 'Stock initial',
            value: overview != null ? '$initialStock' : '—',
            color: AppColors.textSecondary,
          ),
          KpiCard(
            icon: Icons.call_received,
            label: 'Entrées',
            value: overview != null ? '+$entriesTotal' : '—',
            color: AppColors.success,
          ),
          KpiCard(
            icon: Icons.call_made,
            label: 'Sorties',
            value: overview != null ? '-$outputsTotal' : '—',
            color: AppColors.error,
          ),
          KpiCard(
            icon: Icons.warehouse_outlined,
            label: 'Stock actuel',
            value: overview != null ? '$currentStock' : '—',
            color: overview != null ? stockStatus.color : AppColors.accentLight,
          ),
        ]),
      ],
    );
  }
}

class _FiltersPanel extends StatelessWidget {
  final List<ProductOverview> products;
  final List<Store> stores;
  final String? reference;
  final int? storeId;
  final TransactionType? type;
  final DateTime dateFrom;
  final DateTime dateTo;
  final TextEditingController searchController;
  final ValueChanged<String?> onReferenceChanged;
  final ValueChanged<int?> onStoreChanged;
  final ValueChanged<TransactionType?> onTypeChanged;
  final ValueChanged<DateTime> onDateFromChanged;
  final ValueChanged<DateTime> onDateToChanged;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onReset;

  const _FiltersPanel({
    required this.products,
    required this.stores,
    required this.reference,
    required this.storeId,
    required this.type,
    required this.dateFrom,
    required this.dateTo,
    required this.searchController,
    required this.onReferenceChanged,
    required this.onStoreChanged,
    required this.onTypeChanged,
    required this.onDateFromChanged,
    required this.onDateToChanged,
    required this.onSearchChanged,
    required this.onReset,
  });

  Future<void> _pickDate(
    BuildContext context,
    DateTime initial,
    ValueChanged<DateTime> onPicked,
  ) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) onPicked(picked);
  }

  Widget _dateField(
    BuildContext context,
    String label,
    DateTime value,
    ValueChanged<DateTime> onChanged,
  ) {
    return InkWell(
      borderRadius: AppRadius.fieldRadius,
      onTap: () => _pickDate(context, value, onChanged),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 16),
        ),
        child: Text(DateFormat('dd/MM/yyyy').format(value)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: appSurfaceDecoration(radius: AppRadius.lg),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Below this width the controls are given the full row rather
          // than being squeezed side by side.
          final stacked = constraints.maxWidth < 620;
          final full = constraints.maxWidth;
          double w(double wide) => stacked ? full : wide;

          return Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: w(240),
                child: DropdownButtonFormField<String?>(
                  initialValue: reference,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Produit'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Tous les produits'),
                    ),
                    ...products.map(
                      (o) => DropdownMenuItem<String?>(
                        value: o.product.reference,
                        child: Text(
                          '${o.product.reference} — ${o.product.designation}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: onReferenceChanged,
                ),
              ),
              SizedBox(
                width: w(260),
                child: TextField(
                  controller: searchController,
                  decoration: const InputDecoration(
                    labelText: 'Rechercher',
                    prefixIcon: Icon(Icons.search, size: 20),
                    hintText: 'Référence, désignation, fournisseur…',
                  ),
                  onChanged: onSearchChanged,
                ),
              ),
              SizedBox(
                width: w(180),
                child: DropdownButtonFormField<int?>(
                  initialValue: storeId,
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
                  onChanged: onStoreChanged,
                ),
              ),
              SizedBox(
                width: w(150),
                child: DropdownButtonFormField<TransactionType?>(
                  initialValue: type,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: const [
                    DropdownMenuItem<TransactionType?>(
                      value: null,
                      child: Text('Tous'),
                    ),
                    DropdownMenuItem<TransactionType?>(
                      value: TransactionType.entry,
                      child: Text('Entrée'),
                    ),
                    DropdownMenuItem<TransactionType?>(
                      value: TransactionType.output,
                      child: Text('Sortie'),
                    ),
                  ],
                  onChanged: onTypeChanged,
                ),
              ),
              // The two dates always stay on one line: side by side when
              // stacked, so the period reads as a single range control.
              if (stacked)
                SizedBox(
                  width: full,
                  child: Row(
                    children: [
                      Expanded(
                        child: _dateField(
                          context,
                          'Du',
                          dateFrom,
                          onDateFromChanged,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: _dateField(context, 'Au', dateTo, onDateToChanged),
                      ),
                    ],
                  ),
                )
              else ...[
                SizedBox(
                  width: 150,
                  child: _dateField(context, 'Du', dateFrom, onDateFromChanged),
                ),
                SizedBox(
                  width: 150,
                  child: _dateField(context, 'Au', dateTo, onDateToChanged),
                ),
              ],
              SizedBox(
                width: stacked ? full : null,
                child: OutlinedButton.icon(
                  onPressed: onReset,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Réinitialiser'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final List<TransactionRow> rows;

  const _StatsRow({required this.rows});

  @override
  Widget build(BuildContext context) {
    final totalIn = rows.fold<int>(0, (sum, r) => sum + r.inQty);
    final totalOut = rows.fold<int>(0, (sum, r) => sum + r.outQty);
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _StatChip(value: '${rows.length}', label: 'transactions', color: AppColors.textSecondary),
        _StatChip(value: '+$totalIn', label: 'total entrées', color: AppColors.success),
        _StatChip(value: '-$totalOut', label: 'total sorties', color: AppColors.error),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _StatChip({required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.elevated,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(width: 6),
          Text(label, style: AppTextStyles.bodyMuted),
        ],
      ),
    );
  }
}

class _TransactionFormDialog extends StatefulWidget {
  final TransactionRow row;
  final List<Store> stores;

  const _TransactionFormDialog({required this.row, required this.stores});

  @override
  State<_TransactionFormDialog> createState() => _TransactionFormDialogState();
}

class _TransactionFormDialogState extends State<_TransactionFormDialog> {
  final _entryRepo = StockEntryRepository();
  final _outputRepo = StockOutputRepository();
  late final TextEditingController _refController;
  late final TextEditingController _desController;
  late final TextEditingController _counterpartController;
  late final TextEditingController _invoiceController;
  late final TextEditingController _quantityController;
  late DateTime _date;
  int? _storeId;
  String? _error;
  bool _saving = false;

  bool get _isEntry => widget.row.type == TransactionType.entry;

  @override
  void initState() {
    super.initState();
    final row = widget.row;
    _refController = TextEditingController(text: row.reference);
    _desController = TextEditingController(text: row.designation);
    _counterpartController = TextEditingController(text: row.partner);
    _invoiceController = TextEditingController(text: row.invoiceNumber);
    _quantityController = TextEditingController(text: '${_isEntry ? row.inQty : row.outQty}');
    _storeId = widget.stores.isNotEmpty ? widget.stores.first.id : null;
    for (final s in widget.stores) {
      if (s.name == row.storeName) _storeId = s.id;
    }
    try {
      _date = DateTime.parse(row.date);
    } catch (_) {
      _date = DateTime.now();
    }
  }

  @override
  void dispose() {
    _refController.dispose();
    _desController.dispose();
    _counterpartController.dispose();
    _invoiceController.dispose();
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
    final ref = _refController.text.trim();
    final des = _desController.text.trim();
    final qty = int.tryParse(_quantityController.text.trim()) ?? 0;

    if (ref.isEmpty || des.isEmpty) {
      setState(() => _error = 'Référence et désignation sont obligatoires.');
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
      final dateStr = DateFormat('yyyy-MM-dd').format(_date);
      if (_isEntry) {
        await _entryRepo.update(StockEntry(
          id: widget.row.id,
          date: dateStr,
          supplier: _counterpartController.text.trim(),
          reference: ref,
          designation: des,
          storeId: _storeId!,
          quantity: qty,
        ));
      } else {
        await _outputRepo.update(StockOutput(
          id: widget.row.id,
          date: dateStr,
          reference: ref,
          designation: des,
          invoiceNumber: _invoiceController.text.trim(),
          storeId: _storeId!,
          destination: _counterpartController.text.trim(),
          quantity: qty,
        ));
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
      title: Text('Modifier la transaction · ${widget.row.reference}'),
      content: DialogBody(
        maxWidth: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(controller: _refController, decoration: const InputDecoration(labelText: 'Référence')),
            const SizedBox(height: 12),
            TextField(controller: _desController, decoration: const InputDecoration(labelText: 'Désignation')),
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
              controller: _counterpartController,
              decoration: InputDecoration(labelText: _isEntry ? 'Fournisseur' : 'Destination'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _invoiceController,
              decoration: const InputDecoration(labelText: 'N° facture'),
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
