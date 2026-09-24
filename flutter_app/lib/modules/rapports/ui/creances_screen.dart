import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import 'package:erp/core/errors/messages.dart';
import 'package:erp/core/events/data_refresh_bus.dart';
import 'package:erp/modules/parametres/services/parametres_service.dart';
import 'package:erp/modules/rapports/services/creances_pdf_service.dart';
import 'package:erp/modules/stock/services/creance_service.dart';
import 'package:erp/shared/models/creance.dart';
import 'package:erp/shared/ui/theme/app_breakpoints.dart';
import 'package:erp/shared/ui/theme/app_colors.dart';
import 'package:erp/shared/ui/theme/app_spacing.dart';
import 'package:erp/shared/ui/widgets/adaptive_table.dart';
import 'package:erp/shared/ui/widgets/dialog_body.dart';
import 'package:erp/shared/ui/widgets/empty_state.dart';
import 'package:erp/shared/ui/widgets/kpi_card.dart';
import 'package:erp/shared/ui/widgets/page_header.dart';
import 'package:erp/shared/ui/widgets/row_actions.dart';
import 'package:erp/shared/ui/widgets/skeleton.dart';

/// Ce que les clients doivent.
///
/// La liste va du plus gros encours au plus petit, parce que c'est
/// l'ordre dans lequel on décroche le téléphone, et l'ancienneté est
/// une colonne et non une note : 200 000 dus depuis quatre mois et
/// 200 000 dus depuis huit jours ne se traitent pas pareil.
///
/// Rien ici n'est stocké. L'encours se recalcule à chaque ouverture à
/// partir des tickets et de leurs règlements, ce qui garantit qu'une
/// ligne corrigée dans Transactions se voit immédiatement plutôt que
/// de se découvrir en allant relancer quelqu'un qui a déjà payé.
class CreancesScreen extends StatefulWidget {
  const CreancesScreen({super.key});

  @override
  State<CreancesScreen> createState() => _CreancesScreenState();
}

class _CreancesScreenState extends State<CreancesScreen> {
  final _service = CreanceService();
  final _parametres = ParametresService();

  late DateTime _arrete;
  late Future<EtatCreances> _future;
  bool _impression = false;

  @override
  void initState() {
    super.initState();
    _arrete = DateTime.now();
    _future = _service.etat(au: _arrete);
    DataRefreshBus.instance.addListener(_recharger);
  }

  @override
  void dispose() {
    DataRefreshBus.instance.removeListener(_recharger);
    super.dispose();
  }

  void _recharger() {
    if (!mounted) return;
    // Corps en bloc : une flèche *retourne* le Future à `setState`, qui
    // refuse de le poser et laisse l'écran sur ses données d'avant.
    setState(() {
      _future = _service.etat(au: _arrete);
    });
  }

  Future<void> _choisirDate() async {
    final choisi = await showDatePicker(
      context: context,
      initialDate: _arrete,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: 'Arrêter les créances au',
    );
    if (choisi == null) return;
    setState(() => _arrete = choisi);
    _recharger();
  }

