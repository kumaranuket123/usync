import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/neon_back_button.dart';
import '../../../shared/widgets/toggle_switch.dart';
import '../bloc/settings_bloc.dart';

/// Per-alert choice between "makes a sound" and "silent". Silent alerts still
/// show in the notification shade, just without sound or a heads-up popup.
class AlertSoundsScreen extends StatelessWidget {
  const AlertSoundsScreen({super.key});

  /// Alert groups, keyed by `NotifType.soundGroup`.
  static const groups = [
    _Group('touch',      '👆', Color(0x1FFF2D78), 'Touch',          'Your partner is touching the screen'),
    _Group('doodle',     '✏️', Color(0x1F00D4FF), 'Doodles',        'A new drawing on the canvas'),
    _Group('moodChange', '💭', Color(0x1F9D4EDD), 'Mood updates',   'Your partner shared how they feel'),
    _Group('streak',     '🔥', Color(0x1AFFD700), 'Streaks',        'Streak reminders and records'),
    _Group('milestone',  '💖', Color(0x1FC77DFF), 'Milestones',     'Pairing and anniversaries'),
    _Group('question',   '💬', Color(0x1F00D4FF), 'Daily question', 'Your partner answered the question of the day'),
    _Group('location',   '📍', Color(0x1F00E676), 'Location checks', 'Your partner looks at or requests your location'),
  ];

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
                  Text('Alert sounds', style: AppTextStyles.h2.copyWith(fontSize: 24)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'Turn a switch off to make that alert silent. Silent alerts still appear in your notification shade.',
                style: AppTextStyles.bodyMuted,
              ),
            ),
            Expanded(
              child: BlocBuilder<SettingsBloc, SettingsState>(
                builder: (context, settings) => ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                  children: [
                    for (final g in groups)
                      _SoundRow(
                        group: g,
                        hasSound: !settings.silentTypes.contains(g.key),
                        onChanged: (sound) => context
                            .read<SettingsBloc>()
                            .add(AlertSilenceChanged(group: g.key, silent: !sound)),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Group {
  const _Group(this.key, this.icon, this.iconBg, this.title, this.subtitle);
  final String key, icon, title, subtitle;
  final Color  iconBg;
}

class _SoundRow extends StatelessWidget {
  const _SoundRow({required this.group, required this.hasSound, required this.onChanged});
  final _Group group;
  final bool   hasSound;
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
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(color: group.iconBg, borderRadius: BorderRadius.circular(12)),
            child: Center(child: Text(group.icon, style: const TextStyle(fontSize: 18))),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(group.title, style: AppTextStyles.body.copyWith(fontSize: 15)),
                Text(group.subtitle, style: AppTextStyles.labelSmall),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              ToggleSwitch(value: hasSound, onChanged: onChanged),
              const SizedBox(height: 2),
              Text(hasSound ? 'Sound' : 'Silent', style: AppTextStyles.labelSmall),
            ],
          ),
        ],
      ),
    );
  }
}
