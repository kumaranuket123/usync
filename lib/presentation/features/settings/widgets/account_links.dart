import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/route_names.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/privacy_policy.dart';
import 'delete_account_dialog.dart';

/// About, Privacy Policy and Delete account, for people who are signed in but
/// not paired yet and so cannot reach Settings.
class AccountLinks extends StatelessWidget {
  const AccountLinks({super.key});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _link('About Usync', () => context.push(RouteNames.about)),
        _dot(),
        _link('Privacy Policy', () => openPrivacyPolicy(context)),
        _dot(),
        _link('Delete account', () => confirmAndDeleteAccount(context)),
      ],
    );
  }

  static Widget _link(String label, VoidCallback onTap) => TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        child: Text(label, style: AppTextStyles.labelSmall.copyWith(decoration: TextDecoration.underline)),
      );

  static Widget _dot() => Text('·', style: AppTextStyles.labelSmall);
}
