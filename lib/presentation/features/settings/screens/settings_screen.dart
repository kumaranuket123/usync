import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gal/gal.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../../../../core/constants/route_names.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/services/app_lock_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../domain/repositories/i_memory_repository.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/neon_back_button.dart';
import '../../../shared/widgets/outline_button.dart';
import '../../../shared/widgets/toggle_switch.dart';
import '../bloc/settings_bloc.dart';
import 'alert_sounds_screen.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../profile/bloc/profile_bloc.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    // The alert sound choices live on the server; fetch them now, once.
    context.read<SettingsBloc>().add(const AlertTypesRequested());
  }

  @override
  Widget build(BuildContext context) {
    final auth     = context.read<AuthBloc>().state;
    final uid      = Supabase.instance.client.auth.currentUser?.id ?? '';
    final coupleId = auth is Authenticated ? (auth.user.coupleId ?? '') : '';
    // The couple's disconnect state lives in ProfileBloc; Settings owns the
    // Disconnect row, so it provides its own copy.
    return BlocProvider(
      create: (_) => getIt<ProfileBloc>()..add(ProfileLoaded(userId: uid, coupleId: coupleId)),
      child: BlocListener<ProfileBloc, ProfileState>(
        listener: (context, state) {
          if (state is ProfileDisconnected) {
            // Refresh the app-wide user so coupleId is cleared, then re-pair.
            context.read<AuthBloc>().add(const AuthStateChecked());
            context.go(RouteNames.pairInvite);
          }
        },
        child: _scaffold(context),
      ),
    );
  }

  Future<void> _setGalleryBackup(BuildContext context, bool on) async {
    final bloc      = context.read<SettingsBloc>();
    final messenger = ScaffoldMessenger.of(context);
    if (!on) {
      bloc.add(const ToggleChanged(key: 'gallery_backup', value: false));
      messenger.showSnackBar(const SnackBar(
        content: Text('New older pictures stay in the app only. Copies already in your gallery are kept.'),
      ));
      return;
    }
    // Asked here, so a refusal leaves the switch off instead of silently doing nothing.
    if (!await Gal.requestAccess(toAlbum: true)) {
      messenger.showSnackBar(const SnackBar(content: Text('Allow photo access to save pictures to your gallery')));
      return;
    }
    bloc.add(const ToggleChanged(key: 'gallery_backup', value: true));
    try {
      final n = await GetIt.I<IMemoryRepository>().backupArchivedToGallery();
      messenger.showSnackBar(SnackBar(
        content: Text(n == 0
            ? 'Older pictures will be saved to your "Usync" gallery album as they are moved off the server.'
            : 'Saved $n ${n == 1 ? 'picture' : 'pictures'} to your "Usync" gallery album. Newer ones will follow automatically.'),
      ));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Could not save to your gallery just now. It will be tried again.')));
    }
  }

  Widget _scaffold(BuildContext context) {
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
                      _SectionLabel('NOTIFICATIONS'),
                      _ToggleRow('🔔', const Color(0x1F00D4FF), 'Push notifications', 'Gentle emotional alerts',
                          value: settings.notificationsEnabled,
                          onChanged: (v) => context.read<SettingsBloc>().add(ToggleChanged(key: 'notifications', value: v))),
                      _Row('🔊', const Color(0x1F00E676), 'Alert sounds',
                          '${settings.silentTypes.length} of ${AlertSoundsScreen.groups.length} alerts silent',
                          onTap: () => context.push(RouteNames.alertSounds)),

                      _SectionLabel('PRIVACY & SECURITY'),
                      _Row('📍', const Color(0x1F00E676), 'Location sharing', 'Who sees where you are, and when',
                          onTap: () => context.push(RouteNames.location)),
                      ListenableBuilder(
                        listenable: GetIt.I<AppLockService>(),
                        builder: (context, _) => _ToggleRow('🔐', const Color(0x1F9D4EDD), 'Biometric lock',
                            'Fingerprint, face or device PIN to open Usync',
                            value: GetIt.I<AppLockService>().enabled,
                            onChanged: (v) async {
                              final changed = await GetIt.I<AppLockService>().setEnabled(v);
                              if (!changed && v && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                  content: Text('Set up a fingerprint, face or screen lock on this device first'),
                                ));
                              }
                            }),
                      ),

                      _SectionLabel('APPEARANCE & FEEL'),
                      _Row('🎨', const Color(0x1AFFD700), 'Themes', 'Choose your colours', onTap: () => context.push(RouteNames.themes)),
                      _ToggleRow('✨', const Color(0x1F9D4EDD), 'Animations', 'Rich particle effects',
                          value: settings.animationsEnabled,
                          onChanged: (v) => context.read<SettingsBloc>().add(ToggleChanged(key: 'animations', value: v))),
                      _ToggleRow('📳', const Color(0x1FFF2D78), 'Haptic feedback', 'Vibrate on partner touch',
                          value: settings.hapticEnabled,
                          onChanged: (v) => context.read<SettingsBloc>().add(ToggleChanged(key: 'haptic', value: v))),

                      _SectionLabel('STORAGE'),
                      _ToggleRow('🖼️', const Color(0x1FFF6EC7), 'Save older memories to gallery',
                          'Copy pictures moved off the server into your "Usync" album',
                          value: settings.galleryBackupEnabled,
                          onChanged: (v) => _setGalleryBackup(context, v)),

                      _SectionLabel('ABOUT'),
                      _Row('ℹ️', const Color(0x0FFFFFFF), 'About Usync', 'Version 1.0.0', onTap: () {}),

                      _SectionLabel('DANGER ZONE'),
                      BlocBuilder<ProfileBloc, ProfileState>(
                        builder: (context, profile) {
                          if (profile is! ProfileReady) return const SizedBox.shrink();
                          return _Row('💔', const Color(0x1FFF5252), 'Disconnect Couple',
                              'Unlink and delete all shared data',
                              onTap: () => _onDisconnectTap(context, profile));
                        },
                      ),
                      _Row('🗑️', const Color(0x1FFF5252), 'Delete Account',
                          'Permanently delete your account and all your data',
                          onTap: () => _onDeleteAccountTap(context)),

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

