import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:get_it/get_it.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../domain/entities/milestone.dart';
import '../../domain/repositories/i_auth_repository.dart';
import '../../domain/repositories/i_milestone_repository.dart';

/// One notification to show on this phone at [when] (local wall-clock time).
class Reminder extends Equatable {
  const Reminder({required this.id, required this.title, required this.body, required this.when});
  final int      id;
  final String   title;
  final String   body;
  final DateTime when;

  @override
  List<Object?> get props => [id, title, body, when];
}

/// Shows reminders on this phone. Behind an interface so the planning can be tested without the plugin.
abstract interface class ReminderScheduler {
  Future<void> cancelAll();
  Future<void> schedule(Reminder reminder);
}

/// Date reminders are local notifications scheduled by each phone, not pushes from the server: the server
/// cannot read the dates any more (they are end-to-end encrypted), and the text never leaves the phone.
class ReminderService {
  ReminderService({required this.scheduler, DateTime Function()? now}) : _now = now ?? DateTime.now;

  final ReminderScheduler scheduler;
  final DateTime Function() _now;

  /// Reminders go off at this hour, local time.
  static const hour = 9;
  /// Upcoming yearly occurrences scheduled at once (each with its own anniversary count); opening the app
  /// tops them up.
  static const _yearsAhead = 3;
  /// iOS keeps at most 64 pending notifications.
  static const _maxPending = 60;

  /// What to schedule for [milestones] at [now]: custom dates only (the server's own milestones are not
  /// reminders), skipping ones this phone could not read. A one-off date reminds on its day; a yearly one on
  /// each of its next [_yearsAhead] anniversaries.
  static List<Reminder> plan(List<Milestone> milestones, DateTime now) {
    final due = <({DateTime when, String title, String body})>[];
    for (final m in milestones) {
      if (!m.isCustom || m.occurredAt.year <= 1970) continue; // not a readable custom date
      final day   = m.occurredAt.toUtc(); // stored as noon UTC of the calendar day
      final title = '${m.displayEmoji} ${m.title}';

      DateTime at(int year) {
        // A 29 February falls on the 28th in years without one.
        final d = day.month == 2 && day.day == 29 && !_isLeap(year) ? 28 : day.day;
        return DateTime(year, day.month, d, hour);
      }

      if (!m.repeatsYearly) {
        final when = at(day.year);
        if (when.isAfter(now)) due.add((when: when, title: title, body: 'Today 💖'));
        continue;
      }
      var year = day.year;
      while (!at(year).isAfter(now)) {
        year++;
      }
      for (var i = 0; i < _yearsAhead; i++, year++) {
        final years = year - day.year;
        due.add((
          when: at(year),
          title: title,
          body: years > 0 ? '$years ${years == 1 ? 'year' : 'years'} today! 💖' : 'Today 💖',
        ));
      }
    }
    due.sort((a, b) => a.when.compareTo(b.when));
    return [
      for (var i = 0; i < due.length && i < _maxPending; i++)
        Reminder(id: i + 1, title: due[i].title, body: due[i].body, when: due[i].when),
    ];
  }

  static bool _isLeap(int y) => (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;

  /// Replaces everything scheduled with the reminders for [milestones].
  Future<void> schedule(List<Milestone> milestones) async {
    await scheduler.cancelAll();
    for (final r in plan(milestones, _now())) {
      await scheduler.schedule(r);
    }
  }

  /// Removes every reminder (sign-out, disconnect, account deletion).
  Future<void> cancelAll() => scheduler.cancelAll();
}

/// The real scheduler, using the platform's local notifications.
class PluginReminderScheduler implements ReminderScheduler {
  PluginReminderScheduler([FlutterLocalNotificationsPlugin? plugin]) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  Future<void>? _ready;

  Future<void> _init() => _ready ??= () async {
        tzdata.initializeTimeZones();
        try {
          tz.setLocalLocation(tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier));
        } catch (_) {
          // Unknown zone: reminders fall back to UTC rather than not being scheduled at all.
        }
        await _plugin.initialize(
          settings: const InitializationSettings(
            android: AndroidInitializationSettings('@mipmap/ic_launcher'),
            // The permission is asked for once, with the push notifications.
            iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
          ),
        );
      }();

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'date_reminders',
      'Date reminders',
      channelDescription: 'Reminders for the dates on your timeline',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  @override
  Future<void> cancelAll() async {
    await _init();
    await _plugin.cancelAllPendingNotifications();
  }

  @override
  Future<void> schedule(Reminder r) async {
    await _init();
    final w = r.when;
    await _plugin.zonedSchedule(
      id: r.id,
      title: r.title,
      body: r.body,
      scheduledDate: tz.TZDateTime(tz.local, w.year, w.month, w.day, w.hour, w.minute),
      notificationDetails: _details,
      // Inexact: a reminder at about 9:00 needs no exact-alarm permission.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }
}

/// Keeps the reminders current: on launch and whenever the app returns to the foreground it loads the
/// couple's dates and schedules them. Also what puts them in place on a partner's phone, which never has
/// to open the timeline.
class ReminderSync with WidgetsBindingObserver {
  ReminderSync._(this._reminders);
  final ReminderService _reminders;

  static const _minGap = Duration(minutes: 10);
  DateTime? _last;

  static void init(ReminderService reminders) {
    final sync = ReminderSync._(reminders);
    WidgetsBinding.instance.addObserver(sync);
    sync._sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _sync();
  }

  Future<void> _sync() async {
    if (Supabase.instance.client.auth.currentUser == null) return;
    final last = _last;
    if (last != null && DateTime.now().difference(last) < _minGap) return;
    _last = DateTime.now();
    try {
      final user = await GetIt.I<IAuthRepository>().getCurrentUser();
      final coupleId = user?.coupleId;
      if (coupleId == null) return await _reminders.cancelAll();
      await _reminders.schedule(await GetIt.I<IMilestoneRepository>().getMilestones(coupleId));
    } catch (_) {
      // Best effort: the reminders already scheduled stay as they are.
    }
  }
}
