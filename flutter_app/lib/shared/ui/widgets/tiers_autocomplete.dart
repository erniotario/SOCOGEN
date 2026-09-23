import 'package:flutter/material.dart';

import 'package:erp/shared/models/tiers.dart';
import 'package:erp/shared/ui/theme/app_colors.dart';
import 'package:erp/shared/ui/theme/app_spacing.dart';
import 'package:erp/shared/ui/theme/app_text_styles.dart';

/// Le choix du client ou du fournisseur sur un mouvement.
///
/// Le champ reste du texte libre, et c'est délibéré : un magasinier qui
/// reçoit d'un nouveau fournisseur un samedi doit pouvoir enregistrer
/// l'entrée sans aller d'abord créer une fiche. Ce que le champ ajoute,
/// c'est que **choisir soit plus facile que retaper** — la liste sort
/// dès les premières lettres, et un nom inconnu propose explicitement
/// de créer la fiche au lieu de la fabriquer en silence.
///
/// Trois issues, donc, et l'appelant doit les distinguer :
/// une fiche choisie (`onTiersChoisi`), une fiche à créer
/// (`onCreationDemandee`), ou du texte laissé tel quel — le mouvement
/// part alors sans `tiers_id`, ce qui est un manque assumé et
/// rattrapable, pas une erreur.
class TiersAutocomplete extends StatefulWidget {
  final List<Tiers> tiers;
  final TextEditingController controller;

  /// Appelé quand une fiche existante est choisie.
  final ValueChanged<Tiers> onTiersChoisi;

  /// Appelé quand l'utilisateur demande explicitement la création d'une
  /// fiche pour le nom qu'il vient de taper. Passer null retire
  /// l'option — utile là où la création n'a pas sa place.
  final ValueChanged<String>? onCreationDemandee;

  /// Appelé quand le texte cesse de correspondre à la fiche choisie :
  /// l'appelant doit alors oublier le `tiers_id` qu'il gardait.
  final VoidCallback? onChoixAbandonne;

  final String labelText;
  final String hintText;

  const TiersAutocomplete({
    super.key,
    required this.tiers,
    required this.controller,
    required this.onTiersChoisi,
    this.onCreationDemandee,
    this.onChoixAbandonne,
    this.labelText = 'Fournisseur',
    this.hintText = 'Chercher ou saisir…',
  });

  @override
  State<TiersAutocomplete> createState() => _TiersAutocompleteState();
}

/// Ce qu'une ligne de la liste déroulante peut être.
sealed class _Option {
  const _Option();
}

class _OptionFiche extends _Option {
  final Tiers tiers;
  const _OptionFiche(this.tiers);
}

class _OptionCreer extends _Option {
  final String nom;
  const _OptionCreer(this.nom);
}

class _TiersAutocompleteState extends State<TiersAutocomplete> {
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Le menu est un overlay et ne peut pas se mesurer sur le champ :
    // on relève la largeur ici pour qu'il s'aligne dessus.
    return LayoutBuilder(
      builder: (context, constraints) => _construire(constraints.maxWidth),
    );
  }

  Widget _construire(double largeurChamp) {
    return Autocomplete<_Option>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      // Le champ garde le texte tapé, jamais un libellé enrichi : c'est
      // ce texte qui sera écrit sur le mouvement, et il doit rester
      // exactement ce que quelqu'un relira dans l'historique.
      displayStringForOption: (o) => switch (o) {
        _OptionFiche(:final tiers) => tiers.nom,
        _OptionCreer(:final nom) => nom,
      },
      optionsBuilder: (valeur) {
        final saisie = valeur.text.trim();
        if (saisie.isEmpty) return const Iterable<_Option>.empty();
        final requete = saisie.toLowerCase();
        final correspondances = widget.tiers
            .where((t) =>
                t.nom.toLowerCase().contains(requete) ||
                t.code.toLowerCase().contains(requete))
            .toList();
        final exact =
            correspondances.any((t) => t.nom.toLowerCase() == requete);
        return [
          for (final t in correspondances) _OptionFiche(t),
          // L'option de création ne s'affiche que si le nom n'existe pas
          // déjà : proposer de créer « BMC » alors que BMC est juste
          // au-dessus est le meilleur moyen d'obtenir deux BMC.
          if (!exact && widget.onCreationDemandee != null)
            _OptionCreer(saisie),
        ];
      },
      onSelected: (option) {
        switch (option) {
          case _OptionFiche(:final tiers):
            widget.onTiersChoisi(tiers);
          case _OptionCreer(:final nom):
            widget.onCreationDemandee!(nom);
        }
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          textCapitalization: TextCapitalization.characters,
          onChanged: (_) => widget.onChoixAbandonne?.call(),
          decoration: InputDecoration(
            labelText: widget.labelText,
            hintText: widget.hintText,
            prefixIcon: const Icon(Icons.person_search_outlined, size: 18),
          ),
        );
      },
      optionsViewBuilder: (context, choisir, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.borderStrong),
              boxShadow: AppShadows.medium,
            ),
            clipBehavior: Clip.antiAlias,
            // Les options sont des ListTile : sans Material transparent
            // ici, leur encre se peint sur la page derrière l'overlay et
            // les lignes paraissent mortes au toucher.
            child: Material(
              type: MaterialType.transparency,
              child: ConstrainedBox(
                constraints:
                    BoxConstraints(maxHeight: 260, maxWidth: largeurChamp),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (context, i) {
                    final option = options.elementAt(i);
                    return switch (option) {
                      _OptionFiche(:final tiers) => ListTile(
                          dense: true,
                          title: Text(
                            tiers.nom,
                            style: AppTextStyles.body,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            tiers.telephone?.isNotEmpty == true
                                ? '${tiers.code} · ${tiers.telephone}'
                                : tiers.code,
                            style: AppTextStyles.bodyMuted,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => choisir(option),
                        ),
                      _OptionCreer(:final nom) => ListTile(
                          dense: true,
                          leading: const Icon(Icons.person_add_alt_1,
                              size: 18, color: AppColors.accentLight),
                          title: Text(
                            'Créer la fiche « $nom »',
                            style: AppTextStyles.body
                                .copyWith(color: AppColors.accentLight),
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => choisir(option),
                        ),
                    };
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
