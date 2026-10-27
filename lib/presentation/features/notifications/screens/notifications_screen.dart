import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../domain/entities/notification_item.dart';
import '../../../features/auth/bloc/auth_bloc.dart';
import '../../../shared/widgets/loading_dots.dart';
import '../../../shared/widgets/neon_back_button.dart';
import '../bloc/notification_bloc.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth     = context.read<AuthBloc>().state;
    final coupleId = auth is Authenticated ? (auth.user.coupleId ?? '') : '';
    return BlocProvider(
      create: (_) => GetIt.I<NotificationBloc>()
        ..add(NotificationsLoaded(coupleId)),
      child: const _NotifBody(),
    );
  }
}

class _NotifBody extends StatelessWidget {
  const _NotifBody();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg1,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  const NeonBackButton(),
                  const SizedBox(width: 14),
                  Text('Moments', style: AppTextStyles.h2.copyWith(fontSize: 24)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: BlocBuilder<NotificationBloc, NotifState>(
                builder: (context, state) {
                  if (state is NotifLoading) return const Center(child: LoadingDots());
                  if (state is NotifReady) {
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                      itemCount: state.items.length,
                      itemBuilder: (_, i) => _NotifItem(item: state.items[i]),
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

class _NotifItem extends StatelessWidget {
  const _NotifItem({required this.item});
  final NotificationItem item;

  /// Opens the part of the app a notification is about. Screens above the main
  /// tabs are pushed so back returns here; tabs are switched to.
  void _open(BuildContext context) {
    if (!item.isRead) {
      context.read<NotificationBloc>().add(NotificationRead(id: item.id, coupleId: item.coupleId));
    }
    switch (item.type) {
      case NotifType.touch:
        context.push(RouteNames.touchSync);
      case NotifType.doodle:
        context.go(RouteNames.memories);
      case NotifType.moodChange:
        context.go(RouteNames.home);
      case NotifType.streak:
      case NotifType.milestone:
        context.push(RouteNames.timeline);
      case NotifType.location:
      case NotifType.locate:
        context.push(RouteNames.location);
      case NotifType.question:
        context.push(RouteNames.question);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _open(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: item.isRead ? AppColors.glass : AppColors.pink.withValues(alpha: 0.055),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: item.isRead ? AppColors.glassBorder : AppColors.pink.withValues(alpha: 0.15),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: item.type.iconBackground,
                shape: BoxShape.circle,
              ),
              child: Center(child: Text(item.type.emoji, style: const TextStyle(fontSize: 20))),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.bodyText, style: AppTextStyles.body.copyWith(fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(item.timestamp.timeAgo, style: AppTextStyles.labelSmall),
                ],
              ),
            ),
            if (!item.isRead) ...[
              const SizedBox(width: 8),
              Container(
                width: 8, height: 8,
                margin: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(
                  color: AppColors.pink,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: AppColors.pink.withValues(alpha: 0.7), blurRadius: 7)],
                ),
              ),
            ],
            const Icon(Icons.chevron_right, color: AppColors.textDim, size: 20),
          ],
        ),
      ),
    );
  }
}

extension _DateExt on DateTime {
  String get timeAgo {
    final diff = DateTime.now().difference(this);
    if (diff.inSeconds < 60)  return 'Just now';
    if (diff.inMinutes < 60)  return '${diff.inMinutes} min ago';
    if (diff.inHours < 24)    return '${diff.inHours} hours ago';
    if (diff.inDays == 1)     return 'Yesterday';
    return '${diff.inDays} days ago';
  }
}
