import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../config/auralay_dev_flags.dart';
import '../../theme/auralay_app_colors.dart';
import '../../theme/auralay_app_typography.dart';
import '../../widgets/safe_close_button.dart';

/// TROUBLESHOOT — one screen that hits every backend endpoint the app
/// depends on, shows the verbatim response, and lets the apprentice
/// copy the whole report to the clipboard.
///
/// Reachable from Settings → TROUBLESHOOT. Reachable from the in-
/// session DebugPanel's "DIAGNOSTICS" button. The whole point is to
/// surface backend / OpenAI failures the moment they happen, with no
/// guesswork — and to give us a structured report we can act on.
class DiagnosticScreen extends StatefulWidget {
  const DiagnosticScreen({super.key});

  @override
  State<DiagnosticScreen> createState() => _DiagnosticScreenState();
}

enum _CheckState { idle, running, pass, fail }

extension on _CheckState {
  String get label => switch (this) {
        _CheckState.idle    => 'IDLE',
        _CheckState.running => 'RUNNING',
        _CheckState.pass    => 'PASS',
        _CheckState.fail    => 'FAIL',
      };

  Color get color => switch (this) {
        _CheckState.idle    => AppColors.textTertiary,
        _CheckState.running => AppColors.signalAmber,
        _CheckState.pass    => AppColors.signalGreen,
        _CheckState.fail    => AppColors.signalRed,
      };
}

class _Check {
  final String name;
  final String method;
  final String url;
  final String? body;
  _CheckState state = _CheckState.idle;
  int? statusCode;
  String? responseBody;
  int? elapsedMs;
  bool expanded = false;

  _Check({
    required this.name,
    required this.method,
    required this.url,
    this.body,
  });
}

