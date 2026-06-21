import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

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
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/kpi_card.dart';
import '../widgets/page_header.dart';
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
      final rows = await _transactionRepo.getTransactions(
        reference: _reference,
        search: _search.isEmpty ? null : _search,
        storeId: _storeId,
        type: _type,
        dateFrom: DateFormat('yyyy-MM-dd').format(_dateFrom),
        dateTo: DateFormat('yyyy-MM-dd').format(_dateTo),
      );
      final products = await _productRepo.getProductOverviews();
      final stores = await _storeRepo.getAllStores();

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

  Future<void> _exportPdfReport(_TransactionsData data, {required String defaultName}) async {
    if (data.rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucune transaction à exporter.')),
      );
      return;
    }

    try {
      final company = await _settingsRepo.getSettings();
      final overview = _selectedOverview(data.products);
      final bytes = await TransactionsPdfService.build(
        productRef: _reference,
        transactions: data.rows,
        overview: overview,
        storeAvailability: data.storeAvailability,
        company: company,
      );

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

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (_error != null) {
      return Column(
        children: [
          const PageHeader(
            title: 'Transactions',
            subtitle: 'Historique des entrées et sorties',
          ),
          Expanded(
            child: Center(
              child: Text(
                'Erreur de chargement : $_error',
                style: const TextStyle(color: AppColors.error),
              ),
            ),
          ),
        ],
      );
    }
    if (data == null) {
      return const Column(
        children: [
          PageHeader(
            title: 'Transactions',
            subtitle: 'Historique des entrées et sorties',
          ),
          Expanded(child: Center(child: CircularProgressIndicator())),
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
              onPressed: data.rows.isNotEmpty ? () => _exportPdfAll(data) : null,
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: const Text('Rapport PDF (tout)'),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _reference != null && data.rows.isNotEmpty ? () => _exportPdf(data) : null,
              icon: const Icon(Icons.picture_as_pdf, size: 18),
              label: const Text('Rapport PDF'),
            ),
          ],
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                _InfoCard(overview: overview, storeAvailability: data.storeAvailability, rows: data.rows),
                const SizedBox(height: 16),
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
                const SizedBox(height: 16),
                _StatsRow(rows: data.rows),
                const SizedBox(height: 16),
                _TransactionsTable(
                  rows: data.rows,
                  onEdit: (row) => _openEditDialog(row, data.stores),
                  onDelete: _deleteTransaction,
                ),
              ],
            ),
          ),
        ),
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

  Future<void> _pickDate(BuildContext context, DateTime initial, ValueChanged<DateTime> onPicked) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) onPicked(picked);
  }

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
            width: 240,
            child: DropdownButtonFormField<String?>(
              initialValue: reference,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Produit'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Tous les produits')),
                ...products.map((o) => DropdownMenuItem<String?>(
                      value: o.product.reference,
                      child: Text(
                        '${o.product.reference} — ${o.product.designation}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    )),
              ],
              onChanged: onReferenceChanged,
            ),
          ),
          SizedBox(
            width: 260,
            child: TextField(
              controller: searchController,
              decoration: const InputDecoration(
                labelText: 'Rechercher',
                prefixIcon: Icon(Icons.search, size: 20),
                hintText: 'Référence, désignation, fournisseur…',
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
            width: 140,
            child: DropdownButtonFormField<TransactionType?>(
              initialValue: type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: const [
                DropdownMenuItem<TransactionType?>(value: null, child: Text('Tous')),
                DropdownMenuItem<TransactionType?>(value: TransactionType.entry, child: Text('Entrée')),
                DropdownMenuItem<TransactionType?>(value: TransactionType.output, child: Text('Sortie')),
              ],
              onChanged: onTypeChanged,
            ),
          ),
          SizedBox(
            width: 140,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _pickDate(context, dateFrom, onDateFromChanged),
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Du'),
                child: Text(DateFormat('dd/MM/yyyy').format(dateFrom)),
              ),
            ),
          ),
          SizedBox(
            width: 140,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _pickDate(context, dateTo, onDateToChanged),
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Au'),
                child: Text(DateFormat('dd/MM/yyyy').format(dateTo)),
              ),
            ),
          ),
          OutlinedButton.icon(
            onPressed: onReset,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Réinitialiser'),
          ),
        ],
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

