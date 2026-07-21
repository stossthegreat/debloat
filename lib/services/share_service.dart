import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'face_asset_service.dart';
import '../theme/app_colors.dart';
import '../widgets/common/share_card.dart';
import '../widgets/share/body_share_card.dart';
import '../widgets/share/certificate_share_card.dart';
import '../widgets/share/eye_strip_share_card.dart';
import '../widgets/share/progress_share_card.dart';
import '../widgets/share/score_share_card.dart';

/// Captures any widget via RepaintBoundary + exports a PNG + opens the
/// system share sheet. Supports:
/// - Simple repaint-boundary share (widget already on screen)
/// - Off-screen ShareCard render (composed just for sharing, never shown)
/// - Auralay eye-strip card (Eyes tab — gaze sessions)
/// - Auralay score card (Game tab — Free Flow + Eyes scores)
class ShareService {
  /// Screenshot an existing widget wrapped in RepaintBoundary via GlobalKey.
  static Future<void> shareFromKey(
    GlobalKey key, {
    String suggestedName = 'mirrorly.png',
    String? text,
  }) async {
    try {
      final boundary = key.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final origin = _sharePositionOriginFromKey(key);
      await _shareBytes(byteData.buffer.asUint8List(), suggestedName, text,
          origin: origin);
    } catch (_) {}
  }

