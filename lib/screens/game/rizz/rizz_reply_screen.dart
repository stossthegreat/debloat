import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../services/analytics_service.dart';
import '../../../services/local_store_service.dart';
import '../../../services/paywall_gate.dart';
import '../../../services/rizz_reply_service.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/common/imhim_wordmark.dart';

/// Debug pane visibility — flip true to surface the OCR / endpoint /
/// raw-response trail under the GIMME MORE button. Off for ship.
const _kRizzDebug = false;

/// RIZZ — clean, two-state generator.
///
/// INPUT STATE — no results yet:
///   · italic Playfair headline + back arrow
///   · single tap UPLOAD A SCREENSHOT pill (auto-fires on entry
///     when the screen was launched from the Rizz tab "Upload" card)
///   · "or type her message" expand → text field + GENERATE
///
/// RESULTS STATE — once the AI has spoken:
///   · screenshot rendered FULL-WIDTH at the top so the user can see
///     what got read (and that OCR worked)
///   · three red iMessage bubbles below, tap to copy each
///   · GIMME MORE pill at the bottom to re-roll
///   · ⊕ icon in the top-right to start a fresh image / clear state
class RizzReplyScreen extends StatefulWidget {
  /// True when opened from the "Upload a screenshot" tab card — fires
  /// the photo picker immediately so the user lands in the iOS sheet.
  final bool launchUpload;

  /// Non-null when the screen was opened via the iOS Share Extension
  /// (a screenshot shared from outside the app). Bytes are wired
  /// straight into the existing OCR + reply pipeline as if the user
  /// had picked the image from Photos.
  final Uint8List? preloadedScreenshot;

  const RizzReplyScreen({
    super.key,
    this.launchUpload = false,
    this.preloadedScreenshot,
  });

  @override
  State<RizzReplyScreen> createState() => _RizzReplyScreenState();
}

class _RizzReplyScreenState extends State<RizzReplyScreen> {
  final _herCtrl = TextEditingController();
  bool _generating = false;
  Uint8List? _screenshotBytes;
  List<RizzReply>? _replies;
  bool _showTextEntry = false;
  /// Active tone preset. Default FLIRTY mirrors the WingAI default
  /// the user benchmarked us against. The bottom-of-results pill
  /// opens a picker that lets the user swap to SENSUAL / PLAYFUL /
  /// CONFIDENT / SINCERE; tapping a new tone or a situation chip
  /// re-fires _generate so the existing replies refresh in-place.
  RizzVibe _tone = RizzVibe.flirty;
  /// Scenario bias for the NEXT generate — set by situation chips
  /// ("Turn up heat", "Tease a bit", "Plan a date"). Cleared the
  /// moment the request fires so subsequent re-rolls don't keep
  /// the bias unless the user re-selects.
  String _scenario = '';

