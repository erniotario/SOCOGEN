import 'package:erp/modules/stock/models/stock_entry.dart';
import 'package:erp/modules/stock/models/stock_output.dart';
import 'package:erp/modules/stock/services/stock_service.dart';
import 'package:erp/modules/stock/repositories/stock_entry_repository.dart';
import 'package:erp/modules/stock/repositories/stock_output_repository.dart';

/// One article counted in one magasin.
///
/// [theoretical] is what the ledger said when the line was added to the
/// count, kept so the operator sees the figure they were judging against
/// even if something else moves in the meantime. It is *not* what the
/// adjustment is computed from — see [InventoryService.post].
class InventoryCount {
  final String reference;
  final String designation;
  final int storeId;
  final String storeName;
  final int theoretical;
  final int counted;

  const InventoryCount({
    required this.reference,
    required this.designation,
    required this.storeId,
    required this.storeName,
    required this.theoretical,
    required this.counted,
  });

  /// What the shelf holds minus what the ledger claims. Positive means a
  /// surplus to add, negative a shortfall to take out.
  int get variance => counted - theoretical;

  InventoryCount copyWith({int? theoretical, int? counted}) => InventoryCount(
        reference: reference,
        designation: designation,
        storeId: storeId,
        storeName: storeName,
        theoretical: theoretical ?? this.theoretical,
        counted: counted ?? this.counted,
      );
}

/// What one validated count session wrote.
class InventoryPostReport {
  int surpluses = 0;
  int shortfalls = 0;
  int unchanged = 0;

  final List<String> problems = [];

  int get adjustments => surpluses + shortfalls;

  String get summary {
    if (adjustments == 0) {
      return unchanged == 0
          ? 'Rien à régulariser.'
          : 'Inventaire validé : $unchanged article(s) conforme(s).';
    }
    final parts = <String>[
      if (surpluses > 0) '$surpluses excédent(s)',
      if (shortfalls > 0) '$shortfalls manquant(s)',
    ];
    var text = 'Inventaire validé : ${parts.join(', ')}';
    if (unchanged > 0) text += ' — $unchanged conforme(s)';
    return text;
  }
}

/// Posts a physical count as corrective movements.
///
/// The app derives current stock as
/// `initial_stock + entrées - sorties` and never stores it, so an
/// inventory cannot "set" a stock. It records the difference as an
/// ordinary movement instead: a surplus becomes an entrée, a shortfall a
/// sortie. That is also the accounting shape this project wants
/// elsewhere — the original lines stay standing and the correction is
/// visible beside them in Transactions, rather than history being
/// rewritten.
///
/// Adjustments are recognisable by their counterparty, [label]: it lands
/// in `supplier` on an entrée and `destination` on a sortie, the columns
/// Transactions already shows.
class InventoryService {
  InventoryService({
    StockService? stockService,
    StockEntryRepository? entryRepository,
    StockOutputRepository? outputRepository,
  })  : _stock = stockService ?? StockService(),
        _entries = entryRepository ?? StockEntryRepository(),
        _outputs = outputRepository ?? StockOutputRepository();

  final StockService _stock;
  final StockEntryRepository _entries;
  final StockOutputRepository _outputs;

  /// The counterparty written on every adjustment movement.
  static const String label = 'Inventaire physique';

  /// Writes one corrective movement per article whose count differs from
  /// the ledger.
  ///
  /// The variance is recomputed here against the live balance rather than
  /// trusted from [InventoryCount.theoretical]: a count session is a
  /// draft that can sit on screen for a while, and posting a difference
  /// measured against a stale figure would re-introduce the error the
  /// inventory exists to remove. The counted quantity is the fact; the
  /// theoretical figure is only what the operator was shown.
  Future<InventoryPostReport> post(
    List<InventoryCount> counts, {
    DateTime? on,
  }) async {
    final report = InventoryPostReport();
    final date = _iso(on ?? DateTime.now());

    for (final count in counts) {
      if (count.counted < 0) {
        report.problems.add(
          '${count.reference} (${count.storeName}) : '
          'quantité comptée négative, ligne ignorée.',
        );
        continue;
      }

      final live = await _stock.solde(
        reference: count.reference,
        magasinId: count.storeId,
      );
      final variance = count.counted - live;

      if (variance == 0) {
        report.unchanged++;
        continue;
      }

      if (variance > 0) {
        await _entries.create(StockEntry(
          id: 0,
          date: date,
          supplier: label,
          reference: count.reference,
          designation: count.designation,
          storeId: count.storeId,
          quantity: variance,
        ));
        report.surpluses++;
      } else {
        await _outputs.create(StockOutput(
          id: 0,
          date: date,
          reference: count.reference,
          designation: count.designation,
          invoiceNumber: '',
          storeId: count.storeId,
          destination: label,
          quantity: -variance,
        ));
        report.shortfalls++;
      }
    }

    return report;
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
