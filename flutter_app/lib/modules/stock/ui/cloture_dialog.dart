import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';

import 'package:erp/core/errors/messages.dart';
import 'package:erp/modules/parametres/services/parametres_service.dart';
import 'package:erp/modules/rapports/services/cloture_pdf_service.dart';
import 'package:erp/modules/stock/models/store.dart';
import 'package:erp/modules/stock/services/cloture_service.dart';
import 'package:erp/shared/models/cloture.dart';
import 'package:erp/shared/ui/theme/app_colors.dart';
import 'package:erp/shared/ui/theme/app_spacing.dart';
import 'package:erp/shared/ui/theme/app_text_styles.dart';
import 'package:erp/shared/ui/widgets/dialog_body.dart';

/// La clôture du soir, ouverte depuis la caisse.
///
/// Elle vit **ici** et non dans Rapports parce que c'est un geste de
/// comptoir : le caissier ferme, imprime, compte son tiroir. Le lui
/// faire chercher dans un écran de rapports à huit heures du soir,
/// c'est s'assurer qu'il ne le fera pas.
///
/// Elle ne ferme rien au sens comptable — rien n'est figé, les
/// corrections restent possibles. C'est une lecture de la journée, et
/// le document qu'on signe.
class ClotureDialog extends StatefulWidget {
  final List<Store> magasins;

  /// Le magasin de la caisse, proposé d'emblée.
  final int? magasinId;

  const ClotureDialog({super.key, required this.magasins, this.magasinId});

  @override
  State<ClotureDialog> createState() => _ClotureDialogState();
}

class _ClotureDialogState extends State<ClotureDialog> {
  final _service = ClotureService();
  final _parametres = ParametresService();

  late DateTime _date;
  late int? _magasinId;
  late Future<ClotureCaisse> _future;
  bool _impression = false;

  @override
  void initState() {
    super.initState();
    _date = DateTime.now();
    _magasinId = widget.magasinId;
    _future = _charger();
  }

  String get _iso =>
      '${_date.year.toString().padLeft(4, '0')}-'
      '${_date.month.toString().padLeft(2, '0')}-'
      '${_date.day.toString().padLeft(2, '0')}';

  String? get _nomMagasin => _magasinId == null
      ? null
      : widget.magasins
          .where((m) => m.id == _magasinId)
          .map((m) => m.name)
          .firstOrNull;

  Future<ClotureCaisse> _charger() => _service.pour(
        date: _iso,
        magasinId: _magasinId,
        nomMagasin: _nomMagasin,
      );

  void _relire() {
    // Corps en bloc et non en flèche : une flèche *retourne* le Future
    // à `setState`, qui refuse de le poser. Le piège a déjà coûté la
    // recherche des Tiers et le rafraîchissement de l'Inventaire.
    setState(() {
      _future = _charger();
    });
  }

