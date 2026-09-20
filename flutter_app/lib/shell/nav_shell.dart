import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:socogen/core/auth/auth_provider.dart';
import 'package:socogen/core/auth/permissions.dart';
import 'package:socogen/modules/rapports/ui/dashboard_screen.dart';
import 'package:socogen/modules/stock/ui/entries_screen.dart';
import 'package:socogen/modules/stock/ui/inventory_screen.dart';
import 'package:socogen/modules/stock/ui/outputs_screen.dart';
import 'package:socogen/modules/catalogue/ui/products_screen.dart';
import 'package:socogen/modules/rapports/ui/reports_screen.dart';
import 'package:socogen/modules/utilisateurs/ui/security_screen.dart';
import 'package:socogen/modules/parametres/ui/settings_screen.dart';
import 'package:socogen/modules/stock/ui/stores_screen.dart';
import 'package:socogen/modules/tiers/ui/tiers_screen.dart';
import 'package:socogen/modules/stock/ui/transactions_screen.dart';
import 'package:socogen/shared/ui/theme/app_branding.dart';
import 'package:socogen/shared/ui/theme/app_breakpoints.dart';
import 'package:socogen/shared/ui/theme/app_colors.dart';
import 'package:socogen/shared/ui/theme/app_spacing.dart';
import 'package:socogen/shared/ui/theme/app_text_styles.dart';
import 'package:socogen/core/auth/ui/change_password_dialog.dart';
import 'package:socogen/shared/ui/widgets/logo_mark.dart';

class NavigationController extends ChangeNotifier {
  int _selectedIndex = 0;

  int get selectedIndex => _selectedIndex;

  void select(int index) {
    if (_selectedIndex == index) return;
    _selectedIndex = index;
    notifyListeners();
  }
}

class _NavEntry {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  /// Shorter label for the bottom bar, where space is tight.
  final String shortLabel;

  const _NavEntry(this.icon, this.selectedIcon, this.label, [String? short])
      : shortLabel = short ?? label;
}

const List<_NavEntry> _navEntries = [
  _NavEntry(Icons.dashboard_outlined, Icons.dashboard, 'Tableau de bord',
      'Accueil'),
  _NavEntry(Icons.inventory_2_outlined, Icons.inventory_2, 'Produits'),
  _NavEntry(Icons.call_received, Icons.call_received, 'Entrées'),
  _NavEntry(Icons.call_made, Icons.call_made, 'Sorties'),
  _NavEntry(Icons.swap_horiz, Icons.swap_horiz, 'Transactions'),
  _NavEntry(Icons.fact_check_outlined, Icons.fact_check, 'Inventaire'),
  _NavEntry(Icons.bar_chart_outlined, Icons.bar_chart, 'Rapports'),
  _NavEntry(Icons.contacts_outlined, Icons.contacts, 'Tiers'),
  _NavEntry(Icons.store_outlined, Icons.store, 'Magasins'),
  _NavEntry(Icons.security_outlined, Icons.security, 'Sécurité'),
  _NavEntry(Icons.settings_outlined, Icons.settings, 'Paramètres'),
];

/// Number of trailing entries/screens reserved for admins only
/// (Sécurité and Paramètres).
const int _adminOnlyCount = 2;

/// Indices that start a new visual section in the sidebar
/// (a divider is drawn above each, except the first).
///
/// Sections are: the daily stock screens, then the ledger ones
/// (Transactions, Inventaire, Rapports), then the reference and
/// administration ones (Tiers, Magasins, Sécurité, Paramètres). These
/// are positions into [_navEntries] -- inserting a destination moves
/// them.
const List<int> _sectionStarts = [4, 7];

/// Destinations that get a slot in the phone bottom bar. The rest live
/// behind the trailing "Plus" destination.
const int _bottomBarCount = 4;

const List<Widget> _screens = [
  DashboardScreen(),
  ProductsScreen(),
  EntriesScreen(),
  OutputsScreen(),
  TransactionsScreen(),
  InventoryScreen(),
  ReportsScreen(),
  TiersScreen(),
  StoresScreen(),
  SecurityScreen(),
  SettingsScreen(),
];

