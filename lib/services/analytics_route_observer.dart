import 'package:flutter/material.dart';

import 'analytics_service.dart';

/// Router observer that fires `screen_view` on every navigation event.
/// Wired into [GoRouter] via its `observers` list so EVERY push, pop,
/// and replacement automatically tags the new top-of-stack route.
///
/// Why bother when Firebase ships [FirebaseAnalyticsObserver]?
///   1. We want a single chokepoint: AnalyticsService.screenView updates
///      [AnalyticsService.currentScreen] so the lifecycle hook can read
///      "where did the user quit from".
///   2. go_router stores its route metadata on `RouteSettings.name`
///      already; we just normalise the name a touch (strip params,
///      collapse "/" → "home").
///   3. Debug logging passes through one place.
class AnalyticsRouteObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _tag(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute != null) _tag(newRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) _tag(previousRoute);
  }

  void _tag(Route<dynamic> route) {
    final name = _normalise(route.settings.name);
    if (name == null) return;
    // ignore: discarded_futures
    AnalyticsService.screenView(name, route.runtimeType.toString());
  }

  /// Path-like ("/scan", "/lesson/the_lock") → flat snake-case
  /// ("scan", "lesson_the_lock"). Empty / null / "/" → "home" so
  /// the splash + bootstrap step doesn't show up as a blank screen
  /// in the Firebase Screens report.
  String? _normalise(String? raw) {
    if (raw == null) return null;
    if (raw == '/' || raw.isEmpty) return 'home';
    var s = raw;
    if (s.startsWith('/')) s = s.substring(1);
    s = s.replaceAll('/', '_').replaceAll('-', '_');
    return s.isEmpty ? null : s;
  }
}