  @override
  void initState() {
    super.initState();
    // Share-extension intake: if the screen was opened with bytes
    // already in hand, plant them in state and auto-fire the same
    // OCR + reply pipeline the image picker uses.
    if (widget.preloadedScreenshot != null) {
      _screenshotBytes = widget.preloadedScreenshot;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        // ignore: discarded_futures
        AnalyticsService.rizzScreenshotUploaded(hasText: false);
        await _generate();
      });
      return;
    }
    if (widget.launchUpload) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pick(ImageSource.gallery);
      });
    }
  }

  @override
  void dispose() {
    _herCtrl.dispose();
    super.dispose();
  }

  bool get _canGenerate {
    if (_generating) return false;
    if (_screenshotBytes != null) return true;
    return _herCtrl.text.trim().isNotEmpty;
  }

  Future<void> _pick(ImageSource source) async {
    HapticFeedback.selectionClick();
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: source, maxWidth: 1800);
      if (picked == null || !mounted) return;
      final bytes = await File(picked.path).readAsBytes();
      if (!mounted) return;
      setState(() {
        _screenshotBytes = bytes;
        _replies = null;
        _herCtrl.clear();
        _showTextEntry = false;
      });
      // ignore: discarded_futures
      AnalyticsService.rizzScreenshotUploaded(
        hasText: _herCtrl.text.trim().isNotEmpty,
      );
      // Auto-generate the moment the image lands — saves a tap. The
      // user picked a screenshot precisely because they want rizz.
      await _generate();
    } catch (_) {
      if (!mounted) return;
      _snack('Couldn\'t load that image. Try another.');
    }
  }

  void _reset() {
    HapticFeedback.selectionClick();
    setState(() {
      _screenshotBytes = null;
      _replies = null;
      _herCtrl.clear();
      _showTextEntry = false;
    });
  }

  Future<void> _generate() async {
    if (!_canGenerate) return;
    // Paywall gate — non-pro users get ONE free rizz generation.
    // The second tap (after the bool flips) lands on the paywall.
    // Pro users always pass.
    final pro      = await PaywallGate.isPro();
    final ssUsed   = await LocalStoreService.rizzScreenshotFreeUsed();
    if (!pro && ssUsed) {
      if (!mounted) return;
      setState(() => _generating = false);
      // ignore: discarded_futures
      AnalyticsService.rizzBlockedFreeCap('screenshot_generate');
      await context.push('/paywall',
          extra: {'source': 'rizz_screenshot_capped'});
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() {
      _generating = true;
      _replies = null;
    });
    // Snapshot + clear scenario BEFORE the await so a timeout/error
    // doesn't leave the chip-bias sticky for the next re-roll.
    final scenarioForCall = _scenario;
    _scenario = '';
    // v203 cost fix: any time we already have three replies on screen,
    // pass them in as `previous` so the backend goes into TRANSFORM
    // mode — rewrites the angles without re-reading the screenshot.
    // Saves a gpt-4o vision call on every GIMME MORE + every preset
    // chip tap (which used to re-burn vision tokens on every press).
    // First-ever generate keeps the image because previousForCall is
    // empty by definition.
    final previousForCall = _replies != null
        ? List<RizzReply>.from(_replies!)
        : const <RizzReply>[];
    print('[RIZZ-SCREEN] _generate start hasImage=${_screenshotBytes != null} '
        'textLen=${_herCtrl.text.trim().length} scn="$scenarioForCall" '
        'transform=${previousForCall.isNotEmpty}');
    // Hard 45s ceiling — even if the backend hangs, the spinner
    // clears + the user sees a clear "try again" snack instead of
    // forever-stuck "READING THE CHAT…".
    try {
      final result = await RizzReplyService.generate(
        herMessage:       _herCtrl.text.trim(),
        screenshotBytes:  _screenshotBytes,
        vibe:             _tone,
        scenario:         scenarioForCall,
        previous:         previousForCall,
      // 55s ceiling — vision adds ~1-2s vs text path; this gives the
      // service-level 50s some headroom before the spinner clears.
      ).timeout(const Duration(seconds: 55));
      print('[RIZZ-SCREEN] _generate got ${result.length} replies');
      if (!mounted) return;
      setState(() {
        _replies = result;
        _generating = false;
      });
      // ignore: discarded_futures
      AnalyticsService.rizzRepliesGenerated(
        count:  result.length,
        isFree: !pro,
      );
      // Burn the free pass — every subsequent tap routes to paywall.
      // Pro users keep generating without ever flipping this bit.
      if (!pro) {
        await LocalStoreService.markRizzScreenshotFreeUsed();
      }
    } on TimeoutException {
      print('[RIZZ-SCREEN] _generate timed out');
      if (!mounted) return;
      setState(() => _generating = false);
      _snack('Took too long — try a clearer screenshot.');
    } catch (e) {
      print('[RIZZ-SCREEN] _generate throw $e');
      if (!mounted) return;
      setState(() => _generating = false);
      _snack('Couldn\'t generate — try again.');
    }
  }

  Future<void> _copy(RizzReply r) async {
    HapticFeedback.mediumImpact();
    await Clipboard.setData(ClipboardData(text: r.text));
    if (!mounted) return;
    _snack('Copied. Send it.');
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
        style: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 14, fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        )),
      backgroundColor: AppColors.red,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final hasResults = _replies != null;
    final hasImage   = _screenshotBytes != null;
    return Scaffold(
      backgroundColor: Colors.black,
      // Tap anywhere outside the text field to dismiss the keyboard.
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: Column(
            children: [
              _Header(
                // v216 fix: Navigator.maybePop() did nothing when the
                // screen was entered via go() from the iOS Share
                // Extension (and sometimes from the Rizz tab too —
                // go_router's nested-stack push doesn't always leave
                // a Navigator route in the local Material stack).
                // Result: tapping the back chevron after a screenshot
                // landed felt completely broken. Now we route through
                // go_router and fall back to /home so there is always
                // a valid destination.
                onBack: () {
                  HapticFeedback.lightImpact();
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/home');
                  }
                },
                onReset: hasImage || hasResults ? _reset : null,
              ),
              Expanded(
                child: hasResults
                    ? _resultsLayout()
                    : _inputLayout(hasImage),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── INPUT STATE ────────────────────────────────────────────────────
  Widget _inputLayout(bool hasImage) {
    // Share-extension mode — the user arrived from the iOS Share
    // Sheet, the screenshot is already in hand, the scanner is
    // already running. Swap the "Drop her chat." headline for the
    // ImHim wordmark so the experience reads as ours from the
    // moment we open. Plays the same WingAI mental model: their
    // app opens with the brand on top + the scanning UI below.
    final fromShare = widget.preloadedScreenshot != null;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 6, 22, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (fromShare) ...[
            const SizedBox(height: 6),
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  ImHimWordmark(fontSize: 38, letterSpacing: -0.9),
                  SizedBox(width: 10),
                  _BrandHeartbeatDot(),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: Text(
                'Reading your chat — three hits incoming.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: AppColors.textSecondary,
                  fontSize: 13.5, height: 1.4,
                  letterSpacing: 0.1,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ] else ...[
            Text('Drop her chat.',
              style: GoogleFonts.playfairDisplay(
                color: Colors.white,
                fontSize: 36, height: 1.05,
                letterSpacing: -0.7,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w800,
              )),
            Text('Get 3 hits.',
              style: GoogleFonts.playfairDisplay(
                color: AppColors.red,
                fontSize: 36, height: 1.05,
                letterSpacing: -0.7,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w800,
              )),
          ],

          const SizedBox(height: 28),

          if (_generating)
            _GeneratingPanel(bytes: _screenshotBytes)
          else ...[
            _BigUploadButton(
              onTap: () => _pick(ImageSource.gallery),
              icon: Icons.photo_library_outlined,
              label: 'UPLOAD A SCREENSHOT',
              filled: true,
            ),
            const SizedBox(height: 18),
            if (!_showTextEntry)
              Center(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _showTextEntry = true);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text('or type her message  ›',
                      style: GoogleFonts.inter(
                        color: AppColors.textSecondary,
                        fontSize: 13, letterSpacing: 0.4,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w600,
                      )),
                  ),
                ),
              )
            else ...[
              _TextInput(
                controller: _herCtrl,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              _GenerateButton(
                enabled:    _canGenerate,
                generating: _generating,
                onTap:      _generate,
              ),
            ],
          ],
        ],
      ),
    );
  }

  // ── RESULTS STATE ──────────────────────────────────────────────────
  Widget _resultsLayout() {
    // Carry the ImHim wordmark into the results view too when the
    // flow began at the Share Extension. Keeps the WingAI-style
    // brand-on-top continuity all the way through to the chips.
    final fromShare = widget.preloadedScreenshot != null;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 6, 22, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (fromShare) ...[
            const SizedBox(height: 4),
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  ImHimWordmark(fontSize: 30, letterSpacing: -0.7),
                  SizedBox(width: 8),
                  _BrandHeartbeatDot(),
                ],
              ),
            ),
            const SizedBox(height: 18),
          ],

          // Full screenshot preview (or typed-text card if no image).
          if (_screenshotBytes != null)
            _ScreenshotFull(bytes: _screenshotBytes!)
          else if (_herCtrl.text.trim().isNotEmpty)
            _TypedHerCard(text: _herCtrl.text.trim()),

          const SizedBox(height: 18),

          Center(
            child: Text('TAP A REPLY TO COPY',
              style: GoogleFonts.inter(
                color: AppColors.textTertiary,
                fontSize: 11, letterSpacing: 2.8,
                fontWeight: FontWeight.w800,
              )),
          ),
          const SizedBox(height: 14),

          for (var i = 0; i < _replies!.length; i++) ...[
            _ReplyBubble(
              reply:    _replies![i],
              safeness: i,
              onTap:    () => _copy(_replies![i]),
            ),
            const SizedBox(height: 14),
          ],

          const SizedBox(height: 12),

          // ── SITUATION CHIPS ─ one-tap "more rizz" / "tease a bit"
          // / "turn up heat" / "plan a date". Each chip rewrites the
          // SAME three replies through that bias. The picked
          // scenario is one-shot — it lifts on the next request
          // unless the user picks again. Bro: "fire rizz that can
          // get extra rizz added to it."
          _ScenarioStrip(
            onTap: _useScenario,
            disabled: _generating,
          ),

          const SizedBox(height: 14),

          // ── GENERATE MORE pill — re-roll with current tone + last
          // scenario bias (cleared after one use).
          _GimmeMoreButton(
            generating: _generating,
            onTap:      _generate,
          ),

          const SizedBox(height: 14),

          // ── TONE PILL ─ bottom-row chip. Tap → bottom-sheet
          // picker. Picking a new tone re-fires generate so the
          // existing replies refresh into the new register.
          Center(
            child: _TonePill(
              tone: _tone,
              onTap: _generating ? null : _openTonePicker,
            ),
          ),

          if (_kRizzDebug) ...[
            const SizedBox(height: 18),
            const _RizzDebugPane(),
          ],
        ],
      ),
    );
  }

  // ── Tone picker bottom sheet ────────────────────────────────────────
  Future<void> _openTonePicker() async {
    HapticFeedback.selectionClick();
    final picked = await showModalBottomSheet<RizzVibe>(
      context: context,
      backgroundColor: Colors.transparent,
      // Bro: "needs to be scrollable, looks like one at the bottom
      // can't get to it." isScrollControlled lifts the default 50%
      // height cap; the sheet's inner Column is wrapped in a
      // SingleChildScrollView so 5 rows always reach.
      isScrollControlled: true,
      builder: (_) => _TonePickerSheet(current: _tone),
    );
    if (picked == null || picked == _tone || !mounted) return;
    setState(() => _tone = picked);
    // Refresh replies in the new tone the moment they pick.
    await _generate();
  }

  // ── Scenario chip handler ───────────────────────────────────────────
  Future<void> _useScenario(String scenario) async {
    if (_generating) return;
    HapticFeedback.selectionClick();
    _scenario = scenario;
    await _generate();
  }
}

