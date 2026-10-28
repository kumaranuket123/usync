import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:gal/gal.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../domain/entities/memory.dart';
import '../../../../domain/repositories/i_memory_repository.dart';
import '../../../shared/widgets/memory_art.dart';
import '../../../shared/widgets/neon_back_button.dart';
import 'confirm_delete_memory.dart';
import '../../../../core/utils/app_snack_bar.dart';

class MemoryDetailScreen extends StatelessWidget {
  const MemoryDetailScreen({super.key, required this.memoryId, this.memory});
  final String  memoryId;
  final Memory? memory;

  /// The memory's picture as a local file (from the image cache, else downloaded),
  /// or null when it only has an emoji.
  Future<String?> _imagePath(Memory m) async {
    final url = m.thumbnailUrl;
    if (url != null && url.startsWith('/')) return url; // already a file on this phone
    if (url == null || !url.startsWith('http')) return null;
    // Same key MemoryArt caches under, so an image already on screen isn't fetched again.
    return (await DefaultCacheManager().getSingleFile(url, key: m.id)).path;
  }

  Future<void> _share(BuildContext context, Memory m) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final path = await _imagePath(m);
      if (path == null) {
        messenger.showSnackBar(appSnackBar(content: Text('This memory has no picture to share')));
        return;
      }
      await Share.shareXFiles([XFile(path, mimeType: 'image/png')], text: m.title);
    } catch (_) {
      messenger.showSnackBar(appSnackBar(content: Text('Could not share this memory')));
    }
  }

  Future<void> _save(BuildContext context, Memory m) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final path = await _imagePath(m);
      if (path == null) {
        messenger.showSnackBar(appSnackBar(content: Text('This memory has no picture to save')));
        return;
      }
      await Gal.putImage(path, album: 'Usync');
      messenger.showSnackBar(appSnackBar(content: Text('Saved to your gallery')));
    } on GalException catch (e) {
      messenger.showSnackBar(appSnackBar(
        content: Text(e.type == GalExceptionType.accessDenied
            ? 'Allow photo access to save images'
            : 'Could not save this memory'),
      ));
    } catch (_) {
      messenger.showSnackBar(appSnackBar(content: Text('Could not save this memory')));
    }
  }

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
                      if (m != null) ...[
                        GestureDetector(
                          onTap: () async {
                            final router = GoRouter.of(context);
                            if (!await confirmDeleteMemory(context, m)) return;
                            await getIt<IMemoryRepository>().deleteMemory(m.id, m.coupleId);
                            router.pop();
                          },
                          child: const Icon(Icons.delete_outline, color: Colors.white, size: 24),
                        ),
                      ],
                    ],
                  ),
                ),

                // Art
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Center(
                      child: m == null
                          ? const Text('🫧', style: TextStyle(fontSize: 110))
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: MemoryArt(memory: m, emojiSize: 110),
                            ),
                    ),
                  ),
                ),

                // Footer; scrolls inside half the screen so large text cannot push it off.
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
                  child: SingleChildScrollView(
                    child: Container(
                  padding: const EdgeInsets.fromLTRB(28, 20, 28, 40),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end:   Alignment.topCenter,
                      colors: [AppColors.bg1, AppColors.bg1.withValues(alpha: 0)],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m?.title ?? 'Memory', style: AppTextStyles.h2.copyWith(fontSize: 26)),
                      const SizedBox(height: 6),
                      Text('${m?.createdAt.formatted ?? ''} · ${m?.type.tagLabel ?? ''}',
                          style: AppTextStyles.label),
                      if (m != null && m.imageArchived && !(m.thumbnailUrl ?? '').startsWith('/')) ...[
                        const SizedBox(height: 10),
                        Text(
                          'To save storage, this picture was moved off the server and now lives only on the phones that were using Usync then.',
                          style: AppTextStyles.labelSmall,
                        ),
                      ],
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Expanded(child: _ActionBtn('🔗 Share', onTap: m == null ? null : () => _share(context, m))),
                          const SizedBox(width: 12),
                          Expanded(child: _ActionBtn('⬇️ Save', onTap: m == null ? null : () => _save(context, m))),
                        ],
                      ),
                    ],
                  ),
                    ),
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
  const _ActionBtn(this.label, {required this.onTap});
  final String        label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          color: AppColors.glass,
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: onTap == null ? AppColors.textDim : Colors.white,
              fontWeight: FontWeight.w500,
            ),
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
