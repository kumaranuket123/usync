import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/neon_back_button.dart';
import '../../../shared/widgets/outline_button.dart';
import '../../../shared/widgets/toggle_switch.dart';
import '../bloc/settings_bloc.dart';
import '../../auth/bloc/auth_bloc.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg1,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
              child: Row(
                children: [
                  const NeonBackButton(),
                  const SizedBox(width: 14),
                  Text('Settings', style: AppTextStyles.h2.copyWith(fontSize: 24)),
                ],
              ),
            ),
            Expanded(
              child: BlocBuilder<SettingsBloc, SettingsState>(
                builder: (context, settings) {
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                    children: [
                      Builder(builder: (context) {
                        final auth = context.read<AuthBloc>().state;
                        final user = auth is Authenticated ? auth.user : null;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _SectionLabel('ACCOUNT'),
                            _Row('👤', const Color(0x1FFF2D78), 'Profile',
                                '${user?.username ?? '—'} · ${user?.email ?? ''}',
                                onTap: () {}),
                            _Row('🔒', const Color(0x1F9D4EDD), 'Privacy', 'Manage visibility', onTap: () {}),
                          ],
                        );
                      }),

                      _SectionLabel('CONNECTION'),
                      _Row('💞', const Color(0x1FFF6EC7), 'Couple Settings', 'Connected', onTap: () {}),
                      _ToggleRow('🔔', const Color(0x1F00D4FF), 'Notifications', 'Gentle emotional alerts',
                          value: settings.notificationsEnabled,
                          onChanged: (v) => context.read<SettingsBloc>().add(ToggleChanged(key: 'notifications', value: v))),

                      _SectionLabel('EXPERIENCE'),
                      _Row('🎨', const Color(0x1AFFD700), 'Themes', 'Midnight Purple', onTap: () => context.push(RouteNames.themes)),
                      _ToggleRow('✨', const Color(0x1F9D4EDD), 'Animations', 'Rich particle effects',
                          value: settings.animationsEnabled,
                          onChanged: (v) => context.read<SettingsBloc>().add(ToggleChanged(key: 'animations', value: v))),
                      _ToggleRow('🌙', const Color(0x1F00D4FF), 'Dark Mode', 'Always on', value: true, onChanged: (_) {}),
                      _ToggleRow('📳', const Color(0x1FFF2D78), 'Haptic Feedback', 'Vibrate on partner touch',
                          value: settings.hapticEnabled,
                          onChanged: (v) => context.read<SettingsBloc>().add(ToggleChanged(key: 'haptic', value: v))),

                      _SectionLabel('ABOUT'),
                      _Row('ℹ️', const Color(0x0FFFFFFF), 'About Usync', 'Version 1.0.0', onTap: () {}),

                      const SizedBox(height: 20),
                      UsyncOutlineButton(
                        label: 'Sign Out',
                        textColor:   const Color(0xB3FF5050),
                        borderColor: const Color(0x33FF5050),
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (_) => AlertDialog(
                              backgroundColor: AppColors.bg2,
                              title: const Text('Sign out?', style: TextStyle(color: Colors.white)),
                              content: Text('You can sign back in any time.', style: AppTextStyles.bodyMuted),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted))),
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    context.read<AuthBloc>().add(const SignOutRequested());
                                  },
                                  child: const Text('Sign Out', style: TextStyle(color: Color(0xFFFF5050))),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
    child: Text(label, style: AppTextStyles.labelCaps),
  );
}

class _Row extends StatelessWidget {
  const _Row(this.icon, this.iconBg, this.title, this.subtitle, {required this.onTap});
  final String icon, title, subtitle;
  final Color  iconBg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: AppColors.glass.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.glassBorder.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Container(width: 38, height: 38, decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
              child: Center(child: Text(icon, style: const TextStyle(fontSize: 18)))),
            const SizedBox(width: 13),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: AppTextStyles.body.copyWith(fontSize: 15)),
              Text(subtitle, style: AppTextStyles.labelSmall),
            ])),
            Text('›', style: TextStyle(color: AppColors.textDim, fontSize: 18)),
          ],
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow(this.icon, this.iconBg, this.title, this.subtitle, {required this.value, required this.onChanged});
  final String icon, title, subtitle;
  final Color  iconBg;
  final bool   value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.glass.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.glassBorder.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(width: 38, height: 38, decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
            child: Center(child: Text(icon, style: const TextStyle(fontSize: 18)))),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: AppTextStyles.body.copyWith(fontSize: 15)),
            Text(subtitle, style: AppTextStyles.labelSmall),
          ])),
          ToggleSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