/// In-screen debug pane that surfaces the live RizzDebug trail. Sits
/// at the bottom of the results layout so we can SEE every stage of
/// the OCR → API → parse pipeline without scrolling Xcode console.
/// Tap to expand the raw response.
class _RizzDebugPane extends StatefulWidget {
  const _RizzDebugPane();
  @override
  State<_RizzDebugPane> createState() => _RizzDebugPaneState();
}

class _RizzDebugPaneState extends State<_RizzDebugPane> {
  bool _open = false;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.red.withValues(alpha: 0.4), width: 0.6),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => setState(() => _open = !_open),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Icon(_open
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_right_rounded,
                    color: AppColors.red, size: 16),
                const SizedBox(width: 4),
                Text('DEBUG TRAIL',
                  style: GoogleFonts.inter(
                    color: AppColors.red,
                    fontSize: 10.5, letterSpacing: 2.4,
                    fontWeight: FontWeight.w800,
                  )),
                const Spacer(),
                Text('${RizzDebug.log.length} entries',
                  style: GoogleFonts.inter(
                    color: AppColors.textSecondary,
                    fontSize: 10.5, fontWeight: FontWeight.w600,
                  )),
              ],
            ),
          ),
          if (_open) ...[
            const SizedBox(height: 10),
            if (RizzDebug.ocrText.isNotEmpty) ...[
              _row('OCR (${RizzDebug.ocrText.length}c):',
                  RizzDebug.ocrText),
              const SizedBox(height: 6),
            ],
            _row('Endpoint:', RizzDebug.lastEndpoint),
            _row('Status:',   RizzDebug.lastStatus.toString()),
            _row('Parsed:',   '${RizzDebug.parsedCount} replies'),
            if (RizzDebug.lastResponse.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Raw response:',
                style: GoogleFonts.inter(
                  color: AppColors.red,
                  fontSize: 9.5, letterSpacing: 1.4,
                  fontWeight: FontWeight.w800,
                )),
              const SizedBox(height: 4),
              SelectableText(RizzDebug.lastResponse,
                style: GoogleFonts.firaCode(
                  color: AppColors.textPrimary,
                  fontSize: 10, height: 1.4,
                )),
            ],
            const SizedBox(height: 8),
            Text('Trail:',
              style: GoogleFonts.inter(
                color: AppColors.red,
                fontSize: 9.5, letterSpacing: 1.4,
                fontWeight: FontWeight.w800,
              )),
            const SizedBox(height: 4),
            for (final l in RizzDebug.log)
              Text(l,
                style: GoogleFonts.firaCode(
                  color: AppColors.textSecondary,
                  fontSize: 9.5, height: 1.35,
                )),
          ],
        ],
      ),
    );
  }

  Widget _row(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(text: '$k ',
              style: GoogleFonts.inter(
                color: AppColors.red,
                fontSize: 10, fontWeight: FontWeight.w800,
              )),
            TextSpan(text: v,
              style: GoogleFonts.firaCode(
                color: AppColors.textPrimary,
                fontSize: 10,
              )),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback? onReset;
  const _Header({required this.onBack, required this.onReset});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 14, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 4),
          Text('RIZZ',
            style: GoogleFonts.inter(
              color: AppColors.red,
              fontSize: 12, letterSpacing: 3.6,
              fontWeight: FontWeight.w800,
            )),
          const Spacer(),
          if (onReset != null)
            Material(
              color: AppColors.red,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: onReset,
                customBorder: const CircleBorder(),
                child: Container(
                  width: 38, height: 38,
                  alignment: Alignment.center,
                  child: const Icon(Icons.add_rounded,
                      color: Colors.white, size: 22),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ScreenshotFull extends StatelessWidget {
  final Uint8List bytes;
  const _ScreenshotFull({required this.bytes});

  @override
  Widget build(BuildContext context) {
    // Cap the screenshot at HALF the screen height. The rest of the
    // page (rizz bubbles + GIMME MORE) needs room to breathe; an
    // unconstrained Image.memory was filling the whole viewport and
    // pushing the results off the bottom.
    final maxH = MediaQuery.of(context).size.height * 0.42;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.red.withValues(alpha: 0.32), width: 0.8),
        boxShadow: [
          BoxShadow(
            color: AppColors.red.withValues(alpha: 0.14),
            blurRadius: 22, offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(8),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            alignment: Alignment.topCenter,
          ),
        ),
      ),
    );
  }
}

