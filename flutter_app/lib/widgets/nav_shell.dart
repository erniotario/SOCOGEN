import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_provider.dart';
import '../screens/dashboard_screen.dart';
import '../screens/entries_screen.dart';
import '../screens/outputs_screen.dart';
import '../screens/products_screen.dart';
import '../screens/reports_screen.dart';
import '../screens/security_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/stores_screen.dart';
import '../screens/transactions_screen.dart';
import '../theme/app_colors.dart';
import 'change_password_dialog.dart';

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
  final String label;

  const _NavEntry(this.icon, this.label);
}

const List<_NavEntry> _navEntries = [
  _NavEntry(Icons.dashboard_outlined, 'Tableau de bord'),
  _NavEntry(Icons.inventory_2_outlined, 'Produits'),
  _NavEntry(Icons.call_received, 'Entrées'),
  _NavEntry(Icons.call_made, 'Sorties'),
  _NavEntry(Icons.swap_horiz, 'Transactions'),
  _NavEntry(Icons.bar_chart_outlined, 'Rapports'),
  _NavEntry(Icons.store_outlined, 'Magasins'),
  _NavEntry(Icons.security_outlined, 'Sécurité'),
  _NavEntry(Icons.settings_outlined, 'Paramètres'),
];

/// Number of trailing entries/screens reserved for admins only
/// (Sécurité and Paramètres).
const int _adminOnlyCount = 2;

/// Indices that start a new visual section in the sidebar
/// (a divider is drawn above each, except the first).
const List<int> _sectionStarts = [4, 6];

const List<Widget> _screens = [
  DashboardScreen(),
  ProductsScreen(),
  EntriesScreen(),
  OutputsScreen(),
  TransactionsScreen(),
  ReportsScreen(),
  StoresScreen(),
  SecurityScreen(),
  SettingsScreen(),
];

/// Responsive shell: fixed sidebar on wide screens, drawer on narrow ones.
/// Breakpoint matches the plan's 900px cutoff.
class NavShell extends StatelessWidget {
  const NavShell({super.key});

  static const double breakpoint = 900;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => NavigationController(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= breakpoint) {
            return const _WideShell();
          }
          return const _NarrowShell();
        },
      ),
    );
  }
}

/// Drops the admin-only entries (Sécurité, Paramètres) for non-admin users.
List<_NavEntry> _visibleEntries(bool isAdmin) =>
    isAdmin ? _navEntries : _navEntries.sublist(0, _navEntries.length - _adminOnlyCount);

/// Drops the admin-only screens (SecurityScreen, SettingsScreen) for
/// non-admin users, matching [_visibleEntries].
List<Widget> _visibleScreens(bool isAdmin) =>
    isAdmin ? _screens : _screens.sublist(0, _screens.length - _adminOnlyCount);

class _WideShell extends StatelessWidget {
  const _WideShell();

  @override
  Widget build(BuildContext context) {
    final selected = context.watch<NavigationController>().selectedIndex;
    final isAdmin = context.watch<AuthProvider>().currentUser?.isAdmin ?? false;
    final entries = _visibleEntries(isAdmin);
    final screens = _visibleScreens(isAdmin);
    final index = selected < screens.length ? selected : 0;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Row(
        children: [
          _Sidebar(entries: entries),
          Expanded(
            child: IndexedStack(index: index, children: screens),
          ),
        ],
      ),
    );
  }
}

class _NarrowShell extends StatelessWidget {
  const _NarrowShell();

  @override
  Widget build(BuildContext context) {
    final selected = context.watch<NavigationController>().selectedIndex;
    final isAdmin = context.watch<AuthProvider>().currentUser?.isAdmin ?? false;
    final entries = _visibleEntries(isAdmin);
    final screens = _visibleScreens(isAdmin);
    final index = selected < screens.length ? selected : 0;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.sidebar,
        title: Text(
          entries[index].label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      drawer: Drawer(
        backgroundColor: AppColors.sidebar,
        child: SafeArea(child: _NavList(entries: entries)),
      ),
      body: IndexedStack(index: index, children: screens),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final List<_NavEntry> entries;

  const _Sidebar({required this.entries});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: _NavList(entries: entries),
    );
  }
}

class _NavList extends StatelessWidget {
  final List<_NavEntry> entries;

  const _NavList({required this.entries});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _SidebarHeader(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                if (_sectionStarts.contains(i))
                  const Divider(color: AppColors.border, height: 17),
                _NavButton(index: i, entry: entries[i]),
              ],
            ],
          ),
        ),
        const _SidebarFooter(),
      ],
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.centerLeft,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'SOCOGEN',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.accentLight,
            ),
          ),
          SizedBox(height: 2),
          Text(
            'Gestion de Stock',
            style: TextStyle(fontSize: 10, color: Color(0xFF7D8590)),
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
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.account_circle_outlined, size: 20, color: AppColors.textMuted),
              const SizedBox(width: 8),
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
                    Text(
                      roleLabel,
                      style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _FooterActionButton(
                  icon: Icons.lock_outline,
                  tooltip: 'Changer le mot de passe',
                  onTap: () => showDialog(
                    context: context,
                    builder: (_) => const ChangePasswordDialog(),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _FooterActionButton(
                  icon: Icons.logout,
                  tooltip: 'Déconnexion',
                  onTap: () => context.read<AuthProvider>().logout(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'v1.0.0 • SHEMAB',
            style: TextStyle(fontSize: 9, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _FooterActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _FooterActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: AppColors.border),
          ),
          child: Icon(icon, size: 15, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}

class _NavButton extends StatefulWidget {
  final int index;
  final _NavEntry entry;

  const _NavButton({required this.index, required this.entry});

  @override
  State<_NavButton> createState() => _NavButtonState();
}

class _NavButtonState extends State<_NavButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<NavigationController>();
    final isActive = controller.selectedIndex == widget.index;

    Color bg = Colors.transparent;
    Color fg = const Color(0xFF7D8590);
    FontWeight weight = FontWeight.w500;

    if (isActive) {
      bg = const Color(0xFF1C2D4A);
      fg = AppColors.accentLight;
      weight = FontWeight.w700;
    } else if (_hovering) {
      bg = AppColors.surface;
      fg = AppColors.textPrimary;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          controller.select(widget.index);
          Scaffold.maybeOf(context)?.closeDrawer();
        },
        child: Container(
          height: 42,
          decoration: BoxDecoration(
            color: bg,
            border: Border(
              left: BorderSide(
                color: isActive ? AppColors.accentLight : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          padding: const EdgeInsets.only(left: 13, right: 16),
          child: Row(
            children: [
              Icon(widget.entry.icon, size: 18, color: fg),
              const SizedBox(width: 12),
              Text(
                widget.entry.label,
                style: TextStyle(fontSize: 13, fontWeight: weight, color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
