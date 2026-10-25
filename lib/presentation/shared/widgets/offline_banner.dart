import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../../core/services/outbox_service.dart';
import '../../../core/theme/app_colors.dart';

/// A small pill under the status bar while the app is offline or changes are
/// waiting to be sent. It floats over the screen, so no layout moves.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final outbox = GetIt.I<OutboxService>();
    return ListenableBuilder(
      listenable: outbox,
      builder: (context, _) {
        final waiting = outbox.pending;
        final String? text = switch ((outbox.online, waiting > 0)) {
          (false, false) => 'You are offline',
          (false, true)  => 'Offline · $waiting ${waiting == 1 ? 'change' : 'changes'} waiting to send',
          (true, true)   => outbox.syncing
              ? 'Sending $waiting ${waiting == 1 ? 'change' : 'changes'}…'
              : '$waiting ${waiting == 1 ? 'change' : 'changes'} waiting to send',
          (true, false)  => null,
        };
        if (text == null) return const SizedBox.shrink();

        return Positioned(
          top: MediaQuery.paddingOf(context).top + 6,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.bg2.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.glassBorder),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        outbox.online ? Icons.sync : Icons.cloud_off,
                        size: 14,
                        color: outbox.online ? AppColors.cyan : AppColors.textMuted,
                      ),
                      const SizedBox(width: 6),
                      Text(text, style: const TextStyle(fontSize: 12, color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