class _TypedHerCard extends StatelessWidget {
  final String text;
  const _TypedHerCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surface3, width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('HER',
            style: GoogleFonts.inter(
              color: AppColors.red,
              fontSize: 10, letterSpacing: 2.6,
              fontWeight: FontWeight.w800,
            )),
          const SizedBox(height: 6),
          Text('"$text"',
            style: GoogleFonts.inter(
              color: AppColors.textPrimary,
              fontSize: 15, height: 1.4,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w500,
            )),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Scanning panel — the WingAI-style screenshot scanner.
//
//  Composition (top to bottom):
//    · Screenshot full-width inside a rounded card, slightly dimmed so the
//      scan line + glow read clearly over any photo.
//    · A red gradient scan line that travels top → bottom → top forever
//      while the AI is reading; the line has a soft red bloom above and
//      below so it feels alive.
//    · A "SCANNING" label + italic Playfair percentage that eases from 0
//      towards 96% on its own clock (so the user always sees progress
//      even when the network is slow). The instant the parent flips
//      _generating off, the result chips replace the panel — the
//      percentage never has to reach 100, the replies ARE the 100.
//    · A thin red progress bar bound to the same animated value.
//
//  Implementation: two AnimationControllers (scan-line + percentage),
//  both autoplay-loop on mount + cleaned up on dispose.
// ═══════════════════════════════════════════════════════════════════════════
class _GeneratingPanel extends StatefulWidget {
  final Uint8List? bytes;
  const _GeneratingPanel({required this.bytes});

