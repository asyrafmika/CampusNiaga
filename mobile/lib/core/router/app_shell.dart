import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart';
import 'app_routes.dart';

/// The signed-in app's frame: the tab's page above a bottom navigation bar
/// with Home, Search, Sell, Reservations and Profile. Sell opens the listing
/// form on top instead of switching tab.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const int _sellSlot = 2;

  /// Bar slot → shell branch (the Sell slot has no branch).
  static int? _branchFor(int slot) => switch (slot) {
    0 => 0,
    1 => 1,
    3 => 2,
    4 => 3,
    _ => null,
  };

  static int _slotFor(int branch) => branch >= 2 ? branch + 1 : branch;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _slotFor(navigationShell.currentIndex),
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primarySoft,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (slot) {
          if (slot == _sellSlot) {
            context.push(AppRoutes.sell);
            return;
          }
          final branch = _branchFor(slot)!;
          navigationShell.goBranch(
            branch,
            initialLocation: branch == navigationShell.currentIndex,
          );
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded, color: AppColors.primary),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_rounded),
            selectedIcon: Icon(Icons.search_rounded, color: AppColors.primary),
            label: 'Search',
          ),
          NavigationDestination(
            icon: _SellIcon(),
            label: 'Sell',
            tooltip: 'Sell something',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(
              Icons.receipt_long_rounded,
              color: AppColors.primary,
            ),
            label: 'Reservations',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded, color: AppColors.primary),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class _SellIcon extends StatelessWidget {
  const _SellIcon();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(6),
    decoration: const BoxDecoration(
      gradient: AppColors.brandGradient,
      shape: BoxShape.circle,
    ),
    child: const Icon(Icons.add_rounded, color: Colors.white, size: 22),
  );
}
