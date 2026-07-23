import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists every answer the onboarding funnel collects, so the plan-ready
/// screen + the analysis can personalise, and so a mid-funnel app kill
/// doesn't lose progress. One flat key namespace ('onb.*'). All writes are
/// fire-and-forget from the UI; reads happen on the screens that need them.
class OnboardingStore {
  static const _kName      = 'onb.name';
  static const _kGoals     = 'onb.goals';       // JSON list<String>
  static const _kWaterL    = 'onb.waterL';      // double, litres/day
  static const _kSleepH    = 'onb.sleepH';      // double, hours/night
  static const _kStruggles = 'onb.struggles';   // JSON list<String>
  static const _kFamiliar  = 'onb.familiarity'; // String
  static const _kCreator   = 'onb.creatorCode'; // String

  static Future<void> setName(String v) async =>
      (await SharedPreferences.getInstance()).setString(_kName, v.trim());
  static Future<String> name() async =>
      (await SharedPreferences.getInstance()).getString(_kName) ?? '';

  static Future<void> setGoals(List<String> v) async =>
      (await SharedPreferences.getInstance()).setString(_kGoals, jsonEncode(v));
  static Future<List<String>> goals() async {
    final raw = (await SharedPreferences.getInstance()).getString(_kGoals);
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List).map((e) => e.toString()).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> setStruggles(List<String> v) async =>
      (await SharedPreferences.getInstance())
          .setString(_kStruggles, jsonEncode(v));
  static Future<List<String>> struggles() async {
    final raw = (await SharedPreferences.getInstance()).getString(_kStruggles);
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List).map((e) => e.toString()).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> setWaterLitres(double v) async =>
      (await SharedPreferences.getInstance()).setDouble(_kWaterL, v);
  static Future<double> waterLitres() async =>
      (await SharedPreferences.getInstance()).getDouble(_kWaterL) ?? 2.5;

  static Future<void> setSleepHours(double v) async =>
      (await SharedPreferences.getInstance()).setDouble(_kSleepH, v);
  static Future<double> sleepHours() async =>
      (await SharedPreferences.getInstance()).getDouble(_kSleepH) ?? 6.5;

  static Future<void> setFamiliarity(String v) async =>
      (await SharedPreferences.getInstance()).setString(_kFamiliar, v);
  static Future<String> familiarity() async =>
      (await SharedPreferences.getInstance()).getString(_kFamiliar) ?? '';

  static Future<void> setCreatorCode(String v) async =>
      (await SharedPreferences.getInstance()).setString(_kCreator, v.trim());
  static Future<String> creatorCode() async =>
      (await SharedPreferences.getInstance()).getString(_kCreator) ?? '';
}