// Relative flex weights for the transactions table columns. Using a
// flexible Row instead of fixed pixel widths means the table always fits
// the available width (no horizontal scrollbar cutting off the ACTIONS
// column).
const int _colDate = 9;
const int _colType = 7;
const int _colReference = 10;
const int _colDesignation = 20;
const int _colStore = 10;
const int _colPartner = 14;
const int _colInvoice = 9;
const int _colInOut = 8;
const int _colBalance = 8;
const int _colActions = 9;
const double _cellPadding = 10;

class _TransactionsTable extends StatelessWidget {
  final List<TransactionRow> rows;
  final void Function(TransactionRow) onEdit;
  final void Function(TransactionRow) onDelete;

  const _TransactionsTable({required this.rows, required this.onEdit, required this.onDelete});

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
                  child: Center(child: Text('Aucune transaction', style: AppTextStyles.bodyMuted)),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: rows.length,
                  itemBuilder: (context, index) => _TransactionRowWidget(
                    row: rows[index],
                    onEdit: onEdit,
                    onDelete: onDelete,
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
      child: const Row(
        children: [
          Expanded(
            flex: _colDate,
            child: Text('DATE', style: AppTextStyles.tableHeader, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            flex: _colType,
            child: Text(
              'TYPE',
              style: AppTextStyles.tableHeader,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: _colReference,
            child: Text('RÉFÉRENCE', style: AppTextStyles.tableHeader, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            flex: _colDesignation,
            child: Text('DÉSIGNATION', style: AppTextStyles.tableHeader, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            flex: _colStore,
            child: Text('MAGASIN', style: AppTextStyles.tableHeader, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            flex: _colPartner,
            child: Text(
              'FOURNISSEUR / DESTINATION',
              style: AppTextStyles.tableHeader,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: _colInvoice,
            child: Text('N° FACTURE', style: AppTextStyles.tableHeader, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            flex: _colInOut,
            child: Text(
              'ENTRÉE (+)',
              style: AppTextStyles.tableHeader,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: _colInOut,
            child: Text(
              'SORTIE (−)',
              style: AppTextStyles.tableHeader,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: _colBalance,
            child: Text(
              'SOLDE',
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

class _TransactionRowWidget extends StatelessWidget {
  final TransactionRow row;
  final void Function(TransactionRow) onEdit;
  final void Function(TransactionRow) onDelete;

  const _TransactionRowWidget({required this.row, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final isEntry = row.type == TransactionType.entry;
    var displayDate = row.date;
    try {
      displayDate = DateFormat('dd/MM/yyyy').format(DateTime.parse(row.date));
    } catch (_) {}

    final tint = isEntry ? AppColors.successBg : AppColors.errorBg;

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: _cellPadding),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.35),
        border: const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: _colDate,
            child: Text(
              displayDate,
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: _colType,
            child: Text(
              isEntry ? 'Entrée' : 'Sortie',
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isEntry ? AppColors.success : AppColors.error,
              ),
            ),
          ),
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
            flex: _colStore,
            child: Text(row.storeName, style: AppTextStyles.bodyMuted, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            flex: _colPartner,
            child: Text(
              row.partner.isEmpty ? '—' : row.partner,
              style: AppTextStyles.bodyMuted,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: _colInvoice,
            child: Text(
              row.invoiceNumber.isEmpty ? '—' : row.invoiceNumber,
              style: AppTextStyles.bodyMuted,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: _colInOut,
            child: Text(
              row.inQty > 0 ? '+ ${row.inQty}' : '—',
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.success),
            ),
          ),
          Expanded(
            flex: _colInOut,
            child: Text(
              row.outQty > 0 ? '− ${row.outQty}' : '—',
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.error),
            ),
          ),
          Expanded(
            flex: _colBalance,
            child: Text(
              '${row.balance}',
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: StockStatus.fromCurrent(row.balance).color,
              ),
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
                  onPressed: () => onEdit(row),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: AppColors.error,
                  tooltip: 'Supprimer',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () => onDelete(row),
                ),
              ],
            ),
          ),
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
      content: SizedBox(
        width: 480,
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
