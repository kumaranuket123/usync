import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../domain/entities/bucket_item.dart';
import '../../../shared/widgets/glass_input.dart';
import '../../../shared/widgets/glow_button.dart';
import '../../../shared/widgets/loading_dots.dart';
import '../../../shared/widgets/neon_back_button.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../bloc/bucket_bloc.dart';
import '../../../../core/utils/app_snack_bar.dart';

class BucketListScreen extends StatelessWidget {
  const BucketListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthBloc>().state;
    final user = auth is Authenticated ? auth.user : null;
    return BlocProvider(
      create: (_) => GetIt.I<BucketBloc>()
        ..add(BucketOpened(coupleId: user?.coupleId ?? '', userId: user?.id ?? '')),
      child: const _BucketBody(),
    );
  }
}

class _BucketBody extends StatelessWidget {
  const _BucketBody();

  Future<void> _openAdd(BuildContext context) async {
    final bloc = context.read<BucketBloc>();
    final added = await showModalBottomSheet<ItemAdded>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bg2,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => const _AddItemSheet(),
    );
    if (added != null) bloc.add(added);
  }

  Future<void> _confirmDelete(BuildContext context, BucketItem item) async {
    final bloc = context.read<BucketBloc>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.bg2,
        title: const Text('Remove this item?', style: TextStyle(color: Colors.white)),
        content: Text('"${item.title}" will be removed for both of you.', style: AppTextStyles.bodyMuted),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok == true) bloc.add(ItemRemoved(item.id));
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<BucketBloc, BucketState>(
      listenWhen: (_, b) => b is BucketReady && b.notice != null,
      listener: (context, state) =>
          ScaffoldMessenger.of(context).showSnackBar(appSnackBar(content: Text((state as BucketReady).notice!))),
      builder: (context, state) {
        final ready = state is BucketReady ? state : null;
        return Scaffold(
          backgroundColor: AppColors.bg1,
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
                  child: Row(
                    children: [
                      const NeonBackButton(),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Bucket list', style: AppTextStyles.h2.copyWith(fontSize: 22)),
                          Text(
                            ready == null || ready.items.isEmpty
                                ? 'Things we want to do together'
                                : '${ready.doneCount} of ${ready.items.length} done',
                            style: AppTextStyles.label,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: switch (state) {
                    BucketLoading() => const Center(child: LoadingDots()),
                    BucketReady(items: final items) when items.isEmpty => const _EmptyState(),
                    BucketReady() => ListView.separated(
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                        itemCount: state.items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final item = state.items[i];
                          return _ItemTile(
                            item: item,
                            pending: state.pendingIds.contains(item.id),
                            onToggle: () => context.read<BucketBloc>().add(ItemToggled(item)),
                            onLongPress: () => _confirmDelete(context, item),
                          );
                        },
                      ),
                  },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                  child: GlowButton(label: 'Add to our list', onTap: () => _openAdd(context)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎯', style: TextStyle(fontSize: 44)),
            const SizedBox(height: 12),
            Text('Nothing here yet', style: AppTextStyles.h3),
            const SizedBox(height: 6),
            Text(
              'Add the things you dream of doing together. You can both tick them off.',
              style: AppTextStyles.bodyMuted,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item, required this.pending, required this.onToggle, required this.onLongPress});
  final BucketItem   item;
  final bool         pending;
  final VoidCallback onToggle, onLongPress;

  @override
  Widget build(BuildContext context) {
    final done = item.isDone;
    return GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.glass,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: pending ? null : onToggle,
              child: Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done ? AppColors.pink : Colors.transparent,
                  border: Border.all(color: done ? AppColors.pink : AppColors.textDim, width: 2),
                ),
                child: done ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
              ),
            ),
            const SizedBox(width: 12),
            Text(item.emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: AppTextStyles.body.copyWith(
                      fontSize: 15,
                      color: done ? AppColors.textMuted : Colors.white,
                      decoration: done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (item.note != null)
                    Text(item.note!, style: AppTextStyles.labelSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (pending) Text('Waiting to send…', style: AppTextStyles.labelSmall.copyWith(color: AppColors.pinkLight)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddItemSheet extends StatefulWidget {
  const _AddItemSheet();
  @override
  State<_AddItemSheet> createState() => _AddItemSheetState();
}

class _AddItemSheetState extends State<_AddItemSheet> {
  static const _emojis = ['✨', '✈️', '🍽️', '🏔️', '🏖️', '🎬', '🎶', '🏡', '💍'];

  final _title = TextEditingController();
  final _note  = TextEditingController();
  String _emoji = _emojis.first;

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    final note = _note.text.trim();
    Navigator.pop(context, ItemAdded(title: title, emoji: _emoji, note: note.isEmpty ? null : note));
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
            Text('Add to our bucket list', style: AppTextStyles.h3.copyWith(color: Colors.white)),
            const SizedBox(height: 16),
            GlassInput(label: 'WHAT DO WE WANT TO DO', hint: 'Watch the sunrise together', controller: _title, maxLength: 80),
            const SizedBox(height: 12),
            GlassInput(label: 'NOTE (OPTIONAL)', hint: 'Where, when, anything to remember', controller: _note, maxLength: 200),
            const SizedBox(height: 12),
            const Text('ICON', style: AppTextStyles.labelCaps),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in _emojis)
                  GestureDetector(
                    onTap: () => setState(() => _emoji = e),
                    child: Container(
                      width: 44, height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: e == _emoji ? AppColors.pink.withValues(alpha: 0.18) : AppColors.glass,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: e == _emoji ? AppColors.pink : AppColors.glassBorder),
                      ),
                      child: Text(e, style: const TextStyle(fontSize: 22)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            GlowButton(label: 'Add', onTap: _save),
          ],
        ),
      ),
    );
  }
}
