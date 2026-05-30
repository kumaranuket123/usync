import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../domain/entities/memory.dart';
import '../../../shared/widgets/neon_back_button.dart';

class MemoryDetailScreen extends StatelessWidget {
  const MemoryDetailScreen({super.key, required this.memoryId, this.memory});
  final String  memoryId;
  final Memory? memory;

  @override
  Widget build(BuildContext context) {
    // In real app, look up by memoryId if memory not passed via extra.
    final m = memory;

    return Scaffold(
      backgroundColor: AppColors.bg1,
      body: Stack(
        children: [
          // Blurred background art
          if (m != null)
            Center(
              child: Text(
                m.thumbnailEmoji,
                style: const TextStyle(fontSize: 200),
                textAlign: TextAlign.center,
              ).let((w) => ImageFiltered(
                imageFilter: ColorFilter.mode(Colors.transparent, BlendMode.dst),
                child: Opacity(opacity: 0.12, child: w),
              )),
            ),

          // Content
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Row(
                    children: [
                      NeonBackButton(onTap: () => context.pop()),
                      const Spacer(),
                      GestureDetector(
                        onTap: () {},
                        child: const Text('♡', style: TextStyle(color: Colors.white, fontSize: 22)),
                      ),
                    ],
                  ),
                ),

                // Art
                Expanded(
                  child: Center(
                    child: Text(
                      m?.thumbnailEmoji ?? '🫧',
                      style: const TextStyle(fontSize: 110),
                    ),
                  ),
                ),

                // Footer
                Container(
                  padding: const EdgeInsets.fromLTRB(28, 20, 28, 40),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end:   Alignment.topCenter,
                      colors: [AppColors.bg1, AppColors.bg1.withOpacity(0)],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m?.title ?? 'Memory', style: AppTextStyles.h2.copyWith(fontSize: 26)),
                      const SizedBox(height: 6),
                      Text('${m?.createdAt.formatted ?? ''} · ${m?.type.tagLabel ?? ''}',
                          style: AppTextStyles.label),
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Expanded(child: _ActionBtn('🔗 Share', secondary: false)),
                          const SizedBox(width: 12),
                          Expanded(child: _ActionBtn('⬇️ Save', secondary: false)),
                          const SizedBox(width: 12),
                          Expanded(child: _ActionBtn('💖 Favourite', secondary: true)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn(this.label, {required this.secondary});
  final String label;
  final bool   secondary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 15),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        color: secondary ? AppColors.pink.withOpacity(0.2) : AppColors.glass,
        border: Border.all(
          color: secondary ? AppColors.pink.withOpacity(0.3) : AppColors.glassBorder,
        ),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: secondary ? Colors.white : AppColors.textMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

extension _DateExt on DateTime {
  String get formatted {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[month - 1]} $day, $year';
  }
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
