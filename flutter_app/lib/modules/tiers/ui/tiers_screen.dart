import 'package:flutter/material.dart';

import 'package:socogen/core/errors/messages.dart';
import 'package:socogen/core/events/data_refresh_bus.dart';
import 'package:socogen/core/money/montant.dart';
import 'package:socogen/shared/models/tiers.dart';
import 'package:socogen/modules/tiers/repositories/tiers_repository.dart';
import 'package:socogen/shared/ui/theme/app_breakpoints.dart';
import 'package:socogen/shared/ui/theme/app_colors.dart';
import 'package:socogen/shared/ui/theme/app_spacing.dart';
import 'package:socogen/shared/ui/theme/app_text_styles.dart';
import 'package:socogen/shared/ui/widgets/adaptive_table.dart';
import 'package:socogen/shared/ui/widgets/empty_state.dart';
import 'package:socogen/shared/ui/widgets/filter_bar.dart';
import 'package:socogen/shared/ui/widgets/page_header.dart';
import 'package:socogen/shared/ui/widgets/row_actions.dart';
import 'package:socogen/shared/ui/widgets/skeleton.dart';

/// Les fiches clients et fournisseurs.
///
/// L'écran existe surtout pour qu'on cesse de retaper un nom de
/// partenaire sur chaque mouvement : c'est ce qui a produit « BMC » à
/// côté de « BCM » dans les données reprises. Deux gestes lui sont
/// propres et n'existent nulle part ailleurs — **fusionner** deux fiches
/// qui désignent le même partenaire, et **désactiver** plutôt que
/// supprimer, puisqu'une fiche avec de l'historique derrière elle n'est
/// pas effaçable.
class TiersScreen extends StatefulWidget {
  const TiersScreen({super.key});

  @override
  State<TiersScreen> createState() => _TiersScreenState();
}

class _TiersScreenState extends State<TiersScreen> {
  final _depot = TiersRepository();

  late Future<List<Tiers>> _future;
  final _rechercheController = TextEditingController();
  TypeTiers? _filtreType;

  /// Les fiches désactivées sont cachées par défaut : elles ne servent
  /// plus à la saisie. On peut les rappeler pour en réactiver une ou
  /// relire ce qu'une fusion a laissé.
  bool _avecInactifs = false;

  @override
  void initState() {
    super.initState();
    _future = _charger();
    DataRefreshBus.instance.addListener(_rafraichir);
  }

  @override
  void dispose() {
    DataRefreshBus.instance.removeListener(_rafraichir);
    _rechercheController.dispose();
    super.dispose();
  }

  Future<List<Tiers>> _charger() {
    final terme = _rechercheController.text.trim();
    if (terme.isEmpty) {
      return _depot.getAll(type: _filtreType, actifsSeuls: !_avecInactifs);
    }
    return _depot.rechercher(terme, type: _filtreType);
  }

  Future<void> _rafraichir() async {
    final fiches = await _charger();
    if (!mounted) return;
    setState(() => _future = Future.value(fiches));
  }

  void _onChanged() {
    _rafraichir();
    // Les écrans de saisie proposent ces fiches dans leurs listes ;
    // ils doivent voir la création tout de suite.
    DataRefreshBus.instance.notifyChanged();
  }

  bool get _filtreActif =>
      _rechercheController.text.trim().isNotEmpty ||
      _filtreType != null ||
      _avecInactifs;

  void _reinitialiser() {
    _rechercheController.clear();
    setState(() {
      _filtreType = null;
      _avecInactifs = false;
    });
    _rafraichir();
  }

  Future<void> _ouvrirFormulaire({Tiers? existant}) async {
    final enregistre = await showDialog<bool>(
      context: context,
      builder: (_) => _FormulaireTiers(existant: existant),
    );
    if (enregistre == true) _onChanged();
  }

