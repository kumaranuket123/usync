import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../domain/entities/milestone.dart';
import '../../../features/auth/bloc/auth_bloc.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/glass_input.dart';
import '../../../shared/widgets/glow_button.dart';
import '../../../shared/widgets/toggle_switch.dart';
import '../../../shared/widgets/loading_dots.dart';
import '../../../shared/widgets/neon_back_button.dart';
import '../bloc/timeline_bloc.dart';

class TimelineScreen extends StatelessWidget {
  const TimelineScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth     = context.read<AuthBloc>().state;
    final coupleId = auth is Authenticated ? (auth.user.coupleId ?? '') : '';
    return BlocProvider(
      create: (_) => GetIt.I<TimelineBloc>()..add(TimelineLoaded(coupleId)),
      child: const _TimelineBody(),
    );
  }
}

class _TimelineBody extends StatelessWidget {
  const _TimelineBody();

  Future<void> _openAdd(BuildContext context) async {
    final bloc = context.read<TimelineBloc>();
    final result = await showModalBottomSheet<DateAdded>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bg2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _AddDateSheet(),
    );
    if (result != null) bloc.add(result);
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<TimelineBloc, TimelineState>(
      listenWhen: (_, b) => b is TimelineReady && b.notice != null,
      listener: (context, state) => ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text((state as TimelineReady).notice!))),
      child: _scaffold(context),
    );
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Our Journey', style: AppTextStyles.h2.copyWith(fontSize: 24)),
                      BlocBuilder<TimelineBloc, TimelineState>(
                        builder: (context, state) => Text(
                          state is TimelineReady
                              ? '${state.daysTogether} days together'
                              : '…',
                          style: AppTextStyles.label,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  BlocBuilder<TimelineBloc, TimelineState>(
                    builder: (context, state) => state is TimelineReady
                        ? GestureDetector(
                            onTap: () => _openAdd(context),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: AppColors.pink.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(color: AppColors.pink.withValues(alpha: 0.4)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.add, size: 18, color: Colors.white),
                                  const SizedBox(width: 4),
                                  Text('Add date', style: AppTextStyles.label.copyWith(color: Colors.white, fontSize: 13)),
                                ],
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: BlocBuilder<TimelineBloc, TimelineState>(
                builder: (context, state) {
                  if (state is TimelineLoading) return const Center(child: LoadingDots());
                  if (state is TimelineReady) {
                    return _TimelineList(
                      milestones: state.milestones,
                      onAdd: () => _openAdd(context),
                    );
                  }
                  if (state is TimelineEmpty) {
                    return Center(
                      child: Text('Pair with your partner to start your timeline', style: AppTextStyles.bodyMuted),
                    );
                  }
                  if (state is TimelineError) {
                    return Center(child: Text('Could not load your timeline', style: AppTextStyles.bodyMuted));
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

class _TimelineList extends StatelessWidget {
  const _TimelineList({required this.milestones, required this.onAdd});
  final List<Milestone> milestones;
  final VoidCallback    onAdd;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Gradient line
        Positioned(
          left: 43, top: 16, bottom: 40,
          child: Container(
            width: 1,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end:   Alignment.bottomCenter,
                colors: [AppColors.pink, AppColors.purple, AppColors.cyan],
              ),
            ),
          ),
        ),
        ListView.builder(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 100),
          // The extra row is the prompt to add the first date.
          itemCount: milestones.length + (milestones.length == 1 ? 1 : 0),
          itemBuilder: (_, i) => i < milestones.length
              ? _TimelineItem(milestone: milestones[i], index: i)
              : _AddPrompt(onTap: onAdd),
        ),
      ],
    );
  }
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({required this.milestone, required this.index});
  final Milestone milestone;
  final int       index;

  /// How far away a date you added is: the next anniversary for repeating
  /// dates, the date itself for one-offs that are still ahead.
  String? get _countdown {
    if (!milestone.isCustom) return null;
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d     = milestone.occurredAt.toLocal();
    var next    = DateTime(d.year, d.month, d.day);
    if (milestone.repeatsYearly) {
      next = DateTime(today.year, d.month, d.day);
      if (next.isBefore(today)) next = DateTime(today.year + 1, d.month, d.day);
    } else if (next.isBefore(today)) {
      return null;
    }
    final days = next.difference(today).inDays;
    if (days == 0) return 'Today 🎉';
    return milestone.repeatsYearly
        ? 'Next in $days ${days == 1 ? 'day' : 'days'}'
        : 'In $days ${days == 1 ? 'day' : 'days'}';
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final bloc = context.read<TimelineBloc>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.bg2,
        title: const Text('Delete this date?', style: TextStyle(color: Colors.white)),
        content: Text('"${milestone.title}" will be removed for both of you.', style: AppTextStyles.bodyMuted),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok == true) bloc.add(DateDeleted(milestone.id));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Dot
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.bg1,
              border: Border.all(color: AppColors.pink.withValues(alpha: 0.4), width: 1.5),
              boxShadow: [BoxShadow(color: AppColors.pink.withValues(alpha: 0.3), blurRadius: 14)],
            ),
            child: Center(child: Text(milestone.displayEmoji, style: const TextStyle(fontSize: 17))),
          ),
          const SizedBox(width: 14),
          // Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: GlassCard(
                borderRadius: 16,
                padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(milestone.title, style: AppTextStyles.label.copyWith(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                        ),
                        if (milestone.isCustom)
                          GestureDetector(
                            onTap: () => _confirmDelete(context),
                            behavior: HitTestBehavior.opaque,
                            child: const Padding(
                              padding: EdgeInsets.only(left: 8),
                              child: Icon(Icons.delete_outline, size: 18, color: AppColors.textDim),
                            ),
                          ),
                      ],
                    ),
                    if (milestone.note != null && milestone.note!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(milestone.note!, style: AppTextStyles.labelSmall.copyWith(height: 1.5)),
                    ],
                    const SizedBox(height: 5),
                    Text(
                      milestone.repeatsYearly
                          ? '${milestone.occurredAt.formatted} · every year'
                          : milestone.occurredAt.formatted,
                      style: AppTextStyles.labelSmall.copyWith(color: AppColors.textDim),
                    ),
                    if (_countdown != null) ...[
                      const SizedBox(height: 3),
                      Text(_countdown!, style: AppTextStyles.labelSmall.copyWith(color: AppColors.pinkLight, fontWeight: FontWeight.w600)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
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

class _AddPrompt extends StatelessWidget {
  const _AddPrompt({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 52, top: 4),
      child: GestureDetector(
        onTap: onTap,
        child: GlassCard(
          borderRadius: 16,
          padding: const EdgeInsets.all(16),
          child: Text(
            'Add the days that matter: when you first met, your first date, an engagement. You both get a notification on the day.',
            style: AppTextStyles.labelSmall.copyWith(height: 1.5),
          ),
        ),
      ),
    );
  }
}

class _AddDateSheet extends StatefulWidget {
  const _AddDateSheet();
  @override
  State<_AddDateSheet> createState() => _AddDateSheetState();
}

class _AddDateSheetState extends State<_AddDateSheet> {
  static const _emojis = ['💞', '🥂', '💍', '🎉', '✈️', '🌹', '🎂', '🏡', '✨'];

  final _title = TextEditingController();
  final _note  = TextEditingController();
  DateTime _date  = DateTime.now();
  String   _emoji = _emojis.first;
  bool     _repeat = true;

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now    = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1990),
      lastDate: DateTime(now.year + 30),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    final note = _note.text.trim();
    Navigator.pop(
      context,
      DateAdded(
        title: title,
        date: _date,
        note: note.isEmpty ? null : note,
        emoji: _emoji,
        repeatsYearly: _repeat,
      ),
    );
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
            Text('Add a special date', style: AppTextStyles.h3.copyWith(color: Colors.white)),
            const SizedBox(height: 16),
            GlassInput(label: 'WHAT HAPPENED', hint: 'Our first date', controller: _title, maxLength: 60),
            const SizedBox(height: 12),
            const Text('DATE', style: AppTextStyles.labelCaps),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: _pickDate,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.glass,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.event, size: 18, color: AppColors.textMuted),
                    const SizedBox(width: 10),
                    Text(_date.formatted, style: AppTextStyles.body.copyWith(color: Colors.white)),
                  ],
                ),
              ),
            ),
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
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: e == _emoji ? AppColors.pink.withValues(alpha: 0.2) : AppColors.glass,
                        border: Border.all(color: e == _emoji ? AppColors.pink : AppColors.glassBorder),
                      ),
                      child: Center(child: Text(e, style: const TextStyle(fontSize: 20))),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            GlassInput(label: 'NOTE (OPTIONAL)', hint: 'A few words to remember it by', controller: _note, maxLength: 140),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Celebrate every year', style: AppTextStyles.body.copyWith(color: Colors.white)),
                      Text('Notify you both on this day each year', style: AppTextStyles.labelSmall),
                    ],
                  ),
                ),
                ToggleSwitch(value: _repeat, onChanged: (v) => setState(() => _repeat = v)),
              ],
            ),
            const SizedBox(height: 18),
            GlowButton(label: 'Save date', onTap: _save),
          ],
        ),
      ),
    );
  }
}
