import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/app_constants.dart';
import 'app_snack_bar.dart';

/// Opens the public privacy policy in the browser; a snackbar says so if it cannot be opened.
Future<void> openPrivacyPolicy(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final opened = await launchUrl(Uri.parse(AppConstants.privacyPolicyUrl), mode: LaunchMode.externalApplication)
      .catchError((_) => false);
  if (!opened) {
    messenger.showSnackBar(appSnackBar(content: const Text('Could not open the privacy policy')));
  }
}