/// Either partner can disconnect on their own; this only asks "are you sure".
Future<void> _onDisconnectTap(BuildContext context, ProfileReady state) async {
  final bloc = context.read<ProfileBloc>();
  final ok = await _askConfirm(context, 'Disconnect from your partner?',
      'This unlinks you both right away and permanently deletes everything you shared: moods, memories, timeline and canvas. This cannot be undone. You can pair again with a new invite code.', 'Disconnect');
  if (ok) bloc.add(DisconnectCouple(userId: state.user.id, coupleId: state.couple.id));
}

/// Deleting the account cannot be undone, so the person has to type DELETE.
Future<void> _onDeleteAccountTap(BuildContext context) async {
  final auth = context.read<AuthBloc>();
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => const _DeleteAccountDialog(),
  );
  if (ok == true) auth.add(const DeleteAccountRequested());
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();
  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final confirmed = _ctrl.text.trim().toUpperCase() == 'DELETE';
    return AlertDialog(
      backgroundColor: AppColors.bg2,
      title: const Text('Delete your account?', style: TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This permanently deletes your account and everything you shared with your partner: moods, memories, timeline and canvas. Your partner is disconnected. This cannot be undone.',
            style: AppTextStyles.bodyMuted,
          ),
          const SizedBox(height: 16),
          Text('Type DELETE to confirm', style: AppTextStyles.labelSmall),
          const SizedBox(height: 6),
          TextField(
            controller: _ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(color: Colors.white),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
        ),
        TextButton(
          onPressed: confirmed ? () => Navigator.pop(context, true) : null,
          child: Text('Delete', style: TextStyle(color: confirmed ? const Color(0xFFFF5050) : AppColors.textDim)),
        ),
      ],
    );
  }
}
