import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/extensions/datetime_ext.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../domain/entities/memory.dart';
import '../../../shared/widgets/memory_art.dart';
import '../../../shared/animations/breathe_animation.dart';
import '../../../shared/widgets/glow_button.dart';
import '../../../shared/widgets/loading_dots.dart';
import '../../../shared/widgets/memory_tag.dart';
import '../../../shared/widgets/outline_button.dart';
import '../../../../core/di/injection.dart';
import '../../../features/auth/bloc/auth_bloc.dart';
import '../bloc/memory_bloc.dart';
import 'confirm_delete_memory.dart';
import '../../../../core/utils/app_snack_bar.dart';

class MemorySpaceScreen extends StatelessWidget {
  const MemorySpaceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth     = context.read<AuthBloc>().state;
    final coupleId = auth is Authenticated ? (auth.user.coupleId ?? '') : '';
    return BlocProvider(
      create: (_) => getIt<MemoryBloc>()..add(MemoriesLoaded(coupleId)),
      child: const _MemorySpaceBody(),
    );
  }
}

class _MemorySpaceBody extends StatefulWidget {
  const _MemorySpaceBody();
  @override
  State<_MemorySpaceBody> createState() => _MemorySpaceBodyState();
}

class _MemorySpaceBodyState extends State<_MemorySpaceBody> {
  StreamSubscription<int>? _archivedSub;

  @override
  void initState() {
    super.initState();
    _archivedSub = context.read<MemoryBloc>().archived.listen((n) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(appSnackBar(
        duration: const Duration(seconds: 8),
        content: Text(
          '$n older ${n == 1 ? 'picture was' : 'pictures were'} saved on this phone to free up '
          'online storage. They stay here, so keep the app installed or use Save to keep a copy in your gallery.',
        ),
      ));
    });
  }

  @override
  void dispose() {
    _archivedSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg1,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 16, 28, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Memory Space', style: AppTextStyles.h2),
                  Text('Your shared emotional archive', style: AppTextStyles.label),
                  const SizedBox(height: 6),
                  Text(
                    'Your latest 10 pictures stay online. Older ones are kept on both of your phones to save storage.',
                    style: AppTextStyles.labelSmall,
                  ),
                ],
              ),
            ),
            Expanded(
              child: BlocBuilder<MemoryBloc, MemoryState>(
                builder: (context, state) {
                  if (state is MemoryLoading) {
                    return const Center(child: LoadingDots());
                  }
                  if (state is MemoryEmpty) {
                    return const _EmptyState();
                  }
                  if (state is MemoryLoaded) {
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                      itemCount: state.memories.length,
                      itemBuilder: (_, i) => _MemoryCard(memory: state.memories[i]),
                    );
                  }
                  return const SizedBox();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemoryCard extends StatelessWidget {
  const _MemoryCard({required this.memory});
  final Memory memory;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/memories/${memory.id}', extra: memory),
      onLongPress: () async {
        final bloc = context.read<MemoryBloc>();
        if (await confirmDeleteMemory(context, memory)) {
          bloc.add(MemoryDeleted(id: memory.id, coupleId: memory.coupleId));
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: AppColors.glass,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            Container(
              height: 160,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                gradient: switch (memory.type) {
                  MemoryType.canvas    => AppGradients.memoryCanvas,
                  MemoryType.touch     => AppGradients.memoryTouch,
                  MemoryType.mood      => AppGradients.memoryMood,
                  MemoryType.milestone => AppGradients.memoryMilestone,
                },
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                child: MemoryArt(memory: memory, emojiSize: 72, fill: true),
              ),
            ),
            // Footer
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(memory.title, style: AppTextStyles.label.copyWith(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                        const SizedBox(height: 3),
                        Text(memory.createdAt.formattedWithTime, style: AppTextStyles.labelSmall),
                      ],
                    ),
                  ),
                  MemoryTag(type: memory.type),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BreatheAnimation(
              child: Container(
                width: 120, height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [AppColors.purple.withValues(alpha: 0.1), Colors.transparent]),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1), style: BorderStyle.solid),
                ),
                child: const Center(child: Text('🫧', style: TextStyle(fontSize: 50))),
              ),
            ),
            const SizedBox(height: 30),
            Text('No memories yet.', style: AppTextStyles.h2.copyWith(fontSize: 26)),
            const SizedBox(height: 12),
            Text(
              'Every doodle, every touch, every mood you share will be kept here, quietly waiting for you.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMuted,
            ),
            const SizedBox(height: 36),
            GlowButton(label: 'Create your first moment ✦', onTap: () {}),
            const SizedBox(height: 12),
            UsyncOutlineButton(label: 'Maybe later', onTap: () {}),
          ],
        ),
      ),
    );
  }
}
