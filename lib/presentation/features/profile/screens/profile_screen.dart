import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/route_names.dart';
import '../../../../core/extensions/datetime_ext.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../shared/painters/conic_orb_painter.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/glass_input.dart';
import '../../../shared/widgets/glow_button.dart';
import '../../../shared/widgets/gradient_text.dart';
import '../../../shared/widgets/loading_dots.dart';
import '../../../../core/di/injection.dart';
import '../../../../domain/entities/access.dart';
import '../../../../domain/entities/couple.dart';
import '../../../../domain/entities/encryption_state.dart';
import '../../../../domain/repositories/i_encryption_repository.dart';
import '../../../../domain/repositories/i_access_repository.dart';
import '../../access/screens/paywall_screen.dart';
import '../../../../domain/repositories/i_auth_repository.dart';
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
            // The whole page scrolls (header and rows together). With the header fixed, the rows had only
            // a small window below it and the ones scrolled out of view were hidden behind it.
            child: ListView(
              padding: const EdgeInsets.only(bottom: 100),
              children: [
                _ProfileHero(state: state),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (state is ProfileReady) ...[
                        _SectionLabel('ACCOUNT'),
                        _NavRow('✏️', const Color(0x1F00D4FF), 'Edit profile', 'Change your name and avatar',
                            () => _editName(context, state)),
                      ],
                      _SectionLabel('YOUR CONNECTION'),
                      if (state is ProfileReady)
                        _NavRow(state.couple.relationshipMode.emoji, const Color(0x1F9D4EDD), 'Relationship type',
                            state.couple.relationshipMode.label, () => _pickMode(context, state)),
                      if (state is ProfileReady) _SubscriptionRow(coupleId: state.couple.id),
                      _NavRow('🎯', const Color(0x1F00D4FF), 'Bucket list', 'Things we want to do together', () => context.push(RouteNames.bucketList)),
                      const _SecurityRow(),
                      _NavRow('💞', const Color(0x1F9D4EDD), 'Mood insights', 'How in sync you\'ve been this week', () => context.push(RouteNames.moodInsights)),
                      _NavRow('🕰️', const Color(0x1FFF2D78), 'Relationship Timeline', 'View your shared journey', () => context.push(RouteNames.timeline)),
                      _SectionLabel('PREFERENCES'),
                      _NavRow('⚙️', const Color(0x0FFFFFFF), 'Settings', 'Themes, notifications, security, disconnect', () => context.push(RouteNames.settings)),
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

/// Encryption status at a glance; opens the Security page. The subtitle nudges when something needs doing.
class _SecurityRow extends StatefulWidget {
  const _SecurityRow();

  @override
  State<_SecurityRow> createState() => _SecurityRowState();
}

class _SecurityRowState extends State<_SecurityRow> {
  late EncryptionState _state = getIt<IEncryptionRepository>().current;

  @override
  void initState() {
    super.initState();
    getIt<IEncryptionRepository>().sync().then((s) {
      if (mounted) setState(() => _state = s);
    });
  }

  String get _subtitle => switch (_state.phase) {
        EncryptionPhase.needsRestore                                             => 'Restore your keys',
        EncryptionPhase.needsVerification                                        => 'Compare your security code',
        EncryptionPhase.partnerKeyChanged                                        => 'Your partner\'s code changed: compare it',
        EncryptionPhase.needsApproval || EncryptionPhase.waitingForKey || EncryptionPhase.waitingForPartner => 'Waiting for your partner',
        EncryptionPhase.unknown                                                  => 'Encryption keys and security code',
        _ when !_state.recoverySetUp                                             => 'Set up your recovery phrase',
        _                                                                        => 'Keys ready',
      };

  @override
  Widget build(BuildContext context) =>
      _NavRow('🔐', const Color(0x1F00E676), 'Security', _subtitle, () => context.push(RouteNames.security));
}

/// Where the couple stands with the subscription. Takes no space until the paywall
/// is switched on on the server, so today nothing shows.
class _SubscriptionRow extends StatefulWidget {
  const _SubscriptionRow({required this.coupleId});
  final String coupleId;

  @override
  State<_SubscriptionRow> createState() => _SubscriptionRowState();
}

class _SubscriptionRowState extends State<_SubscriptionRow> {
  late final Future<Access> _access = getIt<IAccessRepository>().getAccess(widget.coupleId);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Access>(
      future: _access,
      builder: (context, snapshot) {
        final access = snapshot.data;
        if (access == null || !access.paywallEnabled) return const SizedBox.shrink();
        return _NavRow(accessEmoji(access.status), const Color(0x1FFFD700), 'Subscription',
            accessTitle(access, DateTime.now()), () => context.push(RouteNames.paywall));
      },
    );
  }
}

/// Lets either partner switch between together and long-distance; the choice is shared.
Future<void> _pickMode(BuildContext context, ProfileReady state) async {
  final bloc = context.read<ProfileBloc>();
  final picked = await showModalBottomSheet<RelationshipMode>(
    context: context,
    backgroundColor: AppColors.bg2,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _ModeSheet(current: state.couple.relationshipMode),
  );
  if (picked != null) bloc.add(RelationshipModeChanged(coupleId: state.couple.id, mode: picked));
}

class _ModeSheet extends StatelessWidget {
  const _ModeSheet({required this.current});
  final RelationshipMode current;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Relationship type', style: AppTextStyles.h3),
            const SizedBox(height: 4),
            Text('Shared with your partner. It tailors the daily questions to you both.', style: AppTextStyles.labelSmall),
            const SizedBox(height: 14),
            for (final mode in RelationshipMode.values)
              _NavRow(mode.emoji, const Color(0x1F9D4EDD),
                  mode == current ? '${mode.label}  ✓' : mode.label, mode.description,
                  () => Navigator.pop(context, mode)),
          ],
        ),
      ),
    );
  }
}

