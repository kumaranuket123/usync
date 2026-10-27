import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../domain/entities/access.dart';
import '../../../../domain/repositories/i_access_repository.dart';
import '../../../shared/widgets/glow_button.dart';
import '../../../shared/widgets/loading_dots.dart';
import '../../../shared/widgets/neon_back_button.dart';
import '../../auth/bloc/auth_bloc.dart';

/// Where the subscription will live. For now it only says where the couple stands;
/// buying comes in a later step, so the button is switched off.
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  Future<Access>? _access;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthBloc>().state;
    final coupleId = auth is Authenticated ? auth.user.coupleId : null;
    _access = coupleId == null ? Future.value(const Access.open()) : GetIt.I<IAccessRepository>().getAccess(coupleId);
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
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
              child: Row(
                children: [
                  const NeonBackButton(),
                  const SizedBox(width: 14),
                  Expanded(child: Text('Subscription', style: AppTextStyles.h2.copyWith(fontSize: 24), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<Access>(
                future: _access,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: LoadingDots());
                  final access = snapshot.data!;
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                    child: Column(
                      children: [
                        Text(accessEmoji(access.status), style: const TextStyle(fontSize: 52)),
                        const SizedBox(height: 12),
                        Text(accessTitle(access, DateTime.now()), style: AppTextStyles.h2, textAlign: TextAlign.center),
                        const SizedBox(height: 8),
                        Text(accessText(access), style: AppTextStyles.bodyMuted, textAlign: TextAlign.center),
                        if (access.status == AccessStatus.trial || access.status == AccessStatus.expired) ...[
                          const SizedBox(height: 28),
                          const GlowButton(label: 'Subscribe (coming soon)', onTap: null),
                        ],
                      ],
                    ),
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

/// Wording for each state, shared with the Profile row.
String accessEmoji(AccessStatus s) => switch (s) {
    AccessStatus.grandfathered => '🎁',
    AccessStatus.premium       => '💎',
    AccessStatus.trial         => '⏳',
    AccessStatus.expired       => '🔒',
    AccessStatus.free          => '💞',
  };

String accessTitle(Access a, DateTime now) => switch (a.status) {
    AccessStatus.grandfathered => 'Early member',
    AccessStatus.premium       => a.until == null ? 'Premium' : 'Premium until ${DateFormat.yMMMd().format(a.until!)}',
    AccessStatus.trial         => 'Free trial: ${a.daysLeft(now)} ${a.daysLeft(now) == 1 ? 'day' : 'days'} left',
    AccessStatus.expired       => 'Your free trial has ended',
    AccessStatus.free          => 'Everything is free',
  };

String accessText(Access a) => switch (a.status) {
    AccessStatus.grandfathered => 'You were here from the start, so Usync is free for you, for good. Thank you.',
    AccessStatus.premium       => 'Thank you for supporting Usync.',
    AccessStatus.trial         => 'Enjoy everything in Usync while your trial lasts.',
    AccessStatus.expired       => 'Subscriptions are coming soon. Your memories are safe.',
    AccessStatus.free          => 'You have full access to Usync.',
  };