  /// Render the ShareCard off-screen at 1080×1920, capture as PNG, open
  /// share sheet. The card never appears in UI — pure composition.
  ///
  /// Format is the 9:16 export of the in-app hero card: score transition
  /// on top (CURRENT → PROJECTED with red arrow), before/after with
  /// "ImHim Looks" overlaid on the NOW half, tagline, three proof lines,
  /// domain footer. Same visual language in-app and on socials.
  ///
  /// Pass currentScore / projectedScore = 0 from contexts that don't have
  /// scores (e.g. chat inline tryon); the card hides the score row and
  /// shows the brand wordmark at the top instead.
  static Future<void> shareComposed({
    required BuildContext context,
    required Uint8List? beforeBytes,
    required String? afterUrl,
    required int currentScore,
    required int projectedScore,
    required String tagline,
    required List<String> microProofs,
    String? text,
  }) async {
    HapticFeedback.lightImpact();

    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black54,
        builder: (_) => const _RenderingOverlay(),
      );
    }

    // Anchor for the iOS share sheet — REQUIRED on iPad (the system
    // pops the action sheet from a popover that needs a source rect),
    // and useful on iPhone too because under iOS 26's UIScene
    // lifecycle the legacy keyWindow lookup share_plus uses returns
    // a stale window and the sheet silently fails to present (the
    // bug the founder reported as "tap acts like it's doing
    // something but doesn't"). Anchor the popover to the top-centre
    // of the screen — invisible on iPhone, correctly placed on iPad.
    final mq = MediaQuery.of(context);
    final origin = Rect.fromLTWH(
      mq.size.width / 2 - 1, mq.padding.top + 8, 2, 2);

    String? errorMsg;
    try {
      if (!context.mounted) return;
      final card = ShareCard(
        beforeBytes:    beforeBytes,
        afterUrl:       afterUrl,
        currentScore:   currentScore,
        projectedScore: projectedScore,
        tagline:        tagline,
        microProofs:    microProofs,
      );
      final bytes = await _captureOffscreen(
        context:     context,
        widget:      card,
        logicalSize: const Size(1080, 1920),
        pixelRatio:  2.0,
      );
      if (bytes == null) {
        errorMsg = 'Couldn\'t render the card — try again';
      } else {
        if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
        HapticFeedback.mediumImpact();
        await _shareBytes(
          bytes,
          'mirrorly-${DateTime.now().millisecondsSinceEpoch}.png',
          text,
          origin: origin,
        );
        return;
      }
    } catch (e) {
      errorMsg = 'Share failed: ${e.toString().split('\n').first}';
    }

    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMsg),
          backgroundColor: AppColors.surface2,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Render + share the BODY transformation card — the face-scan share
  /// pipeline applied to the Body tab. 9:16 (1080×1920) off-screen
  /// composition, never shown in UI: wordmark + mission chip, quick
  /// NOW → POTENTIAL score row above the images, before/after pair as
  /// the hero, one hard line underneath, brand footer.
  ///
  /// BOTH panes take bytes — the caller pre-downloads the after render
  /// (the offscreen pipeline paints a single synchronous frame, so an
  /// async network image would export as an empty pane).
  static Future<void> shareBodyTransformation({
    required BuildContext context,
    required Uint8List beforeBytes,
    required Uint8List afterBytes,
    required int scoreNow,
    required int scorePotential,
    required String missionName,
    required String tagline,
    String? text,
  }) async {
    HapticFeedback.lightImpact();

    if (context.mounted) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black54,
        builder: (_) => const _RenderingOverlay(),
      );
    }

    final mq = MediaQuery.of(context);
    final origin = Rect.fromLTWH(
      mq.size.width / 2 - 1, mq.padding.top + 8, 2, 2);

    String errorMsg = 'Share failed';
    try {
      if (!context.mounted) return;
      final card = BodyShareCard(
        beforeBytes:    beforeBytes,
        afterBytes:     afterBytes,
        scoreNow:       scoreNow,
        scorePotential: scorePotential,
        missionName:    missionName,
        tagline:        tagline,
      );
      final bytes = await _captureOffscreen(
        context:     context,
        widget:      card,
        logicalSize: const Size(1080, 1920),
        pixelRatio:  2.0,
      );
      if (bytes == null) {
        errorMsg = "Couldn't render the card — try again";
      } else {
        if (context.mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
        HapticFeedback.mediumImpact();
        await _shareBytes(
          bytes,
          'imhim-body-${DateTime.now().millisecondsSinceEpoch}.png',
          text ?? '$scoreNow → $scorePotential. $tagline · ImHim Looks',
          origin: origin,
        );
        return;
      }
    } catch (e) {
      errorMsg = 'Share failed: ${e.toString().split('\n').first}';
    }

    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(errorMsg),
        backgroundColor: AppColors.surface2,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  //  Auralay-imported cards (Eyes + Game tabs)
  // ──────────────────────────────────────────────────────────────────────

  /// Render + share Auralay's eye-strip card. Used by the EYES tab after a
  /// gaze session (post_session_screen) and by the seduction/charisma test
  /// result-reveal screen. Composes at 1080×device-aspect, captures off
  /// screen, opens system share sheet. Same pipeline as [shareComposed].
  static Future<void> shareAuraResult({
    required BuildContext context,
    required Uint8List? photoBytes,
    required double? eyeYNormalized,
    required int score,
    required String tier,
    required String roast,
    required Map<String, double> dimensions,
    int sessionIndex = 1,
    String? techniqueName,
    String? text,
  }) async {
    HapticFeedback.lightImpact();

    if (context.mounted) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black54,
        builder: (_) => const _RenderingOverlay(),
      );
    }

    final mq = MediaQuery.of(context);
    final origin = Rect.fromLTWH(
      mq.size.width / 2 - 1, mq.padding.top + 8, 2, 2);

    String errorMsg = 'Share failed';
    try {
      if (!context.mounted) return;
      final card = EyeStripShareCard(
        photoBytes:     photoBytes,
        eyeYNormalized: eyeYNormalized,
        score:          score,
        tier:           tier,
        roast:          roast,
        dimensions:     dimensions,
        sessionIndex:   sessionIndex,
        techniqueName:  techniqueName,
      );
      final bytes = await _captureOffscreen(
        context:     context,
        widget:      card,
        logicalSize: _auralayCardSize(context),
        pixelRatio:  2.0,
      );
      if (bytes == null) {
        errorMsg = "Couldn't render the card — try again";
      } else {
        if (context.mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
        HapticFeedback.mediumImpact();
        await _shareBytes(
          bytes,
          'mirrorly-${DateTime.now().millisecondsSinceEpoch}.png',
          text,
          origin: origin,
        );
        return;
      }
    } catch (e) {
      errorMsg = 'Share failed: ${e.toString().split('\n').first}';
    }

    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(errorMsg),
        backgroundColor: AppColors.surface2,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  /// Render + share the universal Auralay score card (0–10). Used by The
  /// Gaze, Presence/Eye Contact+Voice, and Free Flow so every shared
  /// result is on-brand with a single visual language.
  static Future<void> shareScore({
    required BuildContext context,
    required String kindLabel,
    required String subLabel,
    required int score,
    required String badge,
    required String verdict,
    List<({String label, int score})> stats = const [],
    String? text,
  }) async {
    HapticFeedback.lightImpact();

    if (context.mounted) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black54,
        builder: (_) => const _RenderingOverlay(),
      );
    }

    final mq = MediaQuery.of(context);
    final origin = Rect.fromLTWH(
      mq.size.width / 2 - 1, mq.padding.top + 8, 2, 2);

    String errorMsg = 'Share failed';
    try {
      if (!context.mounted) return;
      final card = ScoreShareCard(
        kindLabel: kindLabel,
        subLabel:  subLabel,
        score:     score.clamp(0, 10).toInt(),
        badge:     badge,
        verdict:   verdict,
        stats:     stats,
      );
      final bytes = await _captureOffscreen(
        context:     context,
        widget:      card,
        logicalSize: _auralayCardSize(context),
        pixelRatio:  2.0,
      );
      if (bytes == null) {
        errorMsg = "Couldn't render the card — try again";
      } else {
        if (context.mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
        HapticFeedback.mediumImpact();
        await _shareBytes(
          bytes,
          'mirrorly-${DateTime.now().millisecondsSinceEpoch}.png',
          text ?? '$kindLabel · $score/10 on IMHIM LOOKS',
          origin: origin,
        );
        return;
      }
    } catch (e) {
      errorMsg = 'Share failed: ${e.toString().split('\n').first}';
    }

    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(errorMsg),
        backgroundColor: AppColors.surface2,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  /// Render + share the ImHim Looks PROGRESS receipt — DAY hero, streak,
  /// per-surface scores + deltas, total reps, brand wordmark + domain.
  /// Wired to /progress via the masthead SHARE button so the user can
  /// post a single "DAY 14 · STREAK 14 · +12 AESTHETIC" card the
  /// moment their numbers feel post-worthy. Pipeline identical to
  /// [shareScore].
  static Future<void> shareProgress({
    required BuildContext context,
    required int day,
    required int streakDays,
    required int scanCount,
    required int gameReps,
    required int drillsCount,
    int? aestheticNow,
    int? aestheticDelta,
    int? voiceNow,
    int? voiceDelta,
    int? auraNow,
    // v290 — IMHIM LOOKS SCORE hero. The composite that the share card now
    // leads with; Looks + Game demoted to "BUILT FROM" rows beneath.
    int? imhimNow,
    int? imhimDelta,
    String verdict = '',
    String? text,
    // Oldest + newest scan photos for the BEFORE/NOW pair on the card.
    String? beforePhotoPath,
    String? nowPhotoPath,
  }) async {
    HapticFeedback.lightImpact();

    if (context.mounted) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black54,
        builder: (_) => const _RenderingOverlay(),
      );
    }

    // Resolve through the container-UUID rescue (the raw stored path
    // goes stale after an app update), then warm the cache so the
    // BEFORE/NOW photos paint in the single off-screen layout pass.
    final beforeResolved = await FaceAssetService.resolvePath(beforePhotoPath);
    final nowResolved    = await FaceAssetService.resolvePath(nowPhotoPath);
    if (beforeResolved != null && context.mounted) {
      try {
        await precacheImage(FileImage(File(beforeResolved)), context);
      } catch (_) {}
    }
    if (nowResolved != null && context.mounted) {
      try {
        await precacheImage(FileImage(File(nowResolved)), context);
      } catch (_) {}
    }

    final mq = MediaQuery.of(context);
    final origin = Rect.fromLTWH(
      mq.size.width / 2 - 1, mq.padding.top + 8, 2, 2);

    String errorMsg = 'Share failed';
    try {
      if (!context.mounted) return;
      final card = ProgressShareCard(
        day:            day,
        streakDays:     streakDays,
        scanCount:      scanCount,
        gameReps:       gameReps,
        drillsCount:    drillsCount,
        aestheticNow:   aestheticNow,
        aestheticDelta: aestheticDelta,
        voiceNow:       voiceNow,
        voiceDelta:     voiceDelta,
        auraNow:        auraNow,
        imhimNow:       imhimNow,
        imhimDelta:     imhimDelta,
        verdict:        verdict,
        beforePhotoPath: beforeResolved,
        nowPhotoPath:    nowResolved,
      );
      final bytes = await _captureOffscreen(
        context:     context,
        widget:      card,
        logicalSize: _auralayCardSize(context),
        pixelRatio:  2.0,
      );
      if (bytes == null) {
        errorMsg = "Couldn't render the card — try again";
      } else {
        if (context.mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
        HapticFeedback.mediumImpact();
        // Default copy is post-ready: claim, receipt, app handle.
        final defaultText = streakDays > 0
            ? 'Day $day · streak $streakDays on ImHim Looks.'
            : 'Day $day on ImHim Looks.';
        await _shareBytes(
          bytes,
          'mirrorly-progress-${DateTime.now().millisecondsSinceEpoch}.png',
          text ?? defaultText,
          origin: origin,
        );
        return;
      }
    } catch (e) {
      errorMsg = 'Share failed: ${e.toString().split('\n').first}';
    }

    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(errorMsg),
        backgroundColor: AppColors.surface2,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  /// Render + share the v291 IMHIM CERTIFIED Day-60 card. Unlocked
  /// by [_FinalFormCard] in the Ascend tab once the user clears the
  /// 60-day protocol. Same off-screen render pipeline as
  /// [shareProgress] / [shareScore] so the share-sheet behaviour is
  /// identical across cards.
  static Future<void> shareCertificate({
    required BuildContext context,
    String? beforePhotoPath,
    String? afterPhotoPath,
    required int imhimStart,
    required int imhimEnd,
    required int looksStart,
    required int looksEnd,
    required int gameStart,
    required int gameEnd,
    required int consistencyStart,
    required int consistencyEnd,
    String verdict = '60 days. You\'re not the man who started this.',
    String? text,
  }) async {
    HapticFeedback.lightImpact();

    if (context.mounted) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black54,
        builder: (_) => const _RenderingOverlay(),
      );
    }

    // Resolve through the container-UUID rescue (raw path goes stale
    // after an app update), then warm the cache so the full-bleed
    // BEFORE/NOW faces paint in the single off-screen layout pass.
    final beforeResolved = await FaceAssetService.resolvePath(beforePhotoPath);
    final afterResolved  = await FaceAssetService.resolvePath(afterPhotoPath);
    if (beforeResolved != null && context.mounted) {
      try {
        await precacheImage(FileImage(File(beforeResolved)), context);
      } catch (_) {}
    }
    if (afterResolved != null && context.mounted) {
      try {
        await precacheImage(FileImage(File(afterResolved)), context);
      } catch (_) {}
    }

    final mq = MediaQuery.of(context);
    final origin = Rect.fromLTWH(
      mq.size.width / 2 - 1, mq.padding.top + 8, 2, 2);

    String errorMsg = 'Share failed';
    try {
      if (!context.mounted) return;
      final card = CertificateShareCard(
        beforePhotoPath:   beforeResolved,
        afterPhotoPath:    afterResolved,
        imhimStart:        imhimStart,
        imhimEnd:          imhimEnd,
        looksStart:        looksStart,
        looksEnd:          looksEnd,
        gameStart:         gameStart,
        gameEnd:           gameEnd,
        consistencyStart:  consistencyStart,
        consistencyEnd:    consistencyEnd,
        verdict:           verdict,
      );
      final bytes = await _captureOffscreen(
        context:     context,
        widget:      card,
        logicalSize: _auralayCardSize(context),
        pixelRatio:  2.0,
      );
      if (bytes == null) {
        errorMsg = "Couldn't render the certificate — try again";
      } else {
        if (context.mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
        HapticFeedback.heavyImpact();
        final defaultText =
          '60 days. ImHim Certified. ${imhimStart} → ${imhimEnd}.';
        await _shareBytes(
          bytes,
          'mirrorly-certified-${DateTime.now().millisecondsSinceEpoch}.png',
          text ?? defaultText,
          origin: origin,
        );
        return;
      }
    } catch (e) {
      errorMsg = 'Share failed: ${e.toString().split('\n').first}';
    }

    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(errorMsg),
        backgroundColor: AppColors.surface2,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  /// Auralay cards render at the device's portrait aspect — wider phones get
  /// taller cards. Width pinned at 1080 for crisp output.
  static Size _auralayCardSize(BuildContext context) {
    final s = MediaQuery.of(context).size;
    final aspect =
        (s.width <= 0 || s.height <= 0) ? 9 / 19.5 : s.width / s.height;
    const w = 1080.0;
    return Size(w, (w / aspect).clamp(1920.0, 2600.0));
  }

  static Future<void> _shareBytes(
      Uint8List bytes, String name, String? text,
      {Rect? origin}) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'image/png')],
      text: text,
      // Required for iPad popover; on iPhone share_plus 10.x under
      // iOS 26 UIScene also benefits from a valid origin because the
      // plugin's deprecated keyWindow lookup otherwise returns nil
      // and the sheet silently fails to present.
      sharePositionOrigin: origin,
    );
  }

  /// Best-effort source rect for the iOS share popover, derived from
  /// a widget's RepaintBoundary key. Falls back to null if the key's
  /// render object isn't yet attached — share_plus then computes a
  /// default which works on iPhone but not iPad.
  static Rect? _sharePositionOriginFromKey(GlobalKey key) {
    try {
      final ctx = key.currentContext;
      if (ctx == null) return null;
      final box = ctx.findRenderObject();
      if (box is! RenderBox) return null;
      final tl = box.localToGlobal(Offset.zero);
      return tl & box.size;
    } catch (_) {
      return null;
    }
  }

  /// Render any widget off-screen at an explicit logical size. Uses a
  /// MediaQuery + Theme + Directionality wrapper so text/fonts resolve.
  static Future<Uint8List?> _captureOffscreen({
    required BuildContext context,
    required Widget widget,
    required Size logicalSize,
    double pixelRatio = 3.0,
  }) async {
    final repaintBoundary = RenderRepaintBoundary();
    final renderView = RenderView(
      view: View.of(context),
      configuration: ViewConfiguration(
        logicalConstraints: BoxConstraints.tight(logicalSize),
        physicalConstraints: BoxConstraints.tight(logicalSize * pixelRatio),
        devicePixelRatio: pixelRatio,
      ),
      child: RenderPositionedBox(
        alignment: Alignment.center, child: repaintBoundary),
    );

    final pipelineOwner = PipelineOwner()..rootNode = renderView;
    final buildOwner = BuildOwner(focusManager: FocusManager());
    renderView.prepareInitialFrame();

    final rootElement = RenderObjectToWidgetAdapter<RenderBox>(
      container: repaintBoundary,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: MediaQueryData(size: logicalSize, devicePixelRatio: pixelRatio),
          child: Theme(
            data: Theme.of(context),
            // Pure black surface — NOT AppColors.base (#07070A). The share
            // card prints against true #000000 so the edges disappear into
            // whatever surface it's posted on.
            child: ColoredBox(color: Colors.black, child: widget),
          ),
        ),
      ),
    ).attachToRenderTree(buildOwner);

    buildOwner.buildScope(rootElement);
    buildOwner.finalizeTree();

    pipelineOwner.flushLayout();
    pipelineOwner.flushCompositingBits();
    pipelineOwner.flushPaint();

    final image = await repaintBoundary.toImage(pixelRatio: pixelRatio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }
}

/// Loading overlay shown while the ShareCard is being rendered. Gives the
/// user immediate feedback on the share button press (otherwise the 2-3s
/// render time reads as "button is broken").
class _RenderingOverlay extends StatelessWidget {
  const _RenderingOverlay();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: AppColors.red.withValues(alpha: 0.35), width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            SizedBox(width: 22, height: 22,
              child: CircularProgressIndicator(
                color: AppColors.red, strokeWidth: 2)),
            SizedBox(width: 16),
            Text('Composing your card…',
              style: TextStyle(
                color: Color(0xFFF7F7F9),
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2)),
          ],
        ),
      ),
    );
  }
}
