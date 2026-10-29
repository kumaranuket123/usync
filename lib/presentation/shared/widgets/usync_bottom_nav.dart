import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/constants/route_names.dart';
import 'encryption_sync_gate.dart';

/// Shell wrapper — wraps every main-tab screen with the bottom nav.
class UsyncShell extends StatelessWidget {
  const UsyncShell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg1,
      body: EncryptionSyncGate(child: child),
      bottomNavigationBar: const _UsyncBottomNav(),
    );
  }
}

/// Floating glass bar: four tabs around a raised centre action (canvas).
class _UsyncBottomNav extends StatelessWidget {
  const _UsyncBottomNav();

  static const _tabs = [
    _Tab(icon: Icons.home_outlined,          activeIcon: Icons.home_rounded,         label: 'Home',     route: RouteNames.home),
    _Tab(icon: Icons.photo_library_outlined, activeIcon: Icons.photo_library,        label: 'Memories', route: RouteNames.memories),
    _Tab(icon: Icons.brush_rounded,          activeIcon: Icons.brush_rounded,        label: 'Draw',     route: RouteNames.canvas, isCentre: true),
    _Tab(icon: Icons.local_activity_outlined, activeIcon: Icons.local_activity,      label: 'Activity', route: RouteNames.activity),
    _Tab(icon: Icons.person_outline_rounded, activeIcon: Icons.person_rounded,       label: 'Profile',  route: RouteNames.profile),
  ];

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final scheme   = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.paddingOf(context).bottom + 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 8)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              height: 68,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color:  const Color(0xCC12122B),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: Row(
                children: [
                  for (final tab in _tabs)
                    Expanded(
                      child: tab.isCentre
                          ? _CentreButton(
                              tab: tab,
                              isActive: location.startsWith(tab.route),
                              primary: scheme.primary,
                              secondary: scheme.secondary,
                            )
                          : _NavItem(
                              tab: tab,
                              isActive: location.startsWith(tab.route),
                              primary: scheme.primary,
                            ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.tab, required this.isActive, required this.primary});
  final _Tab  tab;
  final bool  isActive;
  final Color primary;

  @override
  Widget build(BuildContext context) {
    final color = isActive ? primary : AppColors.textMuted;
    return GestureDetector(
      onTap: () => context.go(tab.route),
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            width: 52, height: 30,
            decoration: BoxDecoration(
              color: isActive ? primary.withValues(alpha: 0.18) : Colors.transparent,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(isActive ? tab.activeIcon : tab.icon, size: 22, color: color),
          ),
          const SizedBox(height: 3),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 220),
            style: TextStyle(
              fontSize: 10.5,
              height: 1.1,
              color: color,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            ),
            child: Text(tab.label),
          ),
        ],
      ),
    );
  }
}

class _CentreButton extends StatelessWidget {
  const _CentreButton({
    required this.tab,
    required this.isActive,
    required this.primary,
    required this.secondary,
  });
  final _Tab  tab;
  final bool  isActive;
  final Color primary, secondary;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.go(tab.route),
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: AnimatedScale(
          duration: const Duration(milliseconds: 220),
          scale: isActive ? 1.0 : 0.92,
          child: Container(
            width: 50, height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end:   Alignment.bottomRight,
                colors: [primary, secondary],
              ),
              boxShadow: [
                BoxShadow(color: primary.withValues(alpha: isActive ? 0.55 : 0.3), blurRadius: 14),
              ],
            ),
            child: Icon(tab.icon, color: Colors.white, size: 24),
          ),
        ),
      ),
    );
  }
}

class _Tab {
  const _Tab({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.route,
    this.isCentre = false,
  });
  final IconData icon;
  final IconData activeIcon;
  final String   label;
  final String   route;
  final bool     isCentre;
}
