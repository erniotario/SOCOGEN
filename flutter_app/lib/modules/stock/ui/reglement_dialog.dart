import 'package:flutter/material.dart';

import 'package:socogen/core/errors/messages.dart';
import 'package:socogen/core/money/montant.dart';
import 'package:socogen/modules/stock/services/paiement_service.dart';
import 'package:socogen/shared/models/paiement.dart';
import 'package:socogen/shared/ui/theme/app_colors.dart';
import 'package:socogen/shared/ui/theme/app_spacing.dart';
import 'package:socogen/shared/ui/theme/app_text_styles.dart';

/// Encaisser le règlement d'un ticket.
///
/// Ce que cet écran doit faire bien tient en un chiffre : **la monnaie à
/// rendre**. Un caissier la calcule de tête vingt fois par heure, et
/// c'est là qu'on se trompe. Elle s'affiche donc à mesure que le montant
/// reçu se tape, en gros, sans qu'il faille valider quoi que ce soit.
///
/// Fermer sans régler est permis : le ticket part à crédit, ce qui est
/// une situation normale et non un abandon. Le reste dû se retrouve sur
/// l'encours du client.
class ReglementDialog extends StatefulWidget {
  final String ticket;
  final SoldeTicket solde;
  final PaiementService service;

  /// Le message de dépassement de plafond, calculé avant l'ouverture.
  ///
  /// Calculé en amont plutôt qu'ici : le dialogue montre, il ne décide
  /// pas. Et le caissier doit le voir **avant** de choisir de laisser
  /// partir la marchandise à crédit.
  final String? avertissementCredit;

  const ReglementDialog({
    super.key,
    required this.ticket,
    required this.solde,
    required this.service,
    this.avertissementCredit,
  });

  @override
  State<ReglementDialog> createState() => _ReglementDialogState();
}

class _ReglementDialogState extends State<ReglementDialog> {
  final _montantController = TextEditingController();
  final _referenceController = TextEditingController();

  ModePaiement _mode = ModePaiement.especes;
  late SoldeTicket _solde = widget.solde;
  String? _erreur;
  bool _enCours = false;

  @override
  void initState() {
    super.initState();
    // Prérempli avec ce qui reste dû : c'est le cas courant, et ce qui
    // évite une frappe sur chaque vente réglée d'un coup.
    _montantController.text = _solde.reste.formate(avecSymbole: false);
  }

  @override
  void dispose() {
    _montantController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  Montant? get _saisi =>
      Montant.depuisSaisie(_montantController.text, devise: _solde.total.devise);

  /// Ce qu'il faudra rendre si le caissier encaisse ce montant.
  Montant get _rendu {
    final saisi = _saisi;
    if (saisi == null) return Montant(0, devise: _solde.total.devise);
    final difference = saisi - _solde.reste;
    return difference.estNegatif
        ? Montant(0, devise: _solde.total.devise)
        : difference;
  }

  Future<void> _regler() async {
    final montant = _saisi;
    if (montant == null || !montant.estPositif) {
      setState(() => _erreur = 'Saisissez le montant reçu.');
      return;
    }
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      // On n'enregistre jamais plus que le dû : le surplus est de la
      // monnaie rendue, pas de l'argent encaissé. L'inscrire gonflerait
      // le chiffre d'affaires d'un billet qui est reparti.
      final aEncaisser = montant > _solde.reste ? _solde.reste : montant;
      await widget.service.regler(
        ticket: widget.ticket,
        mode: _mode,
        montant: aEncaisser,
        reference: _referenceController.text,
      );
      final solde = await widget.service.solde(widget.ticket);
      if (!mounted) return;
      if (solde.estRegle) {
        Navigator.pop(context, solde);
        return;
      }
      // Réglé en partie : on reste ouvert pour le second mode.
      setState(() {
        _solde = solde;
        _montantController.text = solde.reste.formate(avecSymbole: false);
        _referenceController.clear();
        _enCours = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = messagePour(e, operation: "l'enregistrement du règlement");
        _enCours = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final rendu = _rendu;
    return AlertDialog(
      title: Text('Règlement · ${widget.ticket}'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _LigneMontant(
                libelle: 'Total',
                montant: _solde.total,
              ),
              if (_solde.regle.estPositif)
                _LigneMontant(libelle: 'Déjà réglé', montant: _solde.regle),
              _LigneMontant(
                libelle: 'Reste à payer',
                montant: _solde.reste,
                fort: true,
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<ModePaiement>(
                initialValue: _mode,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Mode'),
                items: [
                  for (final mode in ModePaiement.values)
                    DropdownMenuItem(value: mode, child: Text(mode.libelle)),
                ],
                onChanged: (v) => setState(() => _mode = v ?? _mode),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _montantController,
                keyboardType: TextInputType.number,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Montant reçu',
                  suffixText: _solde.total.devise.symbole,
                ),
              ),
              if (_mode.aUneReference) ...[
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _referenceController,
                  decoration: InputDecoration(
                    labelText: 'N° de transaction *',
                    helperText: 'La trace qui permet de retrouver l\'argent',
                    hintText: _mode == ModePaiement.mobileMoney
                        ? 'Ex : MP260301.1234.A56789'
                        : null,
                  ),
                ),
              ],
              if (rendu.estPositif) ...[
                const SizedBox(height: AppSpacing.md),
                _Rendu(montant: rendu),
              ],
              if (widget.avertissementCredit != null) ...[
                const SizedBox(height: AppSpacing.md),
                _Avertissement(texte: widget.avertissementCredit!),
              ],
              if (_erreur != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(_erreur!,
                    style:
                        const TextStyle(color: AppColors.error, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _enCours ? null : () => Navigator.pop(context, _solde),
          // Nommé pour ce qu'il fait : le ticket part impayé, ce qui est
          // une situation normale et non un abandon de la saisie.
          child: const Text('Laisser à crédit'),
        ),
        FilledButton(
          onPressed: _enCours ? null : _regler,
          child: _enCours
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Encaisser'),
        ),
      ],
    );
  }
}

class _LigneMontant extends StatelessWidget {
  final String libelle;
  final Montant montant;
  final bool fort;

  const _LigneMontant({
    required this.libelle,
    required this.montant,
    this.fort = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(libelle, style: AppTextStyles.bodyMuted),
          Text(
            montant.formate(),
            style: fort
                ? const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.accentLight,
                  )
                : AppTextStyles.numeric,
          ),
        ],
      ),
    );
  }
}

/// La monnaie à rendre, en gros.
///
/// C'est le chiffre que le caissier lit et exécute ; le mettre à la
/// taille du reste reviendrait à le laisser calculer de tête.
class _Rendu extends StatelessWidget {
  final Montant montant;

  const _Rendu({required this.montant});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('À RENDRE', style: AppTextStyles.sectionLabel),
          Text(
            montant.formate(),
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.success,
            ),
          ),
        ],
      ),
    );
  }
}

class _Avertissement extends StatelessWidget {
  final String texte;

  const _Avertissement({required this.texte});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_outlined,
              size: 16, color: AppColors.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(texte, style: AppTextStyles.bodyMuted)),
        ],
      ),
    );
  }
}
