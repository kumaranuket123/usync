import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/constants/route_names.dart';

/// Shell wrapper — wraps every main-tab screen with the bottom nav.
class UsyncShell extends StatelessWidget {
  const UsyncShell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: const _UsyncBottomNav(),
    );
  }
}

class _UsyncBottomNav extends StatelessWidget {
  const _UsyncBottomNav();

  static const _tabs = [
    _Tab(icon: '🏠', label: 'Home',     route: RouteNames.home),
    _Tab(icon: '🫧', label: 'Memories', route: RouteNames.memories),
    _Tab(icon: '✏️', label: '',         route: RouteNames.canvas,  isCentre: true),
    _Tab(icon: '📱', label: 'Widgets',  route: RouteNames.widgets),
    _Tab(icon: '🦋', label: 'Profile',  route: RouteNames.profile),
  ];

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final primary  = Theme.of(context).colorScheme.primary;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          height: 80 + MediaQuery.paddingOf(context).bottom,
          padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
          decoration: const BoxDecoration(
            color:  Color(0xE0080818),
            border: Border(top: BorderSide(color: AppColors.glassBorder)),
          ),
          child: Row(
            children: _tabs.map((tab) {
              if (tab.isCentre) {
                return Expanded(
                  child: Center(
                    child: GestureDetector(
                      onTap: () => context.go(tab.route),
                      child: Transform.translate(
                        offset: const Offset(0, -14),
                        child: Container(
                          width: 58, height: 58,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [primary, Theme.of(context).colorScheme.secondary],
                            ),
                            boxShadow: [
                              BoxShadow(color: primary.withValues(alpha: 0.5), blurRadius: 22),
                              BoxShadow(color: primary.withValues(alpha: 0.3), blurRadius: 44),
                            ],
                          ),
                          child: Center(
                            child: Text(tab.icon, style: const TextStyle(fontSize: 26)),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }

              final isActive = location.startsWith(tab.route);
              return Expanded(
                child: GestureDetector(
                  onTap: () => context.go(tab.route),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        tab.icon,
                        style: TextStyle(
                          fontSize: 22,
                          shadows: isActive
                              ? [Shadow(color: primary.withValues(alpha: 0.8), blurRadius: 12)]
                              : null,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        tab.label,
                        style: AppTextStyles.labelCaps.copyWith(
                          color:      isActive ? primary : AppColors.textDim,
                          letterSpacing: 0.5,
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(height: 2),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width:  isActive ? 4 : 0,
                        height: isActive ? 4 : 0,
                        decoration: BoxDecoration(
                          color:  primary,
                          shape:  BoxShape.circle,
                          boxShadow: [BoxShadow(color: primary, blurRadius: 6)],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _Tab {
  const _Tab({
    required this.icon,
    required this.label,
    required this.route,
    this.isCentre = false,
  });
  final String icon;
  final String label;
  final String route;
  final bool   isCentre;
}
