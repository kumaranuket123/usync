import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/app_snack_bar.dart';
import '../../../../domain/repositories/i_auth_repository.dart';
import '../../../../domain/repositories/i_couple_repository.dart';
import '../../../shared/widgets/loading_dots.dart';
import '../../../shared/widgets/neon_back_button.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../bloc/security_bloc.dart';
import '../widgets/recovery_phrase_sheet.dart';
import '../widgets/security_view.dart';

class SecurityScreen extends StatelessWidget {
  const SecurityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => GetIt.I<SecurityBloc>()..add(const SecurityOpened()),
      child: const _SecurityBody(),
    );
  }
}

class _SecurityBody extends StatefulWidget {
  const _SecurityBody();
  @override
  State<_SecurityBody> createState() => _SecurityBodyState();
}

class _SecurityBodyState extends State<_SecurityBody> {
  Timer? _poll;
  late final Future<String> _partnerName = _loadPartnerName();

  @override
  void initState() {
    super.initState();
    // While waiting for the partner's phone, look again every so often.
    _poll = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) context.read<SecurityBloc>().add(const SecurityRefreshed());
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<String> _loadPartnerName() async {
    try {
      final auth = context.read<AuthBloc>().state;
      final user = auth is Authenticated ? auth.user : null;
      final coupleId = user?.coupleId;
      if (user == null || coupleId == null) return 'your partner';
      final couple = await GetIt.I<ICoupleRepository>().getCouple(coupleId);
      final partner = await GetIt.I<IAuthRepository>().getUserById(couple.partnerIdFor(user.id));
      final name = partner?.username.trim() ?? '';
      return name.isEmpty ? 'your partner' : name;
    } catch (_) {
      return 'your partner';
    }
  }

  Future<void> _showPhrase(BuildContext context, String phrase) async {
    final bloc = context.read<SecurityBloc>();
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      backgroundColor: AppColors.bg2,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => RecoveryPhraseSheet(phrase: phrase),
    );
    bloc.add(confirmed == true ? RecoveryPhraseConfirmed(phrase) : const RecoveryPhraseDismissed());
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<SecurityBloc, SecurityState>(
          listenWhen: (a, b) => b is SecurityReady && b.notice != null && (a is! SecurityReady || a.notice != b.notice),
          listener: (context, state) =>
              ScaffoldMessenger.of(context).showSnackBar(appSnackBar(content: Text((state as SecurityReady).notice!))),
        ),
        BlocListener<SecurityBloc, SecurityState>(
          // Only when a NEW phrase appears, never again for one that is already on screen.
          listenWhen: (a, b) => b is SecurityReady && b.phraseToShow != null && (a is! SecurityReady || a.phraseToShow == null),
          listener: (context, state) => _showPhrase(context, (state as SecurityReady).phraseToShow!),
        ),
      ],
      child: Scaffold(
        backgroundColor: AppColors.bg1,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 16, 28, 12),
                child: Row(
                  children: [
                    const NeonBackButton(),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Security', style: AppTextStyles.h2.copyWith(fontSize: 22), maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text('Your encryption keys', style: AppTextStyles.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: BlocBuilder<SecurityBloc, SecurityState>(
                  builder: (context, state) => switch (state) {
                    SecurityLoading() => const Center(child: LoadingDots()),
                    SecurityReady() => FutureBuilder<String>(
                        future: _partnerName,
                        initialData: 'your partner',
                        builder: (context, name) {
                          final bloc = context.read<SecurityBloc>();
                          return SecurityView(
                            encryption: state.encryption,
                            partnerName: name.data ?? 'your partner',
                            busy: state.busy,
                            // The code on screen is what gets confirmed, never whatever the server serves later.
                            onVerify: () => bloc.add(PartnerVerifiedMarked(state.encryption.securityCode!)),
                            onApprove: () => bloc.add(PartnerKeyApproved(state.encryption.securityCode!)),
                            onSetUpRecovery: () => bloc.add(const RecoveryPhraseRequested()),
                            onRestore: (phrase) => bloc.add(RestoreSubmitted(phrase)),
                            onReset: () => bloc.add(const KeysResetRequested()),
                            onStartFresh: () => bloc.add(const StartFreshRequested()),
                          );
                        },
                      ),
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
