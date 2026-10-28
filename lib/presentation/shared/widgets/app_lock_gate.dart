import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../../core/services/app_lock_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import 'centered_scroll.dart';

/// Covers the app with the lock screen while [AppLockService] says so.
class AppLockGate extends StatelessWidget {
  const AppLockGate({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final lock = GetIt.I<AppLockService>();
    return ListenableBuilder(
      listenable: lock,
      builder: (context, _) => Stack(
        children: [
          child,
          if (lock.obscured) Positioned.fill(child: _LockScreen(lock: lock)),
        ],
      ),
    );
  }
}

class _LockScreen extends StatefulWidget {
  const _LockScreen({required this.lock});
  final AppLockService lock;

  @override
  State<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<_LockScreen> {
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    // Prompt straight away; the button is there for when it is dismissed.
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    final ok = await widget.lock.unlock();
    if (mounted && !ok) setState(() => _failed = true);
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Material(
      color: AppColors.bg1,
      child: CenteredScroll(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84, height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: primary.withValues(alpha: 0.15),
                border: Border.all(color: primary.withValues(alpha: 0.5)),
              ),
              child: Icon(Icons.lock_rounded, size: 38, color: primary),
            ),
            const SizedBox(height: 20),
            Text('Usync is locked', style: AppTextStyles.h3.copyWith(color: Colors.white)),
            const SizedBox(height: 6),
            Text(
              _failed ? 'Could not verify it\'s you' : 'Your moments are private',
              style: AppTextStyles.bodyMuted,
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: widget.lock.locked ? _unlock : null,
              icon: const Icon(Icons.fingerprint),
              label: const Text('Unlock'),
            ),
          ],
        ),
      ),
    );
  }
}