  @override
  State<_GeneratingPanel> createState() => _GeneratingPanelState();
}

class _GeneratingPanelState extends State<_GeneratingPanel>
    with TickerProviderStateMixin {
  /// Scan-line controller — loops 1.4s, drives a Tween from 0 → 1.
  /// The image's stack uses this value as a fraction of its own
  /// height to position the red line.
  late final AnimationController _scanCtl;

  /// Percentage controller — eases from 0 → 96 over ~14 seconds.
  /// Never autoplays past 96, so the user can keep watching it
  /// climb without the UX ever lying that things finished when
  /// they haven't. The replies appearing IS the 100% beat.
  late final AnimationController _pctCtl;

  @override
  void initState() {
    super.initState();
    _scanCtl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pctCtl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..forward();
  }

  @override
  void dispose() {
    _scanCtl.dispose();
    _pctCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.bytes != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: AspectRatio(
              aspectRatio: 9 / 16,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // The screenshot.
                  Image.memory(
                    widget.bytes!,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
                  // Subtle darken so the scan line + glow read clearly.
                  Container(color: Colors.black.withValues(alpha: 0.18)),
                  // The travelling scan line, fraction of card height.
                  AnimatedBuilder(
                    animation: _scanCtl,
                    builder: (_, __) {
                      // Curve gives the line a soft pause at each end
                      // instead of a hard ping-pong.
                      final v = Curves.easeInOutSine.transform(_scanCtl.value);
                      return Align(
                        alignment: Alignment(0, v * 2 - 1),
                        child: _ScanLine(),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 22),

        // SCANNING label + italic Playfair percentage.
        AnimatedBuilder(
          animation: _pctCtl,
          builder: (_, __) {
            final pct = (Curves.easeOutCubic.transform(_pctCtl.value) * 96)
                .clamp(0, 96)
                .toInt();
            return Column(
              children: [
                Text(
                  'SCANNING',
                  style: GoogleFonts.inter(
                    color: AppColors.red,
                    fontSize: 11, letterSpacing: 3.6,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                RichText(
                  text: TextSpan(
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 42, height: 1,
                      letterSpacing: -1.6,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w800,
                    ),
                    children: [
                      TextSpan(
                        text: '$pct',
                        style: const TextStyle(color: Colors.white),
                      ),
                      TextSpan(
                        text: '%',
                        style: TextStyle(color: AppColors.red),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                // Thin progress bar — same animated value.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 36),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: pct / 100,
                      backgroundColor: AppColors.surface3,
                      valueColor: const AlwaysStoppedAnimation(AppColors.red),
                      minHeight: 3,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// The travelling red bar that sits inside the screenshot card.
/// Thin core line with a soft red bloom above and below — gives the
/// "screen being scanned" feel without overpowering the image.
class _ScanLine extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [
            AppColors.red.withValues(alpha: 0.00),
            AppColors.red.withValues(alpha: 0.55),
            AppColors.red.withValues(alpha: 0.00),
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
      child: Center(
        child: Container(
          height: 2,
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: AppColors.red.withValues(alpha: 0.9),
                blurRadius: 14, spreadRadius: 2),
            ],
          ),
        ),
      ),
    );
  }
}

class _BigUploadButton extends StatelessWidget {
  final VoidCallback onTap;
  final IconData icon;
  final String label;
  final bool filled;
  const _BigUploadButton({
    required this.onTap,
    required this.icon,
    required this.label,
    required this.filled,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? AppColors.red : Colors.transparent,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            border: filled
                ? null
                : Border.all(
                    color: AppColors.red.withValues(alpha: 0.6), width: 1.2),
            boxShadow: filled
                ? [
                    BoxShadow(
                      color: AppColors.red.withValues(alpha: 0.4),
                      blurRadius: 24, offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                color: filled ? Colors.white : AppColors.red, size: 20),
              const SizedBox(width: 10),
              Text(label,
                style: GoogleFonts.inter(
                  color: filled ? Colors.white : AppColors.red,
                  fontSize: 13.5, letterSpacing: 2.6,
                  fontWeight: FontWeight.w900,
                )),
            ],
          ),
        ),
      ),
    );
  }
}

class _TextInput extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  const _TextInput({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surface3, width: 0.6),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        maxLines: 4,
        minLines: 3,
        maxLength: 420,
        cursorColor: AppColors.red,
        style: GoogleFonts.inter(
          color: AppColors.textPrimary,
          fontSize: 16, height: 1.45,
          fontWeight: FontWeight.w500,
          fontStyle: FontStyle.italic,
        ),
        decoration: InputDecoration(
          hintText: 'What did she say?',
          hintStyle: GoogleFonts.inter(
            color: AppColors.textTertiary,
            fontSize: 16, height: 1.45,
            fontWeight: FontWeight.w400,
            fontStyle: FontStyle.italic,
          ),
          counterText: '',
          border:           InputBorder.none,
          enabledBorder:    InputBorder.none,
          focusedBorder:    InputBorder.none,
          contentPadding:   EdgeInsets.zero,
          isDense:          true,
        ),
      ),
    );
  }
}

class _GenerateButton extends StatelessWidget {
  final bool enabled;
  final bool generating;
  final VoidCallback onTap;
  const _GenerateButton({
    required this.enabled,
    required this.generating,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? AppColors.red : AppColors.surface3,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          alignment: Alignment.center,
          child: generating
              ? const SizedBox(
                  width: 22, height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4, color: Colors.white))
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.bolt_rounded,
                      color: enabled
                          ? Colors.white
                          : AppColors.textTertiary,
                      size: 22),
                    const SizedBox(width: 8),
                    Text('GENERATE',
                      style: GoogleFonts.inter(
                        color: enabled
                            ? Colors.white
                            : AppColors.textTertiary,
                        fontSize: 14, letterSpacing: 2.8,
                        fontWeight: FontWeight.w900,
                      )),
                  ],
                ),
        ),
      ),
    );
  }
}