  Future<void> _imprimer(EtatCreances etat) async {
    setState(() => _impression = true);
    try {
      final societe = await _parametres.societe();
      final bytes = await CreancesPdfService.buildInBackground(
        CreancesPdfRequest(etat: etat, societe: societe),
      );
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'Créances au ${etat.arreteAu}',
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

  void _ouvrirDetail(CreanceClient client) {
    showDialog<void>(
      context: context,
      builder: (_) => _DetailClient(client: client),
    );
  }

  String get _iso =>
      '${_arrete.year.toString().padLeft(4, '0')}-'
      '${_arrete.month.toString().padLeft(2, '0')}-'
      '${_arrete.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final taille = context.windowSize;
    return FutureBuilder<EtatCreances>(
      future: _future,
      builder: (context, snapshot) {
        final etat = snapshot.data;
        return Column(
          children: [
            PageHeader(
              title: 'Créances',
              subtitle: 'Ce que les clients doivent, et depuis quand',
              actions: [
                OutlinedButton.icon(
                  onPressed: _choisirDate,
                  icon: const Icon(Icons.event_outlined, size: 18),
                  label: Text(_iso),
                ),
                ElevatedButton.icon(
                  onPressed: etat == null || _impression
                      ? null
                      : () => _imprimer(etat),
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

  Widget _corps(WindowSize taille, AsyncSnapshot<EtatCreances> snapshot) {
    final padding = AppSpacing.pagePadding(taille);

    if (snapshot.hasError) {
      return AppErrorState(
        message: messagePour(snapshot.error!, operation: 'les créances'),
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

    final depassements = etat.auDessusDuPlafond.length;

    return ListView(
      padding: padding,
      children: [
        KpiRow(cards: [
          KpiCard(
            icon: Icons.account_balance_wallet_outlined,
            label: 'Total dû',
            value: etat.total.formate(),
            color: AppColors.accentLight,
          ),
          KpiCard(
            icon: Icons.people_outline,
            label: 'Clients concernés',
            value: '${etat.clients.length}',
            color: AppColors.textSecondary,
          ),
          KpiCard(
            icon: Icons.hourglass_bottom_outlined,
            label: 'Plus de 90 jours',
            value: etat.parTranche(TrancheAge.ancien).formate(),
            color: AppColors.error,
          ),
          KpiCard(
            icon: Icons.gpp_maybe_outlined,
            label: 'Au-dessus du plafond',
            value: '$depassements',
            color: depassements > 0 ? AppColors.warning : AppColors.success,
          ),
        ]),
        if (etat.aDesReserves) ...[
          const SizedBox(height: AppSpacing.lg),
          _Reserves(etat: etat),
        ],
        const SizedBox(height: AppSpacing.lg),
        _table(etat),
      ],
    );
  }

  Widget _table(EtatCreances etat) {
    final court = context.windowSize.isCompact;
    return AdaptiveTable(
      shrinkWrap: true,
      minTableWidth: court ? 420 : 860,
      columns: court
          ? const [
              AppColumn('CLIENT', flex: 30),
              AppColumn.number('TOTAL DÛ', flex: 18),
              AppColumn.actions(flex: 10),
            ]
          : const [
              AppColumn('CLIENT', flex: 22),
              AppColumn('TÉLÉPHONE', flex: 13),
              AppColumn.number('0-30 J', flex: 11),
              AppColumn.number('31-60 J', flex: 11),
              AppColumn.number('61-90 J', flex: 11),
              AppColumn.number('+90 J', flex: 11),
              AppColumn.number('TOTAL DÛ', flex: 13),
              AppColumn.actions(flex: 8),
            ],
      empty: const AppEmptyState(
        icon: Icons.verified_outlined,
        title: 'Aucune créance',
        message: 'Tous les tickets sont réglés à cette date. '
            'Les ventes laissées à crédit apparaîtront ici.',
      ),
      rows: [
        for (final client in etat.clients)
          AppRow(
            onTap: () => _ouvrirDetail(client),
            // Le liseré rouge marque un plafond dépassé : c'est la
            // seule ligne qu'on regarde avant les autres.
            accent: client.depassePlafond ? AppColors.error : null,
            cells: court
                ? [
                    _cellNom(client),
                    Cells.number(client.encours.formate(avecSymbole: false),
                        strong: true),
                    _actions(client),
                  ]
                : [
                    _cellNom(client),
                    client.telephone == null || client.telephone!.isEmpty
                        ? Cells.blank
                        : Cells.muted(client.telephone!),
                    _tranche(client, TrancheAge.courant),
                    _tranche(client, TrancheAge.unMois),
                    _tranche(client, TrancheAge.deuxMois),
                    _tranche(client, TrancheAge.ancien,
                        couleur: AppColors.error),
                    Cells.number(client.encours.formate(avecSymbole: false),
                        strong: true),
                    _actions(client),
                  ],
          ),
      ],
    );
  }

  Widget _cellNom(CreanceClient client) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (client.depassePlafond) ...[
            const Icon(Icons.gpp_maybe_outlined,
                size: 15, color: AppColors.error),
            const SizedBox(width: 6),
          ],
          Flexible(child: Cells.text(client.nom)),
        ],
      );

  /// Une tranche vide reste vide plutôt que d'afficher zéro : la
  /// colonne se lit d'un coup quand seules les cases qui portent
  /// quelque chose sont remplies.
  Widget _tranche(CreanceClient client, TrancheAge tranche, {Color? couleur}) {
    final montant = client.parTranche(tranche);
    if (montant.estZero) return const SizedBox.shrink();
    return Cells.number(montant.formate(avecSymbole: false), color: couleur);
  }

  Widget _actions(CreanceClient client) => RowActions(
        actions: [
          RowAction(
            icon: Icons.receipt_long_outlined,
            tooltip: 'Tickets impayés',
            onPressed: () => _ouvrirDetail(client),
          ),
        ],
      );
}

/// Les réserves : ce que l'état ne sait pas dire.
///
/// Affiché seulement quand il y a quelque chose à dire. Montré tout le
/// temps, ce bandeau deviendrait du mobilier que personne ne lit.
class _Reserves extends StatelessWidget {
  final EtatCreances etat;

  const _Reserves({required this.etat});

  @override
  Widget build(BuildContext context) {
    final phrases = <String>[
      if (etat.ticketsSansClient > 0)
        '${etat.ticketsSansClient} ticket(s) impayé(s) sans fiche client, '
            'soit ${etat.sansClient.formate()} : personne à relancer, et '
            'ces sommes ne sont pas dans le total.',
      if (etat.ticketsSansDate > 0)
        '${etat.ticketsSansDate} ticket(s) sans date lisible : comptés '
            'dans le total, absents des colonnes d\'ancienneté.',
    ];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.anomaly.withValues(alpha: 0.10),
        border: Border.all(color: AppColors.anomaly.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18, color: AppColors.anomaly),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final phrase in phrases)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Text(phrase,
                        style: const TextStyle(
                            fontSize: 12.5, color: AppColors.anomaly)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Les tickets impayés d'un client, du plus ancien au plus récent.
///
/// C'est ce qu'on lit au téléphone : « la facture du 2 mai, 40 000, il
/// reste 15 000 ». Un encours global ne permet pas cette conversation.
class _DetailClient extends StatelessWidget {
  final CreanceClient client;

  const _DetailClient({required this.client});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(client.nom),
          Text(
            [
              client.code,
              if (client.telephone != null && client.telephone!.isNotEmpty)
                client.telephone!,
            ].join(' · '),
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
      content: DialogBody(
        maxWidth: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (client.depassePlafond)
              Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                // Les trois nombres : un dépassement qui ne dit pas de
                // combien n'aide personne à décider.
                child: Text(
                  '${client.encours.formate()} dû pour un plafond de '
                  '${client.plafond!.formate()}, soit '
                  '${client.depassement.formate()} de trop.',
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.error),
                ),
              ),
            for (final ticket in client.tickets)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(ticket.ticket,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                          Text(
                            [
                              ticket.date,
                              if (ticket.jours != null)
                                '${ticket.jours} jour(s)'
                              else
                                'date illisible',
                              if (!ticket.regle.estZero)
                                'réglé ${ticket.regle.formate(avecSymbole: false)}'
                                    ' sur ${ticket.total.formate(avecSymbole: false)}',
                            ].join(' · '),
                            style: const TextStyle(
                                fontSize: 11.5,
                                color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      ticket.reste.formate(),
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: ticket.tranche == TrancheAge.ancien
                            ? AppColors.error
                            : AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total dû',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                Text(client.encours.formate(),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fermer'),
        ),
      ],
    );
  }
}
