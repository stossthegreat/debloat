import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../config/dev_flags.dart';
import 'local_store_service.dart';

/// Centralised paywall gating. Every flood-gate check in the app routes
/// through here so the rules (2 scans/week, 10 renders/month, 1 free
/// rizz screenshot, LINES + CHAT locked) live in one place.
///
/// Bro: "look at the system that works perfectly do it no bullshit" —
/// the game tab's pattern (free flow + isSubscribed) is the reference.
/// This service is the same idea generalised across every gate.
class PaywallGate {
  /// True when the user has paid (or kBypassPaywall is on for dev).
  static Future<bool> isPro() async {
    if (kBypassPaywall) return true;
    return LocalStoreService.isSubscribed();
  }

  // ── Scan gate (2 / week for free users) ─────────────────────────────────
  /// True when a free user has burned their weekly scan quota. Pro users
  /// always return false (unlimited).
  static Future<bool> scanCapReached() async {
    if (await isPro()) return false;
    final used = await LocalStoreService.scansThisWeek();
    return used >= LocalStoreService.kScansPerWeek;
  }

  /// Free scans remaining this week (negative-safe, 0 when capped or pro).
  static Future<int> scansRemainingThisWeek() async {
    if (await isPro()) return -1; // sentinel: unlimited
    final used = await LocalStoreService.scansThisWeek();
    final left = LocalStoreService.kScansPerWeek - used;
    return left < 0 ? 0 : left;
  }

  // ── Mirror render gate (10 / month for free users) ──────────────────────
  static Future<bool> renderCapReached() async {
    if (await isPro()) return false;
    final used = await LocalStoreService.mirrorRendersThisMonth();
    return used >= LocalStoreService.kRendersPerMonth;
  }

  // ── Rizz screenshot gate (1 free use ever) ─────────────────────────────
  static Future<bool> rizzScreenshotCapReached() async {
    if (await isPro()) return false;
    return LocalStoreService.rizzScreenshotFreeUsed();
  }

  // ── Rizz LINES + CHAT (paywalled outright for free users) ─────────────
  /// Bro: "the other two rizz cards i.e lines and chat are locked."
  /// No free preview. Pro only.
  static Future<bool> rizzLinesLocked() async => !(await isPro());
  static Future<bool> rizzChatLocked()  async => !(await isPro());

  // ── Open paywall + re-check on return ──────────────────────────────────
  /// Push the paywall onto the navigation stack with a contextual
  /// `source` for analytics. Returns true if the user came back as pro.
  static Future<bool> open(BuildContext context, {required String source}) async {
    await context.push('/paywall', extra: {'source': source});
    if (!context.mounted) return false;
    return isPro();
  }
}
