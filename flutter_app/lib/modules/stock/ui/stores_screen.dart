import 'package:flutter/material.dart';

import 'package:socogen/modules/stock/models/store.dart';
import 'package:socogen/shared/models/view_models.dart';
import 'package:socogen/modules/stock/repositories/store_repository.dart';
import 'package:socogen/core/events/data_refresh_bus.dart';
import 'package:socogen/shared/ui/theme/app_breakpoints.dart';
import 'package:socogen/shared/ui/theme/app_colors.dart';
import 'package:socogen/shared/ui/theme/app_spacing.dart';
import 'package:socogen/shared/ui/theme/app_text_styles.dart';
import 'package:socogen/shared/ui/widgets/adaptive_table.dart';
import 'package:socogen/shared/ui/widgets/empty_state.dart';
import 'package:socogen/shared/ui/widgets/page_header.dart';
import 'package:socogen/shared/ui/widgets/row_actions.dart';
import 'package:socogen/shared/ui/widgets/skeleton.dart';
import 'package:socogen/core/errors/messages.dart';

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

  /// Réunit deux magasins qui désignent le même dépôt.
  ///
  /// Le geste existe parce que les données réelles portent
  /// « Elig-Essono » et « Ellig-Essono ». Le stock étant dérivé par
  /// magasin, ce doublon coupe en deux le solde d'un même entrepôt — et
  /// un article peut paraître en rupture d'un côté et fourni de l'autre.
  Future<void> _fusionner(Store source) async {
    final autres = (await _storeRepo.getAllStores())
        .where((m) => m.id != source.id)
        .toList();
    if (!mounted) return;
    if (autres.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Il n'y a pas d'autre magasin vers lequel "
                'fusionner.')),
      );
      return;
    }
    final bilan = await showDialog<
        ({int mouvements, int lignesStock, int transferts})>(
      context: context,
      builder: (_) => _FusionMagasinDialog(source: source, candidats: autres),
    );
    if (bilan == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 6),
        content: Text(
          'Magasins réunis. ${bilan.mouvements} mouvement'
          '${bilan.mouvements > 1 ? 's' : ''} et ${bilan.lignesStock} ligne'
          '${bilan.lignesStock > 1 ? 's' : ''} de stock déplacée'
          '${bilan.lignesStock > 1 ? 's' : ''}.',
        ),
      ),
    );
    _onChanged();
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
      minTableWidth: 600,
      columns: const [
        AppColumn('ID', flex: 8, align: Alignment.center),
        AppColumn('NOM DU MAGASIN', flex: 35),
        AppColumn('PRODUITS', flex: 15, align: Alignment.center),
        AppColumn.number('STOCK TOTAL', flex: 20),
        AppColumn.actions(flex: 20),
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
                    icon: Icons.merge_type,
                    tooltip: 'Fusionner avec un autre magasin',
                    onPressed: () => _fusionner(overview.store),
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
        _error = messagePour(e, operation: 'la modification du magasin');
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


/// Réunir deux magasins, en disant ce que cela va faire.
///
/// L'opération est irréversible et touche tout l'historique du dépôt :
/// le dialogue annonce donc les trois effets — les mouvements changent
/// de magasin, les stocks d'ouverture s'additionnent, le magasin source
/// disparaît — avant de demander confirmation.
class _FusionMagasinDialog extends StatefulWidget {
  final Store source;
  final List<Store> candidats;

  const _FusionMagasinDialog({required this.source, required this.candidats});

  @override
  State<_FusionMagasinDialog> createState() => _FusionMagasinDialogState();
}

class _FusionMagasinDialogState extends State<_FusionMagasinDialog> {
  final _storeRepo = StoreRepository();

  Store? _cible;
  String? _erreur;
  bool _enCours = false;

  Future<void> _fusionner() async {
    final cible = _cible;
    if (cible == null) {
      setState(() => _erreur = 'Choisissez le magasin à conserver.');
      return;
    }
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      final bilan = await _storeRepo.fusionner(
        sourceId: widget.source.id,
        cibleId: cible.id,
      );
      if (!mounted) return;
      Navigator.pop(context, bilan);
    } catch (e) {
      setState(() {
        _erreur = messagePour(e, operation: 'la fusion des magasins');
        _enCours = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Fusionner deux magasins'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tout ce que contient « ${widget.source.name} » passera au '
              'magasin conservé, et « ${widget.source.name} » sera '
              'supprimé.',
              style: AppTextStyles.bodyMuted,
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<Store>(
              initialValue: _cible,
              isExpanded: true,
              decoration:
                  const InputDecoration(labelText: 'Magasin à conserver'),
              items: [
                for (final m in widget.candidats)
                  DropdownMenuItem(
                    value: m,
                    child: Text(m.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() => _cible = v),
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border:
                    Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_outlined,
                      size: 16, color: AppColors.warning),
                  const SizedBox(width: AppSpacing.sm),
                  const Expanded(
                    child: Text(
                      'Les mouvements changent de magasin et les stocks '
                      "de départ s'additionnent. Cette opération ne peut "
                      'pas être annulée.',
                      style: AppTextStyles.bodyMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (_erreur != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(_erreur!,
                  style:
                      const TextStyle(color: AppColors.error, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _enCours ? null : () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _enCours ? null : _fusionner,
          child: _enCours
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Fusionner'),
        ),
      ],
    );
  }
}
