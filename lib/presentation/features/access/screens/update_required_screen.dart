import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/app_snack_bar.dart';
import '../../../../domain/entities/app_config.dart';
import '../../../../domain/repositories/i_access_repository.dart';
import '../../../shared/widgets/centered_scroll.dart';
import '../../../shared/widgets/glow_button.dart';

/// Shown instead of the app when this build is older than the server's
/// minimum. There is no way past it except updating.
class UpdateRequiredScreen extends StatefulWidget {
  const UpdateRequiredScreen({super.key});

  @override
  State<UpdateRequiredScreen> createState() => _UpdateRequiredScreenState();
}

class _UpdateRequiredScreenState extends State<UpdateRequiredScreen> {
  // The answer is already saved on the phone from the splash check, so this is quick.
  late final Future<AppConfig> _config = GetIt.I<IAccessRepository>().getConfig();

  Future<void> _update(Uri uri) async {
    final messenger = ScaffoldMessenger.of(context);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication)
        .catchError((_) => false);
    if (!opened) messenger.showSnackBar(appSnackBar(content: const Text('Could not open the update link')));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.bg1,
        body: SafeArea(
          child: CenteredScroll(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: FutureBuilder<AppConfig>(
                future: _config,
                builder: (context, snapshot) {
                  final url = snapshot.data?.safeUpdateUri;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('⬆️', style: TextStyle(fontSize: 56)),
                      const SizedBox(height: 16),
                      Text('Time to update', style: AppTextStyles.h2, textAlign: TextAlign.center),
                      const SizedBox(height: 10),
                      Text(
                        'This version of Usync is too old to keep working. Please install the latest version to carry on.',
                        style: AppTextStyles.bodyMuted,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 28),
                      if (url != null)
                        GlowButton(label: 'Update now', onTap: () => _update(url))
                      else
                        Text(
                          'Ask whoever shared Usync with you for the newest version.',
                          style: AppTextStyles.labelSmall,
                          textAlign: TextAlign.center,
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
