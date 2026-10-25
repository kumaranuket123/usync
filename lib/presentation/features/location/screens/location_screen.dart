import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get_it/get_it.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../domain/entities/shared_location.dart';
import '../../../../domain/repositories/i_auth_repository.dart';
import '../../../../domain/repositories/i_couple_repository.dart';
import '../../../../domain/repositories/i_location_repository.dart';
import '../../../shared/widgets/loading_dots.dart';
import '../../../shared/widgets/neon_back_button.dart';
import '../bloc/location_bloc.dart';

class LocationScreen extends StatelessWidget {
  const LocationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => GetIt.I<LocationBloc>(),
      child: const _LocationBody(),
    );
  }
}

class _LocationBody extends StatefulWidget {
  const _LocationBody();
  @override
  State<_LocationBody> createState() => _LocationBodyState();
}

class _LocationBodyState extends State<_LocationBody> {
  final _map = MapController();
  String _ownEmoji = '🙂', _partnerEmoji = '💜', _partnerName = 'Partner';
  bool _fitted = false;

  @override
  void initState() {
    super.initState();
    _mount();
  }

  Future<void> _mount() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;

    final auth = GetIt.I<IAuthRepository>();
    final user = await auth.getCurrentUser();
    if (user?.coupleId == null) return;

    final couple    = await GetIt.I<ICoupleRepository>().getCouple(user!.coupleId!);
    final partnerId = couple.partnerIdFor(uid);
    final partner   = await auth.getUserById(partnerId);

