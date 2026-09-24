import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import 'package:erp/core/errors/messages.dart';
import 'package:erp/core/events/data_refresh_bus.dart';
import 'package:erp/modules/comptabilite/services/comptabilite_service.dart';
import 'package:erp/modules/parametres/services/parametres_service.dart';
import 'package:erp/modules/rapports/services/tva_pdf_service.dart';
import 'package:erp/shared/models/comptabilite.dart';
import 'package:erp/shared/ui/theme/app_breakpoints.dart';
import 'package:erp/shared/ui/theme/app_colors.dart';
import 'package:erp/shared/ui/theme/app_spacing.dart';
import 'package:erp/shared/ui/widgets/dialog_body.dart';
import 'package:erp/shared/ui/widgets/empty_state.dart';
import 'package:erp/shared/ui/widgets/kpi_card.dart';
import 'package:erp/shared/ui/widgets/page_header.dart';
import 'package:erp/shared/ui/widgets/section_card.dart';
import 'package:erp/shared/ui/widgets/skeleton.dart';

/// La comptabilité : fermer une période, et déclarer ce qu'elle a
/// collecté.
///
/// Les deux vont ensemble et c'est tout le propos de cet écran. Tant
/// qu'une période reste ouverte, un mouvement de mars peut être corrigé
/// en décembre et la déclaration établie entre-temps devient fausse
/// sans que personne ne le sache. La déclaration porte donc l'état de
/// la période, et la clôture est à côté d'elle.
class ComptabiliteScreen extends StatefulWidget {
  const ComptabiliteScreen({super.key});

  @override
  State<ComptabiliteScreen> createState() => _ComptabiliteScreenState();
}

class _EtatCompta {
  final String? limite;
  final List<ActeCloture> historique;
  final DeclarationTva declaration;

  const _EtatCompta({
    required this.limite,
    required this.historique,
    required this.declaration,
  });
}

class _ComptabiliteScreenState extends State<ComptabiliteScreen> {
  final _service = ComptabiliteService();
  final _parametres = ParametresService();

  late DateTimeRange _periode;
  late Future<_EtatCompta> _future;
  bool _impression = false;

  @override
  void initState() {
    super.initState();
    // Le mois écoulé : la période qu'on déclare le plus souvent, et
    // celle qu'on vient de finir quand on ouvre cet écran.
    final maintenant = DateTime.now();
    final debutMois = DateTime(maintenant.year, maintenant.month, 1);
    _periode = DateTimeRange(
      start: DateTime(maintenant.year, maintenant.month - 1, 1),
      end: debutMois.subtract(const Duration(days: 1)),
    );
    _future = _charger();
    DataRefreshBus.instance.addListener(_recharger);
  }

  @override
  void dispose() {
    DataRefreshBus.instance.removeListener(_recharger);
    super.dispose();
  }

  /// Les trois lectures partent **ensemble**, pas l'une après l'autre.
  ///
  /// Enchaînées, elles font trois allers-retours successifs : l'écran
  /// reste sur son squelette bien plus longtemps, et le banc de test
  /// widget échoue au démontage avec une requête encore en vol. Aucune
  /// des trois n'a besoin du résultat des autres.
  Future<_EtatCompta> _charger() async {
    final (limite, historique, declaration) = await (
      _service.charger(),
      _service.historique(),
      _service.tvaCollectee(du: _periode.start, au: _periode.end),
    ).wait;
    return _EtatCompta(
      limite: limite,
      historique: historique,
      declaration: declaration,
    );
  }

  void _recharger() {
    if (!mounted) return;
    // Corps en bloc : une flèche rendrait le Future à `setState`, qui
    // refuse de le poser.
    setState(() {
      _future = _charger();
    });
  }