/// Opens the profile editor (name and avatar); after a save the screen and the app-wide user update.
Future<void> _editName(BuildContext context, ProfileReady state) async {
  final profile = context.read<ProfileBloc>();
  final auth    = context.read<AuthBloc>();
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.bg2,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _EditProfileSheet(
      userId:        state.user.id,
      currentName:   state.user.username,
      currentAvatar: state.user.avatarEmoji,
    ),
  );
  if (saved != true) return;
  final user = await getIt<IAuthRepository>().getCurrentUser();
  if (user != null) profile.add(UserUpdated(user));
  auth.add(const AuthStateChecked()); // Home, Settings and the rest show the new name
}

class _EditProfileSheet extends StatefulWidget {
  const _EditProfileSheet({required this.userId, required this.currentName, required this.currentAvatar});
  final String userId, currentName, currentAvatar;

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  static const _minLength = 2;
  static const _maxLength = 24;

  late final _name   = TextEditingController(text: widget.currentName);
  late String _avatar = widget.currentAvatar;
  bool    _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() => _error = null));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String get _trimmed => _name.text.trim();
  bool get _nameChanged   => _trimmed != widget.currentName;
  bool get _avatarChanged => _avatar != widget.currentAvatar;
  bool get _valid => _trimmed.length >= _minLength && (_nameChanged || _avatarChanged);

  /// The standard choices, plus the current avatar if it is not one of them.
  List<String> get _avatars => [
        if (!AppConstants.avatarEmojis.contains(widget.currentAvatar)) widget.currentAvatar,
        ...AppConstants.avatarEmojis,
      ];

  Future<void> _save() async {
    if (!_valid || _saving) return;
    setState(() { _saving = true; _error = null; });
    try {
      await getIt<IAuthRepository>().updateProfile(
        widget.userId,
        username:    _nameChanged ? _trimmed : null,
        avatarEmoji: _avatarChanged ? _avatar : null,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) setState(() { _saving = false; _error = 'Could not save. Check your connection and try again.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
       child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Edit profile', style: AppTextStyles.h3.copyWith(color: Colors.white)),
          const SizedBox(height: 16),
          const Text('AVATAR', style: AppTextStyles.labelCaps),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final a in _avatars)
                GestureDetector(
                  onTap: () => setState(() { _avatar = a; _error = null; }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.glass,
                      border: Border.all(
                        color: a == _avatar ? AppColors.pink : AppColors.glassBorder,
                        width: 2,
                      ),
                      boxShadow: a == _avatar
                          ? [BoxShadow(color: AppColors.pink.withValues(alpha: 0.5), blurRadius: 14)]
                          : null,
                    ),
                    child: Center(child: Text(a, style: const TextStyle(fontSize: 24))),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          GlassInput(label: 'NAME', hint: 'your name', prefixIcon: '👤', controller: _name, maxLength: _maxLength),
          Text(
            'Your partner sees your name and avatar. Name: at least $_minLength characters.',
            style: AppTextStyles.labelSmall,
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: AppTextStyles.body.copyWith(color: AppColors.error)),
          ],
          const SizedBox(height: 18),
          GlowButton(label: 'Save', isLoading: _saving, onTap: _valid ? _save : null),
        ],
       ),
      ),
    );
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
              _Stat(ready.couple.daysTogether.toString(),    'Days Together'),
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
  return dt.togetheSince;
}