class _DiagnosticScreenState extends State<DiagnosticScreen> {
  late final List<_Check> _checks;
  bool _running = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _setupChecks();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runAll());
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _setupChecks() {
    final base = AuralayDevFlags.apiBaseUrl;
    _checks = [
      _Check(
        name:   'BACKEND HEALTH',
        method: 'GET',
        url:    '$base/v1/debug/health',
      ),
      _Check(
        name:   'OPENAI KEY (redacted)',
        method: 'GET',
        url:    '$base/v1/debug/env',
      ),
      _Check(
        name:   'PERSONAS / VOICES',
        method: 'GET',
        url:    '$base/v1/debug/voices',
      ),
      _Check(
        name:   'OPENAI REALTIME MINT (minimal)',
        method: 'GET',
        url:    '$base/v1/debug/openai-test',
      ),
      _Check(
        name:   'DIABLA TTS',
        method: 'POST',
        url:    '$base/v1/diablo/speak',
        body:   '{"text":"diagnostic test, one two three.","mode":"diabla"}',
      ),
      _Check(
        name:   'REALTIME SESSION (practice)',
        method: 'POST',
        url:    '$base/v1/realtime/session',
        body:   '{"teacherId":"diabla","topic":"rizz","mode":"practice"}',
      ),
    ];
  }

  Future<void> _runAll() async {
    if (_running || _disposed) return;
    setState(() {
      _running = true;
      for (final c in _checks) {
        c.state        = _CheckState.idle;
        c.statusCode   = null;
        c.responseBody = null;
        c.elapsedMs    = null;
      }
    });
    for (final c in _checks) {
      if (_disposed) return;
      setState(() => c.state = _CheckState.running);
      await _runOne(c);
      if (_disposed) return;
      setState(() {});
    }
    if (_disposed) return;
    setState(() => _running = false);
  }

  Future<void> _runOne(_Check c) async {
    final started = DateTime.now().millisecondsSinceEpoch;
    try {
      final uri = Uri.parse(c.url);
      final resp = c.method == 'POST'
          ? await http.post(
              uri,
              headers: const {'content-type': 'application/json'},
              body: c.body,
            ).timeout(const Duration(seconds: 20))
          : await http
              .get(uri)
              .timeout(const Duration(seconds: 20));
      c.statusCode   = resp.statusCode;
      c.responseBody = resp.body.length > 2000
          ? '${resp.body.substring(0, 2000)}…(truncated, full length ${resp.body.length})'
          : resp.body;
      c.state        = (resp.statusCode >= 200 && resp.statusCode < 300)
          ? _CheckState.pass
          : _CheckState.fail;
    } on TimeoutException {
      c.state        = _CheckState.fail;
      c.responseBody = 'TIMEOUT after 20s — server did not respond';
    } catch (e) {
      c.state        = _CheckState.fail;
      c.responseBody = 'EXCEPTION: $e';
    } finally {
      c.elapsedMs = DateTime.now().millisecondsSinceEpoch - started;
    }
  }

  String _buildReport() {
    final sb = StringBuffer();
    sb.writeln('IMHIM LOOKS DIAGNOSTIC REPORT');
    sb.writeln('Timestamp:    ${DateTime.now().toIso8601String()}');
    sb.writeln('Backend URL:  ${AuralayDevFlags.apiBaseUrl}');
    sb.writeln('hasBackend:   ${AuralayDevFlags.hasBackend}');
    sb.writeln('===========================================');
    sb.writeln();
    for (final c in _checks) {
      sb.writeln('▶ ${c.name}');
      sb.writeln('    state:    ${c.state.label}');
      sb.writeln('    method:   ${c.method}');
      sb.writeln('    url:      ${c.url}');
      if (c.body != null) sb.writeln('    body:     ${c.body}');
      sb.writeln('    elapsed:  ${c.elapsedMs ?? "—"}ms');
      sb.writeln('    status:   ${c.statusCode ?? "—"}');
      sb.writeln('    response: ${c.responseBody ?? "(none)"}');
      sb.writeln();
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
        content: Text('Diagnostic report copied to clipboard.',
            style: TextStyle(color: AppColors.textPrimary)),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // ─── UI ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final base = AuralayDevFlags.apiBaseUrl;
    return Scaffold(
      backgroundColor: AppColors.base,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Top chrome ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 14, 6),
              child: Row(
                children: [
                  Text('TROUBLESHOOT',
                      style: AppTypography.label.copyWith(
                        color: AppColors.accent,
                        fontSize: 11,
                        letterSpacing: 3,
                        fontWeight: FontWeight.w900,
                      )),
                  const Spacer(),
                  const SafeCloseButton(),
                ],
              ),
            ),

            // ── Backend URL banner ────────────────────────────────────
            Container(
              margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: AppColors.surface1,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.divider, width: 0.6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('BACKEND URL',
                      style: AppTypography.label.copyWith(
                        color: AppColors.textTertiary,
                        fontSize: 9.5,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w900,
                      )),
                  const SizedBox(height: 4),
                  SelectableText(
                    base.isEmpty ? '(AURALAY_API env var not set)' : base,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontFamily: 'monospace',
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),

            // ── RE-RUN button ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: GestureDetector(
                onTap: _running ? null : _runAll,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _running
                        ? AppColors.surface3
                        : AppColors.accent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _running ? 'RUNNING…' : 'RE-RUN ALL CHECKS',
                    style: AppTypography.label.copyWith(
                      color: Colors.white,
                      fontSize: 12,
                      letterSpacing: 3,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),

            // ── Check list ────────────────────────────────────────────
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 80),
                itemCount: _checks.length,
                itemBuilder: (_, i) => _CheckTile(
                  check: _checks[i],
                  onToggle: () {
                    setState(() => _checks[i].expanded = !_checks[i].expanded);
                  },
                ),
              ),
            ),
          ],
        ),
      ),

      // ── COPY REPORT — pinned at the bottom ──────────────────────────
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: GestureDetector(
            onTap: _copyReport,
            behavior: HitTestBehavior.opaque,
            child: Container(
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.accentBorder, width: 0.8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.copy_rounded,
                      color: AppColors.accent, size: 16),
                  const SizedBox(width: 10),
                  Text('COPY FULL REPORT',
                      style: AppTypography.label.copyWith(
                        color: AppColors.accent,
                        fontSize: 12,
                        letterSpacing: 3,
                        fontWeight: FontWeight.w900,
                      )),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckTile extends StatelessWidget {
  final _Check check;
  final VoidCallback onToggle;
  const _CheckTile({required this.check, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final c = check;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: c.state == _CheckState.fail
              ? AppColors.signalRedBorder
              : c.state == _CheckState.pass
                  ? AppColors.signalGreenBorder
                  : AppColors.divider,
          width: 0.8,
        ),
      ),
      child: Column(
        children: [
          // Header row — name + state pill + chevron.
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(c.name,
                        style: AppTypography.label.copyWith(
                          color: Colors.white,
                          fontSize: 12,
                          letterSpacing: 1.8,
                          fontWeight: FontWeight.w900,
                        )),
                  ),
                  // State pill.
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: c.state.color.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(
                          color: c.state.color.withValues(alpha: 0.55),
                          width: 0.6),
                    ),
                    child: Text(
                      c.statusCode != null
                          ? '${c.state.label} · ${c.statusCode}'
                          : c.state.label,
                      style: AppTypography.label.copyWith(
                        color: c.state.color,
                        fontSize: 9.5,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    c.expanded ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.textTertiary,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),

          // Expanded body — URL + response.
          if (c.expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(height: 0.5, color: AppColors.divider),
                  const SizedBox(height: 10),
                  _kvLine('METHOD', c.method),
                  _kvLine('URL',    c.url),
                  if (c.body != null) _kvLine('BODY', c.body!),
                  _kvLine('ELAPSED', '${c.elapsedMs ?? "—"} ms'),
                  _kvLine('STATUS',  c.statusCode?.toString() ?? '—'),
                  const SizedBox(height: 8),
                  Text('RESPONSE',
                      style: AppTypography.label.copyWith(
                        color: AppColors.textTertiary,
                        fontSize: 9.5,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w900,
                      )),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.base,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: AppColors.divider, width: 0.5),
                    ),
                    child: SelectableText(
                      _prettyPrintIfJson(c.responseBody ?? '(no response)'),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 11,
                        fontFamily: 'monospace',
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _kvLine(String key, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(key,
                style: AppTypography.label.copyWith(
                  color: AppColors.textTertiary,
                  fontSize: 9.5,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w900,
                )),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: SelectableText(value,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 11,
                  fontFamily: 'monospace',
                  height: 1.4,
                )),
          ),
        ],
      ),
    );
  }

  String _prettyPrintIfJson(String raw) {
    try {
      final parsed = jsonDecode(raw);
      return const JsonEncoder.withIndent('  ').convert(parsed);
    } catch (_) {
      return raw;
    }
  }
}