  Future<void> _choisirPeriode() async {
    final choisi = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _periode,
      helpText: 'Période à déclarer',
    );
    if (choisi == null) return;
    setState(() => _periode = choisi);
    _recharger();
  }

  Future<void> _cloturer() async {
    final jour = await showDatePicker(
      context: context,
      initialDate: _periode.end,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: 'Fermer les livres jusqu\'au',
    );
    if (jour == null || !mounted) return;
    final confirme = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clôturer la période ?'),
        content: DialogBody(
          child: Text(
            'Plus aucun mouvement ni règlement daté du '
            '${_iso(jour)} ou avant ne pourra être créé, corrigé ou '
            'supprimé. Une correction devra passer par un mouvement daté '
            'd\'aujourd\'hui.\n\n'
            'La clôture reste annulable : rouvrir demande un motif, qui '
            'restera au dossier.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clôturer'),
          ),
        ],
      ),
    );
    if (confirme != true) return;
    await _executer(() => _service.cloturer(jusquau: jour));
  }

  Future<void> _rouvrir(String limite) async {
    final motif = TextEditingController();
    final valide = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rouvrir la période'),
        content: DialogBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Les livres sont fermés jusqu\'au $limite. Les rouvrir '
                'rend à nouveau modifiables des écritures déjà arrêtées, '
                'et peut donc changer une déclaration déjà déposée.',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: motif,
                autofocus: true,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Motif *',
                  // Ce qu'un contrôle regardera en premier.
                  helperText: 'Restera au dossier, avec votre nom',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Rouvrir tout'),
          ),
        ],
      ),
    );
    if (valide != true) return;
    await _executer(() => _service.rouvrir(motif: motif.text));
  }

  Future<void> _executer(Future<void> Function() action) async {
    try {
      await action();
      if (!mounted) return;
      _recharger();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(messagePour(e, operation: 'la clôture'))),
      );
    }
  }

  Future<void> _imprimer(DeclarationTva declaration) async {
    setState(() => _impression = true);
    try {
      final societe = await _parametres.societe();
      final bytes = await TvaPdfService.buildInBackground(
        TvaPdfRequest(declaration: declaration, societe: societe),
      );
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'TVA ${declaration.du} au ${declaration.au}',
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

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final taille = context.windowSize;
    return FutureBuilder<_EtatCompta>(
      future: _future,
      builder: (context, snapshot) {
        final etat = snapshot.data;
        return Column(
          children: [
            PageHeader(
              title: 'Comptabilité',
              subtitle: 'Clôture des périodes et TVA collectée',
              actions: [
                OutlinedButton.icon(
                  onPressed: _choisirPeriode,
                  icon: const Icon(Icons.date_range_outlined, size: 18),
                  label: Text('${_iso(_periode.start)} → '
                      '${_iso(_periode.end)}'),
                ),
                ElevatedButton.icon(
                  onPressed: etat == null || _impression
                      ? null
                      : () => _imprimer(etat.declaration),
                  icon: const Icon(Icons.print_outlined, size: 18),
                  label: const Text('Imprimer'),
                ),
              ],
            ),
            Expanded(child: _corps(taille, snapshot)),
          ],
        );
      },
    );
  }

  Widget _corps(WindowSize taille, AsyncSnapshot<_EtatCompta> snapshot) {
    final padding = AppSpacing.pagePadding(taille);

    if (snapshot.hasError) {
      return AppErrorState(
        message: messagePour(snapshot.error!, operation: 'la comptabilité'),
        onRetry: _recharger,
      );
    }
    final etat = snapshot.data;
    if (etat == null) {
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

    final d = etat.declaration;
    return ListView(
      padding: padding,
      children: [
        KpiRow(cards: [
          KpiCard(
            icon: Icons.receipt_long_outlined,
            label: 'Chiffre TTC',
            value: d.totalTtc.formate(),
            color: AppColors.accentLight,
          ),
          KpiCard(
            icon: Icons.functions_outlined,
            label: 'Base HT',
            value: d.totalHt.formate(),
            color: AppColors.textSecondary,
          ),
          KpiCard(
            icon: Icons.account_balance_outlined,
            label: 'TVA collectée',
            value: d.totalTva.formate(),
            color: AppColors.success,
          ),
          KpiCard(
            icon: d.periodeFermee ? Icons.lock_outline : Icons.lock_open,
            label: 'Période',
            value: d.periodeFermee ? 'Clôturée' : 'Ouverte',
            color: d.periodeFermee ? AppColors.success : AppColors.warning,
          ),
        ]),
        const SizedBox(height: AppSpacing.lg),
        _bandeauPeriode(etat),
        const SizedBox(height: AppSpacing.lg),
        _ventilation(d),
        const SizedBox(height: AppSpacing.lg),
        _cloture(etat),
        if (etat.historique.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          _historique(etat.historique),
        ],
      ],
    );
  }

  /// L'état de la période, en haut : c'est ce qui dit si les chiffres
  /// au-dessus peuvent encore changer.
  Widget _bandeauPeriode(_EtatCompta etat) {
    final ferme = etat.declaration.periodeFermee;
    final couleur = ferme ? AppColors.success : AppColors.warning;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.10),
        border: Border.all(color: couleur.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ferme ? Icons.lock_outline : Icons.warning_amber_outlined,
              size: 18, color: couleur),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              ferme
                  ? 'Les livres sont fermés jusqu\'au ${etat.limite} : '
                      'les chiffres de cette période ne bougeront plus.'
                  : etat.limite == null
                      ? 'Aucune période n\'est clôturée. Tout mouvement '
                          'reste modifiable, y compris ceux déjà '
                          'déclarés — les montants ci-dessus peuvent '
                          'donc changer.'
                      : 'Les livres sont fermés jusqu\'au ${etat.limite}, '
                          'mais la période affichée va au-delà : sa fin '
                          'reste modifiable.',
              style: TextStyle(fontSize: 13, color: couleur),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ventilation(DeclarationTva d) => SectionCard(
        icon: Icons.account_balance_outlined,
        title: 'TVA COLLECTÉE',
        children: [
          for (final ligne in d.lignes)
            _ligne(
              ligne.taux.toString(),
              '${ligne.baseHt.formate(avecSymbole: false)} HT  ·  '
                  '${ligne.tva.formate(avecSymbole: false)} de TVA',
            ),
          if (d.lignes.isEmpty)
            _ligne('Aucune vente sur la période', '', attenue: true),
          const Divider(height: 20),
          _ligne('Total TVA collectée', d.totalTva.formate(), fort: true),
          const SizedBox(height: AppSpacing.sm),
          // La moitié manquante, nommée. Un écran qui s'arrête à la
          // collectée sans le dire laisse croire que c'est la taxe due.
          Text(
            'TVA déductible non tenue : les factures d\'achat ne sont pas '
            'saisies. Ce montant est le point de départ de la déclaration, '
            'pas la taxe nette à payer.',
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary),
          ),
          if (d.aDesInconnues) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              [
                if (d.lignesSansTaux > 0)
                  '${d.lignesSansTaux} ligne(s) sans taux enregistré, soit '
                      '${d.ttcSansTaux.formate()} : dans le chiffre TTC, '
                      'hors de toute base.',
                if (d.lignesSansPrix > 0)
                  '${d.lignesSansPrix} ligne(s) sans prix : hors de tous '
                      'les totaux.',
              ].join(' '),
              style: const TextStyle(fontSize: 12, color: AppColors.anomaly),
            ),
          ],
        ],
      );

  Widget _cloture(_EtatCompta etat) => SectionCard(
        icon: Icons.lock_outline,
        title: 'CLÔTURE',
        children: [
          Text(
            etat.limite == null
                ? 'Aucune période n\'est fermée.'
                : 'Fermé jusqu\'au ${etat.limite} inclus.',
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: [
              ElevatedButton.icon(
                onPressed: _cloturer,
                icon: const Icon(Icons.lock_outline, size: 18),
                label: const Text('Clôturer une période'),
              ),
              if (etat.limite != null)
                OutlinedButton.icon(
                  onPressed: () => _rouvrir(etat.limite!),
                  icon: const Icon(Icons.lock_open, size: 18),
                  label: const Text('Rouvrir'),
                ),
            ],
          ),
        ],
      );

  Widget _historique(List<ActeCloture> actes) => SectionCard(
        icon: Icons.history,
        title: 'HISTORIQUE',
        children: [
          // Rien n'est écrasé : « qui a rouvert mars, et pourquoi » est
          // la question qu'un contrôle pose.
          for (final acte in actes)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    acte.estUneReouverture
                        ? Icons.lock_open
                        : Icons.lock_outline,
                    size: 16,
                    color: acte.estUneReouverture
                        ? AppColors.warning
                        : AppColors.textSecondary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          acte.estUneReouverture
                              ? acte.fermeJusquau.isEmpty
                                  ? 'Réouverture totale'
                                  : 'Réouverture jusqu\'au '
                                      '${acte.fermeJusquau}'
                              : 'Clôture jusqu\'au ${acte.fermeJusquau}',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          [
                            acte.auteur ?? 'auteur inconnu',
                            if (acte.quand != null)
                              acte.quand!.substring(0, 10),
                            if (acte.motif != null) acte.motif!,
                          ].join('  ·  '),
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      );

  Widget _ligne(String libelle, String valeur,
          {bool fort = false, bool attenue = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(libelle,
                  style: TextStyle(
                    fontSize: fort ? 14 : 13,
                    fontWeight: fort ? FontWeight.w700 : FontWeight.w400,
                    color: attenue
                        ? AppColors.textSecondary
                        : AppColors.textPrimary,
                  )),
            ),
            Text(valeur,
                style: TextStyle(
                  fontSize: fort ? 14 : 13,
                  fontWeight: fort ? FontWeight.w700 : FontWeight.w400,
                )),
          ],
        ),
      );
}
