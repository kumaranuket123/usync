import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../shared/painters/conic_orb_painter.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/gradient_text.dart';
import '../../../shared/widgets/loading_dots.dart';
import '../../../../core/di/injection.dart';
import '../../../features/auth/bloc/auth_bloc.dart';
import '../bloc/profile_bloc.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth     = context.read<AuthBloc>().state;
    final uid      = Supabase.instance.client.auth.currentUser?.id ?? '';
    final coupleId = auth is Authenticated ? (auth.user.coupleId ?? '') : '';
    return BlocProvider(
      create: (_) => getIt<ProfileBloc>()
        ..add(ProfileLoaded(userId: uid, coupleId: coupleId)),
      child: const _ProfileBody(),
    );
  }
}

class _ProfileBody extends StatelessWidget {
  const _ProfileBody();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ProfileBloc, ProfileState>(
      listener: (context, state) {
        if (state is ProfileDisconnected) {
          // Refresh the app-wide user so coupleId is cleared, then re-pair.
          context.read<AuthBloc>().add(const AuthStateChecked());
          context.go(RouteNames.pairInvite);
        }
      },
      builder: (context, state) {
        return Scaffold(
          backgroundColor: AppColors.bg1,
          body: SafeArea(
            child: Column(
              children: [
                // Hero
                _ProfileHero(state: state),
                // Body
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                    children: [
                      _SectionLabel('YOUR CONNECTION'),
                      _NavRow('🕰️', const Color(0x1FFF2D78), 'Relationship Timeline', 'View your shared journey', () => context.push(RouteNames.timeline)),
                      _NavRow('🫧', const Color(0x1F00D4FF), 'Memory Space',
                          state is ProfileReady ? '${state.couple.totalMoments} moments' : 'Your archive',
                          () => context.go(RouteNames.memories)),
                      _NavRow('📱', const Color(0x1F9D4EDD), 'Widgets', 'Manage home screen widgets', () => context.go(RouteNames.widgets)),
                      _SectionLabel('PREFERENCES'),
                      _NavRow('🎨', const Color(0x1AFFD700), 'Themes', 'Midnight Purple (active)', () => context.push(RouteNames.themes)),
                      _NavRow('⚙️', const Color(0x0FFFFFFF), 'Settings', 'Account, privacy, notifications', () => context.push(RouteNames.settings)),
                      if (state is ProfileReady) ...[
                        _SectionLabel('DANGER ZONE'),
                        _NavRow('💔', const Color(0x1FFF5252), 'Disconnect Couple',
                            state.couple.disconnectRequestedBy == null
                                ? 'Both partners must confirm'
                                : state.couple.disconnectRequestedBy == state.user.id
                                    ? 'Waiting for your partner to confirm…'
                                    : 'Your partner asked to disconnect — tap to respond',
                            () => _onDisconnectTap(context, state)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

Future<bool> _askConfirm(BuildContext context, String title, String body, String action) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppColors.bg2,
      title: Text(title, style: const TextStyle(color: Colors.white)),
      content: Text(body, style: AppTextStyles.bodyMuted),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(action, style: const TextStyle(color: AppColors.error)),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Disconnecting needs both partners: one requests, the other confirms.
Future<void> _onDisconnectTap(BuildContext context, ProfileReady state) async {
  final bloc      = context.read<ProfileBloc>();
  final myId      = state.user.id;
  final coupleId  = state.couple.id;
  final requester = state.couple.disconnectRequestedBy;

  if (requester == null) {
    final ok = await _askConfirm(context, 'Request to disconnect?',
        'Your partner will be asked to confirm. You stay connected until they do.', 'Send request');
    if (ok) bloc.add(DisconnectRequested(userId: myId, coupleId: coupleId));
  } else if (requester == myId) {
    final ok = await _askConfirm(context, 'Cancel your request?',
        'You asked to disconnect and are waiting for your partner to confirm.', 'Cancel request');
    if (ok) bloc.add(DisconnectCancelled(coupleId: coupleId));
  } else {
    final ok = await _askConfirm(context, 'Your partner wants to disconnect',
        'Confirming unlinks you both and ends live access to the shared canvas, touch and mood. You can pair again with a new invite code.', 'Confirm');
    if (ok) {
      bloc.add(DisconnectConfirmed(userId: myId, coupleId: coupleId));
    } else if (context.mounted) {
      final decline = await _askConfirm(context, 'Decline the request?',
          'Your partner will stay connected to you.', 'Decline');
      if (decline) bloc.add(DisconnectCancelled(coupleId: coupleId));
    }
  }
}

class _ProfileHero extends StatefulWidget {
  const _ProfileHero({required this.state});
  final ProfileState state;

  @override
  State<_ProfileHero> createState() => _ProfileHeroState();
}

class _ProfileHeroState extends State<_ProfileHero> with SingleTickerProviderStateMixin {
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(vsync: this, duration: const Duration(seconds: 22))..repeat();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isReady = widget.state is ProfileReady;
    final ready   = isReady ? widget.state as ProfileReady : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 16),
      child: Column(
        children: [
          // Avatar
          SizedBox(
            width: 96, height: 96,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedBuilder(
                  animation: _spin,
                  builder: (_, __) => CustomPaint(
                    size: const Size(96, 96),
                    painter: ConicOrbPainter(angle: _spin.value * 2 * pi, colors: const [
                      AppColors.pink, AppColors.purple, AppColors.cyan, AppColors.purple, AppColors.pink,
                    ]),
                  ),
                ),
                Container(
                  width: 76, height: 76,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [AppColors.bg2, AppColors.bg1]),
                  ),
                  child: Center(
                    child: Text(
                      ready?.user.avatarEmoji ?? '🦋',
                      style: const TextStyle(fontSize: 38),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(ready?.user.username ?? '—', style: AppTextStyles.partnerName),
          const SizedBox(height: 4),
          Text(
            ready != null ? _formatSince(ready.couple.pairedAt) : '…',
            style: AppTextStyles.label,
          ),
          const SizedBox(height: 22),
          if (!isReady) const LoadingDots() else
          Row(
            children: [
              _Stat(ready!.couple.streakDays.toString(),    'Day Streak'),
              const SizedBox(width: 12),
              _Stat(ready.couple.totalMoments.toString(),   'Moments'),
              const SizedBox(width: 12),
              _Stat(ready.doodleCount.toString(),            'Doodles'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);
  final String value, label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GlassCard(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        borderRadius: 16,
        child: Column(
          children: [
            GradientText(value, gradient: AppGradients.gradientText2, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(label, style: AppTextStyles.labelCaps.copyWith(fontSize: 10), textAlign: TextAlign.center),
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

class _NavRow extends StatelessWidget {
  const _NavRow(this.icon, this.iconBg, this.title, this.subtitle, this.onTap);
  final String icon, title, subtitle;
  final Color  iconBg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 5),
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
              decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
              child: Center(child: Text(icon, style: const TextStyle(fontSize: 18))),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyles.body.copyWith(fontSize: 15)),
                  Text(subtitle, style: AppTextStyles.labelSmall),
                ],
              ),
            ),
            Text('›', style: TextStyle(color: AppColors.textDim, fontSize: 18)),
          ],
        ),
      ),
    );
  }
}

String _formatSince(DateTime dt) {
  const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  return 'Together since ${months[dt.month - 1]} ${dt.day}, ${dt.year}';
}