class _GimmeMoreButton extends StatelessWidget {
  final bool generating;
  final VoidCallback onTap;
  const _GimmeMoreButton({
    required this.generating,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.red,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: generating ? null : onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            boxShadow: [
              BoxShadow(
                color: AppColors.red.withValues(alpha: 0.4),
                blurRadius: 24, offset: const Offset(0, 6),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: generating
              ? const SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.refresh_rounded,
                        color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Text('GIMME MORE',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 14, letterSpacing: 2.8,
                        fontWeight: FontWeight.w900,
                      )),
                  ],
                ),
        ),
      ),
    );
  }
}

/// iMessage-style result bubble — right-aligned red, with a small
/// footer pair "SAFEST · MOVE LABEL" beneath each.
class _ReplyBubble extends StatelessWidget {
  final RizzReply reply;
  final int safeness;
  final VoidCallback onTap;
  const _ReplyBubble({
    required this.reply,
    required this.safeness,
    required this.onTap,
  });

  String get _safenessLabel => switch (safeness) {
        0 => 'SAFEST',
        1 => 'MIDDLE',
        _ => 'BOLDEST',
      };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.82,
            ),
            // Stack the bubble + a clear copy chip pinned to its
            // bottom-right corner. The bubble itself is tappable
            // (via the outer GestureDetector) so the user can copy
            // either by tapping anywhere or by tapping the chip.
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  decoration: BoxDecoration(
                    color: AppColors.red,
                    borderRadius: const BorderRadius.only(
                      topLeft:     Radius.circular(20),
                      topRight:    Radius.circular(20),
                      bottomLeft:  Radius.circular(20),
                      bottomRight: Radius.circular(4),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.red.withValues(alpha: 0.28),
                        blurRadius: 18, spreadRadius: 0,
                      ),
                    ],
                  ),
                  child: SelectableText(reply.text,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 15.5, height: 1.35,
                      fontWeight: FontWeight.w600,
                    )),
                ),
                Positioned(
                  right: 8, bottom: 6,
                  child: GestureDetector(
                    onTap: onTap,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.copy_rounded,
                            size: 11,
                            color: Colors.white.withValues(alpha: 0.95)),
                          const SizedBox(width: 4),
                          Text('COPY',
                            style: GoogleFonts.inter(
                              color: Colors.white.withValues(alpha: 0.95),
                              fontSize: 9, letterSpacing: 1.6,
                              fontWeight: FontWeight.w800,
                            )),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_safenessLabel,
                  style: GoogleFonts.inter(
                    color: AppColors.textTertiary,
                    fontSize: 10, letterSpacing: 2.4,
                    fontWeight: FontWeight.w800,
                  )),
                Text(' · ',
                  style: TextStyle(color: AppColors.textTertiary)),
                Text(reply.tag,
                  style: GoogleFonts.inter(
                    color: AppColors.red,
                    fontSize: 10, letterSpacing: 2.0,
                    fontWeight: FontWeight.w800,
                  )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  TONE PILL + PICKER + SCENARIO STRIP
//
//  Matches the WingAI-style 2026 rizz UX bro flagged. The pill sits
//  at the bottom of the results scroll showing the active tone (e.g.
//  "😏 Flirty"); tapping it opens the bottom-sheet picker. The
//  scenario strip is the row of "Tease a bit / Turn up heat / Plan
//  a date / Win her back" chips that bias the next generation —
//  one-shot, cleared the moment the request fires.
// ═══════════════════════════════════════════════════════════════════════

class _TonePill extends StatelessWidget {
  final RizzVibe tone;
  final VoidCallback? onTap;
  const _TonePill({required this.tone, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(100),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: AppColors.red.withValues(alpha: 0.55), width: 0.9),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tone.emoji,
                style: const TextStyle(fontSize: 15, height: 1)),
              const SizedBox(width: 8),
              Text(tone.label,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 13.5, height: 1,
                  letterSpacing: 0.4,
                  fontWeight: FontWeight.w800,
                )),
              const SizedBox(width: 6),
              const Icon(Icons.keyboard_arrow_down_rounded,
                color: AppColors.textSecondary, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom-sheet picker — one row per canonical tone. The active tone
/// is highlighted with a red border + filled radio. Tap any row to
/// pop with that vibe; the caller fires a fresh _generate so the
/// replies refresh into the new tone.
class _TonePickerSheet extends StatelessWidget {
  final RizzVibe current;
  const _TonePickerSheet({required this.current});

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    return Container(
      // Cap the sheet at 78% of the viewport so the inner scroll
      // can always reach the last row + the bottom safe-area padding.
      constraints: BoxConstraints(maxHeight: screenH * 0.78),
      decoration: const BoxDecoration(
        color: Color(0xFF111111),
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 38, height: 4,
              decoration: BoxDecoration(
                color: AppColors.surface3,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text('SELECT TONE',
                    style: GoogleFonts.inter(
                      color: AppColors.red,
                      fontSize: 12, letterSpacing: 3.0,
                      fontWeight: FontWeight.w800,
                    )),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                      color: AppColors.textSecondary, size: 22),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            // Rows scroll inside the bounded box — guarantees the
            // 5th row (Sincere) is always reachable on small phones.
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final v in RizzVibeLabel.canonical) ...[
                      _TonePickerRow(
                        tone:     v,
                        selected: v == current,
                        onTap:    () => Navigator.of(context).pop(v),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TonePickerRow extends StatelessWidget {
  final RizzVibe     tone;
  final bool         selected;
  final VoidCallback onTap;
  const _TonePickerRow({
    required this.tone,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final border = selected
        ? AppColors.red
        : AppColors.surface3;
    return Material(
      color: selected
          ? AppColors.red.withValues(alpha: 0.10)
          : AppColors.surface1,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border, width: selected ? 1.2 : 0.6),
          ),
          child: Row(
            children: [
              Text(tone.emoji,
                style: const TextStyle(fontSize: 22, height: 1)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tone.label,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 16, height: 1.2,
                        letterSpacing: -0.2,
                        fontWeight: FontWeight.w900,
                      )),
                    const SizedBox(height: 3),
                    Text(tone.blurb,
                      style: GoogleFonts.inter(
                        color: AppColors.textSecondary,
                        fontSize: 12.5, height: 1.35,
                        fontWeight: FontWeight.w500,
                      )),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Filled circle for selected, ring for unselected.
              Container(
                width: 22, height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? AppColors.red : AppColors.textTertiary,
                    width: 1.6),
                ),
                alignment: Alignment.center,
                child: selected
                    ? Container(
                        width: 11, height: 11,
                        decoration: const BoxDecoration(
                          color: AppColors.red,
                          shape: BoxShape.circle,
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontal-scroll quick-action chips. Each chip rewrites the
/// three replies currently on screen in that flavor — the backend
/// switches into TRANSFORM MODE (keeps each idea, shifts the
/// register). Bro: "they take the already good rizz and add
/// something to make it like sexual flirty or very bold" — exactly
/// this surface.
class _ScenarioStrip extends StatelessWidget {
  final Future<void> Function(String scenario) onTap;
  final bool disabled;
  const _ScenarioStrip({required this.onTap, required this.disabled});

  static const _chips = <({String label, String emoji, String scenario})>[
    (label: 'More heat',     emoji: '🔥', scenario: 'turn up the heat — push every line one notch hotter, more cinematic, more suggestive. Keep the structure, raise the temperature.'),
    (label: 'Flirty tease',  emoji: '😏', scenario: 'flirty tease — push-pull, light needle. Cheeky but warm. Keeps the conversation moving.'),
    (label: 'Make a move',   emoji: '🎯', scenario: 'make a move — pivot each line toward a specific, confident date proposal without sounding pushy.'),
    (label: 'Funnier',       emoji: '😂', scenario: 'funnier — keep the situation, add comedy. Screenshot-to-group-chat funny. Self-aware over earnest.'),
    (label: 'Be playful',    emoji: '😜', scenario: 'be playful — light, cheeky, low-stakes. Drop the heavy moves.'),
    (label: 'Be bolder',     emoji: '⚡️', scenario: 'be bolder — high-agency, declarative, scarce. Frame the outcome as already decided.'),
    (label: 'Sexier',        emoji: '💋', scenario: 'sexier — slow-burn sensual, suggestive without spilling. Eye-contact energy. Use a 😏 or 😮‍💨 at the end of a clause.'),
    (label: 'Keep it light', emoji: '🟡', scenario: 'keep it light and easy — no heavy moves, low-stakes charm. Friendly with a hint of flirt.'),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: _chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final c = _chips[i];
          return Material(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(100),
            child: InkWell(
              onTap: disabled ? null : () => onTap(c.scenario),
              borderRadius: BorderRadius.circular(100),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                    color: AppColors.surface3, width: 0.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(c.emoji,
                      style: const TextStyle(fontSize: 14, height: 1)),
                    const SizedBox(width: 7),
                    Text(c.label,
                      style: GoogleFonts.inter(
                        color: disabled
                            ? AppColors.textTertiary
                            : Colors.white,
                        fontSize: 13, height: 1,
                        letterSpacing: 0.1,
                        fontWeight: FontWeight.w700,
                      )),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Small red pulsing dot that sits beside the wordmark in the
/// share-extension header. Same visual cue we use on the Progress
/// page heading — "this is live, working, on your case right now".
class _BrandHeartbeatDot extends StatefulWidget {
  const _BrandHeartbeatDot();

  @override
  State<_BrandHeartbeatDot> createState() => _BrandHeartbeatDotState();
}

class _BrandHeartbeatDotState extends State<_BrandHeartbeatDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctl,
      builder: (_, __) {
        final v = Curves.easeInOut.transform(_ctl.value);
        return Container(
          width: 8, height: 8,
          margin: const EdgeInsets.only(top: 6),
          decoration: BoxDecoration(
            color: AppColors.red,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.red.withValues(alpha: 0.35 + 0.35 * v),
                blurRadius: 8 + 8 * v,
                spreadRadius: 0.5 + v,
              ),
            ],
          ),
        );
      },
    );
  }
}