  Future<void> _basculerActivation(Tiers tiers) async {
    if (!tiers.actif) {
      await _depot.reactiver(tiers.id);
      _onChanged();
      return;
    }

    final mouvements = await _depot.compterMouvements(tiers.id);
    if (!mounted) return;
    final confirme = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Désactiver la fiche'),
        content: Text(
          mouvements == 0
              ? '« ${tiers.nom} » ne sera plus proposé à la saisie. '
                  'Vous pourrez le réactiver à tout moment.'
              : '« ${tiers.nom} » ne sera plus proposé à la saisie. '
                  'Ses $mouvements mouvements restent dans l\'historique '
                  'et gardent son nom.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Désactiver'),
          ),
        ],
      ),
    );
    if (confirme != true) return;
    await _depot.desactiver(tiers.id);
    _onChanged();
  }

  Future<void> _fusionner(Tiers source) async {
    final candidats = (await _depot.getAll())
        .where((t) => t.id != source.id)
        .toList();
    if (!mounted) return;
    if (candidats.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Il n\'y a pas d\'autre fiche vers '
            'laquelle fusionner.')),
      );
      return;
    }
    final deplaces = await showDialog<int>(
      context: context,
      builder: (_) => _DialogueFusion(source: source, candidats: candidats),
    );
    if (deplaces == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(deplaces == 0
            ? 'Fiches réunies. Aucun mouvement à déplacer.'
            : 'Fiches réunies. $deplaces mouvement'
                '${deplaces > 1 ? 's' : ''} déplacé'
                '${deplaces > 1 ? 's' : ''}.'),
      ),
    );
    _onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final taille = context.windowSize;
    return Column(
      children: [
        PageHeader(
          title: 'Tiers',
          subtitle: 'Clients et fournisseurs',
          actions: [
            ElevatedButton.icon(
              onPressed: () => _ouvrirFormulaire(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Nouveau tiers'),
            ),
          ],
        ),
        Expanded(
          child: Padding(
            padding: AppSpacing.pagePadding(taille),
            child: Column(
              children: [
                _filtres(),
                const SizedBox(height: AppSpacing.lg),
                Expanded(
                  child: FutureBuilder<List<Tiers>>(
                    future: _future,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const SkeletonList();
                      }
                      if (snapshot.hasError) {
                        return AppErrorState(
                          message: messagePour(snapshot.error!,
                              operation: 'le chargement des tiers'),
                          onRetry: _rafraichir,
                        );
                      }
                      return RefreshIndicator(
                        onRefresh: _rafraichir,
                        color: AppColors.accentLight,
                        backgroundColor: AppColors.surface,
                        child: _tableau(snapshot.data!),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _filtres() {
    return FilterBar(
      onClear: _filtreActif ? _reinitialiser : null,
      fields: [
        FilterField(
          flex: 3,
          child: TextField(
            controller: _rechercheController,
            onChanged: (_) => _rafraichir(),
            decoration: const InputDecoration(
              labelText: 'Rechercher',
              hintText: 'Nom, code, téléphone ou NIU',
              prefixIcon: Icon(Icons.search, size: 18),
            ),
          ),
        ),
        FilterField(
          child: DropdownButtonFormField<TypeTiers?>(
            initialValue: _filtreType,
            // Sans isExpanded, le menu réclame la largeur naturelle de
            // son libellé le plus long et déborde du panneau de filtres
            // sur une tablette. Avec, le libellé s'élide.
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Type'),
            items: [
              const DropdownMenuItem<TypeTiers?>(
                value: null,
                child: Text('Tous'),
              ),
              for (final type in [TypeTiers.client, TypeTiers.fournisseur])
                DropdownMenuItem<TypeTiers?>(
                  value: type,
                  // Au pluriel : c'est un filtre sur une liste, pas le
                  // rôle d'une fiche.
                  child: Text('${type.libelle}s'),
                ),
            ],
            onChanged: (valeur) {
              setState(() => _filtreType = valeur);
              _rafraichir();
            },
          ),
        ),
        FilterField(
          // Un SwitchListTile a une largeur minimale incompressible et
          // débordait de 47 px sur une tablette. Ce Row rétrécit : le
          // libellé s'élide, l'interrupteur garde sa taille.
          //
          // Le Material transparent n'est pas décoratif non plus — un
          // interrupteur peint son encre sur le Material le plus proche,
          // et le panneau de filtres est un Container décoré. Sans lui,
          // Flutter signale que les éclaboussures seront invisibles.
          child: Material(
            type: MaterialType.transparency,
            child: Row(
              children: [
                Switch(
                  value: _avecInactifs,
                  onChanged: (valeur) {
                    setState(() => _avecInactifs = valeur);
                    _rafraichir();
                  },
                ),
                const SizedBox(width: AppSpacing.sm),
                const Expanded(
                  child: Text(
                    'Fiches désactivées',
                    style: TextStyle(fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _tableau(List<Tiers> fiches) {
    // Un téléphone lit cet écran debout, pour retrouver un contact :
    // le nom, le rôle et le numéro suffisent. Le reste appartient au
    // poste de travail.
    final court = context.showsShortProductList;

    return AdaptiveTable(
      actionsColumn: court ? 3 : 6,
      titleColumn: court ? 0 : 1,
      subtitleColumn: court ? null : 0,
      minTableWidth: court ? 360 : 820,
      columns: [
        if (!court) const AppColumn('CODE', flex: 10),
        const AppColumn('NOM', flex: 32),
        const AppColumn('TYPE', flex: 18),
        const AppColumn('TÉLÉPHONE', flex: 18),
        if (!court) const AppColumn('VILLE', flex: 16),
        if (!court) const AppColumn.number('MOUVEMENTS', flex: 16),
        AppColumn.actions(flex: court ? 16 : 14),
      ],
      empty: AppEmptyState(
        icon: Icons.contacts_outlined,
        title: _filtreActif ? 'Aucun tiers trouvé' : 'Aucun tiers',
        message: _filtreActif
            ? 'Aucune fiche ne correspond à cette recherche.'
            : 'Créez une fiche pour choisir vos clients et fournisseurs '
                'dans une liste au lieu de les retaper.',
        action: _filtreActif
            ? OutlinedButton.icon(
                onPressed: _reinitialiser,
                icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                label: const Text('Effacer les filtres'),
              )
            : ElevatedButton.icon(
                onPressed: () => _ouvrirFormulaire(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nouveau tiers'),
              ),
      ),
      rows: [
        for (final tiers in fiches)
          AppRow(
            onTap: () => _ouvrirFormulaire(existant: tiers),
            cells: [
              if (!court) Cells.identifier(tiers.code),
              _NomCell(tiers: tiers),
              _BadgeType(type: tiers.type),
              tiers.telephone?.isNotEmpty == true
                  ? Cells.text(tiers.telephone!)
                  : Cells.blank,
              if (!court)
                tiers.ville?.isNotEmpty == true
                    ? Cells.muted(tiers.ville!)
                    : Cells.blank,
              if (!court) _CompteurMouvements(depot: _depot, tiersId: tiers.id),
              RowActions(
                actions: [
                  RowAction(
                    icon: Icons.edit_outlined,
                    tooltip: 'Modifier',
                    onPressed: () => _ouvrirFormulaire(existant: tiers),
                  ),
                  if (tiers.actif)
                    RowAction(
                      icon: Icons.merge_type,
                      tooltip: 'Fusionner avec une autre fiche',
                      onPressed: () => _fusionner(tiers),
                    ),
                  RowAction(
                    icon: tiers.actif
                        ? Icons.person_off_outlined
                        : Icons.person_add_alt,
                    tooltip: tiers.actif ? 'Désactiver' : 'Réactiver',
                    onPressed: () => _basculerActivation(tiers),
                  ),
                ],
              ),
            ],
          ),
      ],
    );
  }
}

/// Le nom, grisé et barré quand la fiche est désactivée — sinon une
/// fiche retirée est indiscernable des autres dans la liste complète.
class _NomCell extends StatelessWidget {
  final Tiers tiers;

  const _NomCell({required this.tiers});

  @override
  Widget build(BuildContext context) {
    if (tiers.actif) return Cells.text(tiers.nom);
    return Text(
      tiers.nom,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTextStyles.tableCell.copyWith(
        color: AppColors.textMuted,
        decoration: TextDecoration.lineThrough,
      ),
    );
  }
}

/// Le rôle, en pastille. « Client et fournisseur » est un état à part
/// entière et non un défaut de saisie : un grossiste achète parfois à
/// qui il vend.
class _BadgeType extends StatelessWidget {
  final TypeTiers type;

  const _BadgeType({required this.type});

  Color get _couleur {
    switch (type) {
      case TypeTiers.client:
        return AppColors.success;
      case TypeTiers.fournisseur:
        return AppColors.accentLight;
      case TypeTiers.lesDeux:
        return AppColors.warning;
    }
  }

  String get _libelleCourt =>
      type == TypeTiers.lesDeux ? 'Les deux' : type.libelle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _couleur.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _couleur.withValues(alpha: 0.4)),
      ),
      child: Text(
        _libelleCourt,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: _couleur,
        ),
      ),
    );
  }
}

/// Combien de mouvements portent cette fiche.
///
/// Chargé par ligne, donc une requête par fiche affichée. C'est le
/// compromis assumé ici : la liste tient sur un écran, et le compte est
/// ce qui dit si une fiche peut être fusionnée sans y regarder à deux
/// fois. Si la liste devait s'allonger, ce compte se ferait en une
/// jointure agrégée au chargement — la même leçon que le rapport.
class _CompteurMouvements extends StatelessWidget {
  final TiersRepository depot;
  final int tiersId;

  const _CompteurMouvements({required this.depot, required this.tiersId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: depot.compterMouvements(tiersId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return Cells.blank;
        return Cells.number(
          snapshot.data!,
          color: snapshot.data! == 0 ? AppColors.textMuted : null,
        );
      },
    );
  }
}

/// Création et modification d'une fiche.
class _FormulaireTiers extends StatefulWidget {
  final Tiers? existant;

  const _FormulaireTiers({this.existant});

  @override
  State<_FormulaireTiers> createState() => _FormulaireTiersState();
}

class _FormulaireTiersState extends State<_FormulaireTiers> {
  final _depot = TiersRepository();

  late final TextEditingController _nom;
  late final TextEditingController _telephone;
  late final TextEditingController _email;
  late final TextEditingController _ville;
  late final TextEditingController _adresse;
  late final TextEditingController _niu;
  late final TextEditingController _rccm;
  late final TextEditingController _plafond;
  late final TextEditingController _notes;

  late TypeTiers _type;
  String? _erreur;
  bool _enregistrement = false;

  bool get _modification => widget.existant != null;

  @override
  void initState() {
    super.initState();
    final t = widget.existant;
    _nom = TextEditingController(text: t?.nom ?? '');
    _telephone = TextEditingController(text: t?.telephone ?? '');
    _email = TextEditingController(text: t?.email ?? '');
    _ville = TextEditingController(text: t?.ville ?? '');
    _adresse = TextEditingController(text: t?.adresse ?? '');
    _niu = TextEditingController(text: t?.niu ?? '');
    _rccm = TextEditingController(text: t?.rccm ?? '');
    _notes = TextEditingController(text: t?.notes ?? '');
    // Vide veut dire « pas de plafond ». Un zéro affiché ici se lirait
    // comme « aucun crédit autorisé », qui est une décision, pas un
    // défaut.
    _plafond = TextEditingController(
      text: t?.plafondCreditUnites == null
          ? ''
          : Montant(t!.plafondCreditUnites!).formate(avecSymbole: false),
    );
    _type = t?.type ?? TypeTiers.client;
  }

  @override
  void dispose() {
    for (final c in [
      _nom, _telephone, _email, _ville, _adresse, _niu, _rccm, _plafond, _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _texteOuNull(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  Future<void> _enregistrer() async {
    final nom = _nom.text.trim();
    if (nom.isEmpty) {
      setState(() => _erreur = 'Le nom est obligatoire.');
      return;
    }

    int? plafond;
    final saisiePlafond = _plafond.text.trim();
    if (saisiePlafond.isNotEmpty) {
      final montant = Montant.depuisSaisie(saisiePlafond);
      if (montant == null) {
        setState(() => _erreur =
            'Le plafond de crédit doit être un montant, par exemple 500 000.');
        return;
      }
      if (montant.estNegatif) {
        setState(() =>
            _erreur = 'Un plafond de crédit ne peut pas être négatif.');
        return;
      }
      plafond = montant.unites;
    }

    setState(() {
      _enregistrement = true;
      _erreur = null;
    });

    try {
      final homonyme = await _depot.getParNom(nom);
      if (homonyme != null && homonyme.id != widget.existant?.id) {
        setState(() {
          _erreur = 'Une fiche « ${homonyme.nom} » existe déjà sous le code '
              '${homonyme.code}.';
          _enregistrement = false;
        });
        return;
      }

      if (_modification) {
        await _depot.update(widget.existant!.copyWith(
          nom: nom,
          type: _type,
          niu: _texteOuNull(_niu),
          rccm: _texteOuNull(_rccm),
          telephone: _texteOuNull(_telephone),
          email: _texteOuNull(_email),
          ville: _texteOuNull(_ville),
          adresse: _texteOuNull(_adresse),
          plafondCreditUnites: plafond,
          effacerPlafond: plafond == null,
          notes: _texteOuNull(_notes),
        ));
      } else {
        await _depot.create(Tiers(
          id: 0,
          code: await _depot.prochainCode(_type),
          nom: nom,
          type: _type,
          niu: _texteOuNull(_niu),
          rccm: _texteOuNull(_rccm),
          telephone: _texteOuNull(_telephone),
          email: _texteOuNull(_email),
          ville: _texteOuNull(_ville),
          adresse: _texteOuNull(_adresse),
          plafondCreditUnites: plafond,
          notes: _texteOuNull(_notes),
        ));
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _erreur = messagePour(e,
            operation: _modification
                ? 'la modification de la fiche'
                : 'la création de la fiche');
        _enregistrement = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_modification
          ? 'Modifier ${widget.existant!.code}'
          : 'Nouveau tiers'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nom,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Nom ou raison sociale *',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<TypeTiers>(
                initialValue: _type,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Type'),
                items: [
                  for (final type in TypeTiers.values)
                    DropdownMenuItem(value: type, child: Text(type.libelle)),
                ],
                onChanged: (valeur) {
                  if (valeur != null) setState(() => _type = valeur);
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              const Text('CONTACT', style: AppTextStyles.sectionLabel),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _telephone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Téléphone',
                        hintText: 'Ex : 699 11 22 33',
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: TextField(
                      controller: _ville,
                      decoration: const InputDecoration(labelText: 'Ville'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'E-mail'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _adresse,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Adresse'),
              ),
              const SizedBox(height: AppSpacing.lg),
              const Text('IDENTIFIANTS LÉGAUX',
                  style: AppTextStyles.sectionLabel),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _niu,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'NIU',
                        hintText: 'Identifiant fiscal',
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: TextField(
                      controller: _rccm,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(labelText: 'RCCM'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _plafond,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Plafond de crédit',
                  // Le texte d'aide porte la distinction : laisser vide
                  // n'est pas la même chose que saisir 0.
                  helperText: 'Laisser vide : pas de plafond',
                  suffixText: 'FCFA',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _notes,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
              if (_erreur != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  _erreur!,
                  style: const TextStyle(color: AppColors.error, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              _enregistrement ? null : () => Navigator.pop(context, false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _enregistrement ? null : _enregistrer,
          child: _enregistrement
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_modification ? 'Enregistrer' : 'Créer'),
        ),
      ],
    );
  }
}

/// Réunir deux fiches qui désignent le même partenaire.
///
/// La reprise automatique s'est délibérément gardée de rapprocher « BMC »
/// et « BCM » : décider que deux noms désignent la même entreprise est un
/// jugement, pas une règle. Ce dialogue est l'endroit où ce jugement se
/// pose, et il dit ce qu'il va faire avant de le faire.
class _DialogueFusion extends StatefulWidget {
  final Tiers source;
  final List<Tiers> candidats;

  const _DialogueFusion({required this.source, required this.candidats});

  @override
  State<_DialogueFusion> createState() => _DialogueFusionState();
}

class _DialogueFusionState extends State<_DialogueFusion> {
  final _depot = TiersRepository();

  Tiers? _cible;
  String? _erreur;
  bool _enCours = false;

  Future<void> _fusionner() async {
    final cible = _cible;
    if (cible == null) {
      setState(() => _erreur = 'Choisissez la fiche à conserver.');
      return;
    }
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      final deplaces = await _depot.fusionner(
        sourceId: widget.source.id,
        cibleId: cible.id,
      );
      if (!mounted) return;
      Navigator.pop(context, deplaces);
    } catch (e) {
      setState(() {
        _erreur = messagePour(e, operation: 'la fusion des fiches');
        _enCours = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Fusionner deux fiches'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Les mouvements de « ${widget.source.nom} » '
              '(${widget.source.code}) passeront à la fiche conservée, qui '
              'gardera son nom. « ${widget.source.nom} » sera désactivée, '
              'jamais supprimée.',
              style: AppTextStyles.bodyMuted,
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<Tiers>(
              initialValue: _cible,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Fiche à conserver'),
              items: [
                for (final t in widget.candidats)
                  DropdownMenuItem(
                    value: t,
                    child: Text('${t.code} — ${t.nom}',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (valeur) => setState(() => _cible = valeur),
            ),
            const SizedBox(height: AppSpacing.md),
            // Le texte déjà saisi reste sur chaque ligne : c'est la
            // règle du domaine, et c'est ce qui rend la fusion relisible
            // plus tard. Autant le dire ici plutôt que de le laisser
            // surprendre dans Transactions.
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.accentLight.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                    color: AppColors.accentLight.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline,
                      size: 16, color: AppColors.accentLight),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Dans l\'historique, chaque mouvement continuera '
                      'd\'afficher le nom tapé ce jour-là.',
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
