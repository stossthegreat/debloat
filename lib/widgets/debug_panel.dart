import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../config/auralay_dev_flags.dart';
import '../theme/auralay_app_colors.dart';
import '../theme/auralay_app_typography.dart';

/// One debug event — a single line of state surfaced in the debug
/// overlay. Owned by whichever screen mounts the panel.
class DebugEvent {
  final DateTime ts;
  final String level;   // 'info' | 'warn' | 'error' | 'ok'
  final String tag;     // short, e.g. 'WS', 'API', 'MIC'
  final String message;
  const DebugEvent({
    required this.ts,
    required this.level,
    required this.tag,
    required this.message,
  });
}

/// DebugPanel — bottom-left bug icon. Tap to expand into a fixed
/// overlay that shows the supplied [kvs] (key-value map) + the last N
/// [events]. The overlay is dismissible by tapping outside.
///
/// AUTO-EXPANDS when the latest [events] entry is at 'error' level —
/// the user shouldn't have to find the bug icon to see what broke.
///
/// Two buttons live at the top of the expanded panel:
///   - COPY        — copies a structured report (KVs + events) to
///                   the clipboard so the user can paste it back.
///   - DIAGNOSTICS — pushes /diagnostic, which hits every backend
///                   endpoint and surfaces the verbatim response.
class DebugPanel extends StatefulWidget {
  final Map<String, String> kvs;
  final List<DebugEvent> events;
  final EdgeInsets margin;

  const DebugPanel({
    super.key,
    required this.kvs,
    required this.events,
    this.margin = const EdgeInsets.only(left: 10, bottom: 10),
  });

  @override
  State<DebugPanel> createState() => _DebugPanelState();
}

class _DebugPanelState extends State<DebugPanel> {
  bool _open = false;

  /// Tracked so we only auto-expand ONCE per fresh error — re-collapses
  /// require the user to tap the bug.
  int _autoExpandedForCount = -1;
  int _lastSeenErrorCount  = 0;

  void _toggle() {
    HapticFeedback.selectionClick();
    setState(() => _open = !_open);
  }

  @override
  void didUpdateWidget(covariant DebugPanel old) {
    super.didUpdateWidget(old);
    _maybeAutoExpand();
  }