  Future<void> _choisirDate() async {
    final choisi = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: 'Journée à clôturer',
    );
    if (choisi == null) return;
    setState(() => _date = choisi);
    _relire();
  }

  Future<void> _imprimer(ClotureCaisse cloture) async {
    setState(() => _impression = true);
    try {
      final societe = await _parametres.societe();
      final bytes = await ClosurePdfService.buildInBackground(
        ClosurePdfRequest(cloture: cloture, societe: societe),
      );
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'Journal de caisse ${cloture.date}',
        format: PdfPageFormat.a4,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(messagePour(e, operation: "l'impression"))),
      );
    } finally {
      if (mounted) setState(() => _impression = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Clôture de caisse'),
      content: DialogBody(
        maxWidth: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _filtres(),
            const SizedBox(height: AppSpacing.lg),
            FutureBuilder<ClotureCaisse>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text(
                    messagePour(snapshot.error!, operation: 'la clôture'),
                    style: const TextStyle(color: AppColors.error),
                  );
                }
                final cloture = snapshot.data;
                if (cloture == null) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }
                return _resume(cloture);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fermer'),
        ),
        FutureBuilder<ClotureCaisse>(
          future: _future,
          builder: (context, snapshot) {
            final cloture = snapshot.data;
            return ElevatedButton.icon(
              onPressed: cloture == null || _impression
                  ? null
                  : () => _imprimer(cloture),
              icon: const Icon(Icons.print_outlined, size: 18),
              label: const Text('Imprimer'),
            );
          },
        ),
      ],
    );
  }

  Widget _filtres() => Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _choisirDate,
              icon: const Icon(Icons.event_outlined, size: 18),
              label: Text(_iso),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: DropdownButtonFormField<int?>(
              initialValue: _magasinId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Point de vente'),
              items: [
                // « Tous » est une lecture d'ensemble pour le
                // propriétaire ; un caissier clôture le sien.
                const DropdownMenuItem(value: null, child: Text('Tous')),
                for (final m in widget.magasins)
                  DropdownMenuItem(value: m.id, child: Text(m.name)),
              ],
              onChanged: (v) {
                setState(() => _magasinId = v);
                _relire();
              },
            ),
          ),
        ],
      );

  Widget _resume(ClotureCaisse cloture) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Ce qui est entré d'abord : un caissier qui s'apprête à
        // compter des billets n'a que faire du chiffre d'affaires.
        _titre('Ce qui est entré'),
        for (final ligne in cloture.encaisse)
          _ligne('${ligne.mode.libelle} (${ligne.operations})',
              ligne.montant.formate(avecSymbole: false)),
        if (cloture.encaisse.isEmpty)
          _ligne('Aucun règlement', '', attenue: true),
        _ligne('Total encaissé', cloture.encaisseTotal.formate(), fort: true),
        if (cloture.encaisseSurCreances.estPositif)
          _ligne('dont créances antérieures',
              cloture.encaisseSurCreances.formate(avecSymbole: false),
              attenue: true),
        _ligne('Espèces à compter', cloture.especes.formate(), fort: true),

        const SizedBox(height: AppSpacing.lg),
        _titre('Ce qui a été vendu'),
        _ligne('Tickets', '${cloture.tickets}'),
        _ligne('Total vendu TTC', cloture.ventesTtc.formate(), fort: true),
        if (cloture.creditAccorde.estPositif)
          _ligne('dont resté dû ce soir',
              cloture.creditAccorde.formate(avecSymbole: false),
              attenue: true),

        if (cloture.tva.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          _titre('TVA collectée'),
          for (final bloc in cloture.tva)
            _ligne('Base ${bloc.taux}',
                '${bloc.baseHt.formate(avecSymbole: false)}  |  '
                    '${bloc.tva.formate(avecSymbole: false)}'),
          _ligne('Total TVA', cloture.totalTva.formate(), fort: true),
        ],

        if (cloture.aDesInconnues) ...[
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.anomaly.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _reserves(cloture),
              style: const TextStyle(fontSize: 12, color: AppColors.anomaly),
            ),
          ),
        ],
      ],
    );
  }

  /// Ce que la clôture ne sait pas dire.
  ///
  /// Nommé plutôt que tu : c'est sur ce résumé qu'on décide que la
  /// caisse tombe juste, et un total partiel présenté comme complet
  /// fait chercher un écart qui n'existe pas.
  String _reserves(ClotureCaisse cloture) {
    final phrases = <String>[
      if (cloture.lignesSansPrix > 0)
        '${cloture.lignesSansPrix} ligne(s) vendue(s) sans prix : hors '
            'des totaux.',
      if (cloture.ttcSansTaux.estPositif)
        '${cloture.ttcSansTaux.formate()} sans taux de TVA : dans le '
            'vendu, hors des bases.',
    ];
    return phrases.join(' ');
  }

  Widget _titre(String texte) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: Text(texte.toUpperCase(), style: AppTextStyles.sectionLabel),
      );

  Widget _ligne(String libelle, String valeur,
          {bool fort = false, bool attenue = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                libelle,
                style: TextStyle(
                  fontSize: fort ? 14 : 13,
                  fontWeight: fort ? FontWeight.w700 : FontWeight.w400,
                  color: attenue
                      ? AppColors.textSecondary
                      : AppColors.textPrimary,
                ),
              ),
            ),
            Text(
              valeur,
              style: TextStyle(
                fontSize: fort ? 14 : 13,
                fontWeight: fort ? FontWeight.w700 : FontWeight.w400,
                color:
                    attenue ? AppColors.textSecondary : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      );
}