    if (!mounted) return;
    setState(() {
      _ownEmoji     = user.avatarEmoji;
      _partnerEmoji = partner?.avatarEmoji ?? _partnerEmoji;
      _partnerName  = partner?.username ?? _partnerName;
    });
    context.read<LocationBloc>().add(LocationScreenMounted(
      coupleId:      couple.id,
      userId:        uid,
      partnerUserId: partnerId,
    ));
  }

  /// Frames everyone whose position is known. The bloc listener fires before
  /// the map has been drawn, and the controller can't be used until then, so
  /// wait for the frame that builds it.
  void _frame(SharedLocation? own, SharedLocation? partner) {
    final points = [
      if (own != null) LatLng(own.latitude, own.longitude),
      if (partner != null) LatLng(partner.latitude, partner.longitude),
    ];
    if (points.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (points.length == 1) {
        _map.move(points.single, 16);
      } else {
        _map.fitCamera(CameraFit.coordinates(
          coordinates: points,
          padding: const EdgeInsets.all(80),
          maxZoom: 17,
        ));
      }
    });
  }

  void _fitOnce(SharedLocation own, SharedLocation partner) {
    if (_fitted) return;
    _fitted = true;
    _frame(own, partner);
  }

  /// Hands the partner's position to Google Maps (app if installed, else browser).
  Future<void> _navigate(SharedLocation partner) async {
    final uri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': '${partner.latitude},${partner.longitude}',
      'travelmode': 'driving',
    });
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication)
        .catchError((_) => false);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open Google Maps')),
      );
    }
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg1,
      body: BlocConsumer<LocationBloc, LocationState>(
        listenWhen: (a, b) => b is LocationReady && b.own != null && b.partner != null,
        listener: (_, state) {
          final s = state as LocationReady;
          _fitOnce(s.own!, s.partner!);
        },
        builder: (context, state) {
          if (state is! LocationReady) return const Center(child: LoadingDots());

          final own     = state.own;
          final partner = state.partner;
          final focus   = partner ?? own;

          return Stack(
            children: [
              FlutterMap(
                mapController: _map,
                options: MapOptions(
                  initialCenter: focus == null
                      ? const LatLng(20, 0)
                      : LatLng(focus.latitude, focus.longitude),
                  initialZoom: focus == null ? 2 : 15,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.usync',
                  ),
                  MarkerLayer(markers: [
                    if (partner != null)
                      _marker(partner, _partnerEmoji, AppColors.pink),
                    if (own != null)
                      _marker(own, _ownEmoji, AppColors.cyan),
                  ]),
                  const RichAttributionWidget(attributions: [
                    TextSourceAttribution('© OpenStreetMap contributors'),
                  ]),
                ],
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const NeonBackButton(),
                      const SizedBox(width: 12),
                      Text('Location', style: AppTextStyles.h3.copyWith(color: Colors.white)),
                      const Spacer(),
                      if (own != null || partner != null)
                        _MapButton(
                          icon: Icons.center_focus_strong,
                          tooltip: 'Reset view',
                          onTap: () => _frame(own, partner),
                        ),
                      if (partner != null) ...[
                        const SizedBox(width: 8),
                        _MapButton(
                          icon: Icons.directions,
                          tooltip: 'Navigate in Google Maps',
                          onTap: () => _navigate(partner),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 16, right: 16, bottom: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _Panel(
                      state: state,
                      partnerName: _partnerName,
                      onToggle: () => context.read<LocationBloc>().add(LocationSharingToggled()),
                      onRefresh: () => context.read<LocationBloc>().add(LocationRefreshed()),
                      onLocate: () => context.read<LocationBloc>().add(LocateRequested()),
                      onBackground: () => context.read<LocationBloc>().add(BackgroundToggled()),
                      onSettings: () => context.read<LocationBloc>().add(LocationSettingsRequested()),
                      onShowPartner: partner == null
                          ? null
                          : () => _map.move(LatLng(partner.latitude, partner.longitude), 16),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Marker _marker(SharedLocation l, String emoji, Color color) => Marker(
        point: LatLng(l.latitude, l.longitude),
        width: 48, height: 48,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.bg2,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 3),
          ),
          alignment: Alignment.center,
          child: Text(emoji, style: const TextStyle(fontSize: 22)),
        ),
      );
}

class _MapButton extends StatelessWidget {
  const _MapButton({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: AppColors.bg2.withValues(alpha: 0.9),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.state,
    required this.partnerName,
    required this.onToggle,
    required this.onRefresh,
    required this.onLocate,
    required this.onBackground,
    required this.onSettings,
    required this.onShowPartner,
  });

  final LocationReady state;
  final String partnerName;
  final VoidCallback onToggle, onRefresh, onLocate, onBackground, onSettings;
  final VoidCallback? onShowPartner;

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1)  return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24)   return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }

  String get _partnerLine {
    final p = state.partner;
    if (p == null) return '$partnerName hasn\'t shared a location yet';
    final own = state.own;
    final seen = 'seen ${_ago(p.timestamp)}';
    if (own == null) return '$partnerName · $seen';
    final metres = const Distance().as(
      LengthUnit.Meter,
      LatLng(own.latitude, own.longitude),
      LatLng(p.latitude, p.longitude),
    );
    final away = metres >= 1000 ? '${(metres / 1000).toStringAsFixed(1)} km' : '$metres m';
    return '$partnerName is $away away · $seen';
  }

  String? get _accessMessage => switch (state.access) {
        LocationAccess.granted         => null,
        LocationAccess.denied          => 'Location permission is needed to share.',
        LocationAccess.deniedForever   => 'Location permission is blocked. Enable it in settings.',
        LocationAccess.serviceDisabled => 'Turn on location services to share.',
        LocationAccess.backgroundDenied =>
          'Choose "Allow all the time" so $partnerName can locate you when the app is closed.',
      };

  @override
  Widget build(BuildContext context) {
    final message = _accessMessage;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bg2.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: onShowPartner,
                  child: Text(_partnerLine, style: AppTextStyles.bodyLarge.copyWith(color: Colors.white)),
                ),
              ),
              if (state.isBusy)
                const SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                IconButton(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  tooltip: 'Refresh',
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            state.isSharing
                ? 'Your location is updated each time you open the app. $partnerName can see it.'
                : '$partnerName can\'t see you until you start sharing.',
            style: AppTextStyles.bodyMuted,
          ),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(message, style: AppTextStyles.body.copyWith(color: AppColors.error)),
          ],
          if (state.isSharing) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Let $partnerName locate me when the app is closed',
                    style: AppTextStyles.body.copyWith(color: Colors.white),
                  ),
                ),
                Switch(
                  value: state.own?.allowsBackground ?? false,
                  onChanged: state.isBusy || state.own == null ? null : (_) => onBackground(),
                ),
              ],
            ),
            Text(
              '$partnerName gets a notification every time they do.',
              style: AppTextStyles.bodyMuted,
            ),
          ],
          const SizedBox(height: 12),
          if (state.partner != null) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: state.isLocating || !state.partner!.allowsBackground ? null : onLocate,
                child: Text(state.isLocating ? 'Locating…' : 'Locate $partnerName now'),
              ),
            ),
            if (!state.partner!.allowsBackground)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '$partnerName hasn\'t allowed locating while their app is closed.',
                  style: AppTextStyles.bodyMuted,
                ),
              ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: state.isBusy ? null : onToggle,
                  style: FilledButton.styleFrom(
                    backgroundColor: state.isSharing ? AppColors.glassMid : AppColors.pink,
                  ),
                  child: Text(state.isSharing ? 'Stop sharing' : 'Share my location'),
                ),
              ),
              if (state.access == LocationAccess.deniedForever ||
                  state.access == LocationAccess.serviceDisabled) ...[
                const SizedBox(width: 8),
                OutlinedButton(onPressed: onSettings, child: const Text('Settings')),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