  void _maybeAutoExpand() {
    final errorCount = widget.events.where((e) => e.level == 'error').length;
    if (errorCount > _lastSeenErrorCount &&
        errorCount != _autoExpandedForCount) {
      // New error landed — pop the panel open so the user sees it.
      _lastSeenErrorCount  = errorCount;
      _autoExpandedForCount = errorCount;
      // Defer to next frame so we don't setState during build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_open) {
          setState(() => _open = true);
        }
      });
    } else if (errorCount > _lastSeenErrorCount) {
      _lastSeenErrorCount = errorCount;
    }
  }

  String _buildReport() {
    final sb = StringBuffer();
    sb.writeln('IMHIM LOOKS IN-SESSION DEBUG REPORT');
    sb.writeln('Timestamp: ${DateTime.now().toIso8601String()}');
    sb.writeln('===========================================');
    sb.writeln('STATE');
    for (final entry in widget.kvs.entries) {
      sb.writeln('  ${entry.key.padRight(10)}  ${entry.value}');
    }
    sb.writeln();
    sb.writeln('EVENTS  (most recent last)');
    for (final e in widget.events) {
      final hh = e.ts.hour.toString().padLeft(2, '0');
      final mm = e.ts.minute.toString().padLeft(2, '0');
      final ss = e.ts.second.toString().padLeft(2, '0');
      sb.writeln('  $hh:$mm:$ss  '
          '${e.level.toUpperCase().padRight(5)}  '
          '${e.tag.padRight(4)}  '
          '${e.message}');
    }
    return sb.toString();
  }

  Future<void> _copyReport() async {
    HapticFeedback.mediumImpact();
    await Clipboard.setData(ClipboardData(text: _buildReport()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: AppColors.surface3,
        content: Text('Debug report copied to clipboard.',
            style: TextStyle(color: AppColors.textPrimary)),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _openDiagnostics() {
    HapticFeedback.selectionClick();
    GoRouter.of(context).push('/diagnostic');
  }

  @override
  Widget build(BuildContext context) {
    if (!AuralayDevFlags.showDebugOverlay) return const SizedBox.shrink();
    return Padding(
      padding: widget.margin,
      child: Align(
        alignment: Alignment.bottomLeft,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _open ? _expanded() : _collapsed(),
        ),
      ),
    );
  }

  Widget _collapsed() {
    final hasError = widget.events.any((e) => e.level == 'error');
    return Semantics(
      label: 'Debug',
      button: true,
      child: GestureDetector(
        key: const ValueKey('debug-collapsed'),
        onTap: _toggle,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 36, height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hasError
                ? AppColors.signalRed.withValues(alpha: 0.18)
                : AppColors.surface1.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: hasError
                    ? AppColors.signalRed.withValues(alpha: 0.55)
                    : AppColors.divider,
                width: 0.6),
          ),
          child: Icon(Icons.bug_report_outlined,
              color: hasError ? AppColors.signalRed : AppColors.textTertiary,
              size: 16),
        ),
      ),
    );
  }

  Widget _expanded() {
    return Container(
      key: const ValueKey('debug-expanded'),
      width: 340,
      constraints: const BoxConstraints(maxHeight: 420),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xEE0A0A0C),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider, width: 0.6),
        boxShadow: const [
          BoxShadow(color: Colors.black, blurRadius: 24, spreadRadius: -4),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.bug_report_outlined,
                  color: AppColors.accent, size: 14),
              const SizedBox(width: 6),
              Text('DEBUG',
                  style: AppTypography.label.copyWith(
                    color: AppColors.accent,
                    fontSize: 10,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w900,
                  )),
              const Spacer(),
              _PanelButton(
                label: 'COPY',
                onTap: _copyReport,
              ),
              const SizedBox(width: 6),
              _PanelButton(
                label: 'DIAGNOSE',
                onTap: _openDiagnostics,
                isPrimary: true,
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: _toggle,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 28, height: 28,
                  alignment: Alignment.center,
                  child: const Icon(Icons.close_rounded,
                      color: AppColors.textTertiary, size: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final entry in widget.kvs.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 80,
                    child: Text(entry.key,
                        style: const TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 10,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w700,
                        )),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(entry.value,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 10,
                          fontFamily: 'monospace',
                          height: 1.35,
                        )),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Container(height: 0.5, color: AppColors.divider),
          const SizedBox(height: 6),
          Flexible(
            child: SingleChildScrollView(
              reverse: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final e in widget.events) _eventLine(e),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _eventLine(DebugEvent e) {
    Color color;
    switch (e.level) {
      case 'error': color = AppColors.signalRed;   break;
      case 'warn':  color = AppColors.signalAmber; break;
      case 'ok':    color = AppColors.signalGreen; break;
      default:      color = AppColors.textSecondary;
    }
    final hh = e.ts.hour.toString().padLeft(2, '0');
    final mm = e.ts.minute.toString().padLeft(2, '0');
    final ss = e.ts.second.toString().padLeft(2, '0');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Text(
        '$hh:$mm:$ss  ${e.tag.padRight(4)}  ${e.message}',
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontFamily: 'monospace',
          height: 1.35,
        ),
      ),
    );
  }
}

class _PanelButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool isPrimary;
  const _PanelButton({
    required this.label,
    required this.onTap,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: isPrimary
              ? AppColors.accent
              : AppColors.surface3,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Text(label,
            style: AppTypography.label.copyWith(
              color: isPrimary ? Colors.white : AppColors.accent,
              fontSize: 9,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w900,
            )),
      ),
    );
  }
}