/// Les deux dernières destinations — Sécurité et Paramètres — demandent
/// des droits d'administration. Le shell les retire plutôt que de les
/// afficher désactivées : une entrée de menu qui refuse de s'ouvrir
/// n'apprend rien à personne.
bool _peutAdministrer(PermissionGate droits) =>
    droits.autorise(Permissions.gererUtilisateurs) &&
    droits.autorise(Permissions.modifierParametres);

List<_NavEntry> _visibleEntries(PermissionGate droits) =>
    _peutAdministrer(droits)
        ? _navEntries
        : _navEntries.sublist(0, _navEntries.length - _adminOnlyCount);

/// Doit rester aligné sur [_visibleEntries] : les deux listes sont
/// positionnelles et un décalage ouvrirait le mauvais écran.
List<Widget> _visibleScreens(PermissionGate droits) =>
    _peutAdministrer(droits)
        ? _screens
        : _screens.sublist(0, _screens.length - _adminOnlyCount);

/// Adaptive application shell.
///
/// The navigation surface follows the window size class rather than a
/// single breakpoint: a bottom bar on phones, an icon rail on tablets
/// and small windows, and a labelled sidebar on the desktop. The page
/// content itself is identical in all three, and screen state survives
/// every switch because the pages stay mounted in an [IndexedStack].
class NavShell extends StatelessWidget {
  const NavShell({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => NavigationController(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = AppBreakpoints.of(constraints.maxWidth);
          final droits = PermissionGate(
            context.watch<AuthProvider>().currentUser?.role,
          );
          final entries = _visibleEntries(droits);
          final screens = _visibleScreens(droits);
          final selected = context.watch<NavigationController>().selectedIndex;
          final index = selected < screens.length ? selected : 0;

          switch (size) {
            case WindowSize.compact:
              return _CompactShell(
                entries: entries,
                screens: screens,
                index: index,
              );
            case WindowSize.medium:
              return _RailShell(
                entries: entries,
                screens: screens,
                index: index,
              );
            case WindowSize.expanded:
            case WindowSize.large:
              return _SidebarShell(
                entries: entries,
                screens: screens,
                index: index,
              );
          }
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Phone: app bar + bottom navigation, overflow behind "Plus".
// ---------------------------------------------------------------------------

class _CompactShell extends StatelessWidget {
  final List<_NavEntry> entries;
  final List<Widget> screens;
  final int index;

  const _CompactShell({
    required this.entries,
    required this.screens,
    required this.index,
  });

  /// Bottom-bar slot for the current page: either its own slot, or the
  /// trailing "Plus" slot when the page lives in the overflow sheet.
  int get _barIndex => index < _bottomBarCount ? index : _bottomBarCount;

  Future<void> _openMore(BuildContext context) async {
    final controller = context.read<NavigationController>();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.xl,
                0,
                AppSpacing.xl,
                AppSpacing.sm,
              ),
              child: Text('NAVIGATION', style: AppTextStyles.sectionLabel),
            ),
            for (var i = _bottomBarCount; i < entries.length; i++)
              ListTile(
                leading: Icon(
                  index == i ? entries[i].selectedIcon : entries[i].icon,
                  color: index == i
                      ? AppColors.accentLight
                      : AppColors.textSecondary,
                ),
                title: Text(
                  entries[i].label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight:
                        index == i ? FontWeight.w700 : FontWeight.w500,
                    color: index == i
                        ? AppColors.accentLight
                        : AppColors.textPrimary,
                  ),
                ),
                selected: index == i,
                onTap: () {
                  controller.select(i);
                  Navigator.of(sheetContext).pop();
                },
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.read<NavigationController>();
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        titleSpacing: AppSpacing.lg,
        title: Text(entries[index].label),
        actions: const [_AccountMenuButton(), SizedBox(width: AppSpacing.xs)],
      ),
      body: _AnimatedIndexedStack(index: index, children: screens),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: NavigationBar(
          selectedIndex: _barIndex,
          onDestinationSelected: (i) {
            if (i < _bottomBarCount) {
              controller.select(i);
            } else {
              _openMore(context);
            }
          },
          destinations: [
            for (var i = 0; i < _bottomBarCount && i < entries.length; i++)
              NavigationDestination(
                icon: Icon(entries[i].icon),
                selectedIcon: Icon(entries[i].selectedIcon),
                label: entries[i].shortLabel,
              ),
            const NavigationDestination(
              icon: Icon(Icons.more_horiz),
              selectedIcon: Icon(Icons.more_horiz),
              label: 'Plus',
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tablet / small window: icon rail.
// ---------------------------------------------------------------------------

class _RailShell extends StatelessWidget {
  final List<_NavEntry> entries;
  final List<Widget> screens;
  final int index;

  const _RailShell({
    required this.entries,
    required this.screens,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final controller = context.read<NavigationController>();
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Row(
        children: [
          DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(right: BorderSide(color: AppColors.border)),
            ),
            // `scrollable` lets the destination list scroll on short
            // windows; `trailingAtBottom` pins the account button to the
            // foot of the rail instead of after the last destination.
            child: NavigationRail(
              selectedIndex: index,
              onDestinationSelected: controller.select,
              labelType: NavigationRailLabelType.all,
              groupAlignment: -1,
              scrollable: true,
              trailingAtBottom: true,
              leading: const Padding(
                padding: EdgeInsets.only(top: AppSpacing.sm),
                child: LogoMark(),
              ),
              trailing: const Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.lg),
                child: _AccountMenuButton(),
              ),
              destinations: [
                for (final entry in entries)
                  NavigationRailDestination(
                    icon: Icon(entry.icon),
                    selectedIcon: Icon(entry.selectedIcon),
                    label: Text(entry.shortLabel),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _AnimatedIndexedStack(index: index, children: screens),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Desktop: labelled sidebar.
// ---------------------------------------------------------------------------

class _SidebarShell extends StatelessWidget {
  final List<_NavEntry> entries;
  final List<Widget> screens;
  final int index;

  const _SidebarShell({
    required this.entries,
    required this.screens,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Row(
        children: [
          _Sidebar(entries: entries, index: index),
          Expanded(
            child: _AnimatedIndexedStack(index: index, children: screens),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final List<_NavEntry> entries;
  final int index;

  const _Sidebar({required this.entries, required this.index});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 232,
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          const _SidebarHeader(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              children: [
                for (var i = 0; i < entries.length; i++) ...[
                  if (_sectionStarts.contains(i))
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.sm,
                      ),
                      child: Divider(color: AppColors.border, height: 1),
                    ),
                  _NavButton(
                    index: i,
                    entry: entries[i],
                    isActive: index == i,
                  ),
                ],
              ],
            ),
          ),
          const _SidebarFooter(),
        ],
      ),
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      alignment: Alignment.centerLeft,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const LogoMark(),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppBranding.productName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: AppSpacing.xxs),
                Text(AppBranding.tagline, style: AppTextStyles.captionMuted),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarFooter extends StatelessWidget {
  const _SidebarFooter();

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    final roleLabel = (user?.isAdmin ?? false) ? 'Administrateur' : 'Magasinier';
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _Avatar(username: user?.username ?? ''),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      user?.username ?? '',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(roleLabel, style: AppTextStyles.captionMuted),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _FooterActionButton(
                  icon: Icons.lock_outline,
                  label: 'Mot de passe',
                  tooltip: 'Changer le mot de passe',
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (_) => const ChangePasswordDialog(),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _FooterActionButton(
                icon: Icons.logout,
                tooltip: 'Déconnexion',
                onTap: () => context.read<AuthProvider>().logout(),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text('v1.0.0 • SHEMAB', style: AppTextStyles.captionMuted),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String username;

  const _Avatar({required this.username});

  @override
  Widget build(BuildContext context) {
    final initial =
        username.isEmpty ? '?' : username.characters.first.toUpperCase();
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: AppColors.selected,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.5)),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.accentLight,
        ),
      ),
    );
  }
}

/// Account button used by the app bar and the rail: shows who is signed
/// in and offers the two self-service actions.
class _AccountMenuButton extends StatelessWidget {
  const _AccountMenuButton();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;
    final roleLabel = (user?.isAdmin ?? false) ? 'Administrateur' : 'Magasinier';

    return PopupMenuButton<String>(
      tooltip: 'Compte',
      position: PopupMenuPosition.under,
      icon: _Avatar(username: user?.username ?? ''),
      onSelected: (value) {
        switch (value) {
          case 'password':
            showDialog<void>(
              context: context,
              builder: (_) => const ChangePasswordDialog(),
            );
          case 'logout':
            context.read<AuthProvider>().logout();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                user?.username ?? '',
                style: AppTextStyles.bodyStrong,
              ),
              Text(roleLabel, style: AppTextStyles.captionMuted),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'password',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.lock_outline, size: 18),
            title: Text('Changer le mot de passe'),
          ),
        ),
        const PopupMenuItem<String>(
          value: 'logout',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout, size: 18),
            title: Text('Déconnexion'),
          ),
        ),
      ],
    );
  }
}

class _FooterActionButton extends StatelessWidget {
  final IconData icon;
  final String? label;
  final String tooltip;
  final VoidCallback onTap;

  const _FooterActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Container(
            alignment: Alignment.center,
            padding: EdgeInsets.symmetric(
              horizontal: label == null ? AppSpacing.sm : AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: AppColors.textSecondary),
                if (label != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: Text(
                      label!,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.captionMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatefulWidget {
  final int index;
  final _NavEntry entry;
  final bool isActive;

  const _NavButton({
    required this.index,
    required this.entry,
    required this.isActive,
  });

  @override
  State<_NavButton> createState() => _NavButtonState();
}

class _NavButtonState extends State<_NavButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final isActive = widget.isActive;

    Color bg = Colors.transparent;
    Color fg = AppColors.textFaint;
    FontWeight weight = FontWeight.w500;

    if (isActive) {
      bg = AppColors.selected;
      fg = AppColors.accentLight;
      weight = FontWeight.w700;
    } else if (_hovering) {
      bg = AppColors.surface;
      fg = AppColors.textPrimary;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => context.read<NavigationController>().select(widget.index),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 1,
          ),
          child: AnimatedContainer(
            duration: AppDurations.fast,
            curve: AppCurves.standard,
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: AppDurations.fast,
                  width: 3,
                  height: isActive ? 18 : 0,
                  margin: const EdgeInsets.only(right: AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.accentLight,
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                  ),
                ),
                Icon(
                  isActive ? widget.entry.selectedIcon : widget.entry.icon,
                  size: 18,
                  color: fg,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    widget.entry.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: weight,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// An [IndexedStack] that cross-fades when the destination changes.
///
/// Keeping the stack (rather than swapping widgets) means every screen
/// holds on to its scroll position, filters and loaded data; the short
/// fade just removes the hard cut between pages.
class _AnimatedIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;

  const _AnimatedIndexedStack({required this.index, required this.children});

  @override
  State<_AnimatedIndexedStack> createState() => _AnimatedIndexedStackState();
}

class _AnimatedIndexedStackState extends State<_AnimatedIndexedStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppDurations.normal,
    reverseDuration: AppDurations.instant,
    value: 1,
  );

  late int _displayed = widget.index;

  @override
  void didUpdateWidget(covariant _AnimatedIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != _displayed) _switchTo();
  }

  Future<void> _switchTo() async {
    await _controller.reverse();
    if (!mounted) return;
    setState(() => _displayed = widget.index);
    await _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final index =
        _displayed < widget.children.length ? _displayed : 0;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = AppCurves.enter.transform(_controller.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 8),
            child: child,
          ),
        );
      },
      child: IndexedStack(index: index, children: widget.children),
    );
  }
}
