import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../theme/app_colors.dart';
import '../widgets/common/share_card.dart';

/// Captures any widget via RepaintBoundary + exports a PNG + opens the
/// system share sheet. Supports:
/// - Simple repaint-boundary share (widget already on screen)
/// - Off-screen ShareCard render (composed just for sharing, never shown)
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
      await _shareBytes(byteData.buffer.asUint8List(), suggestedName, text);
    } catch (_) {}
  }

  /// Render the viral ShareCard off-screen at 1080×1920, capture as PNG,
  /// open share sheet. The card is pure composition — never appears in UI.
  ///
  /// Format is locked to:
  ///   "X CORRECTIONS. SAME FACE." → before/after → 3 micro-proofs → footer.
  /// No score, no archetype, no percentile pills — those are report-screen
  /// concerns. Share format optimises for shareability, not completeness.
  static Future<void> shareComposed({
    required BuildContext context,
    required Uint8List? beforeBytes,
    required String? afterUrl,
    required int correctionsCount,
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

    String? errorMsg;
    try {
      if (!context.mounted) return;
      final card = ShareCard(
        beforeBytes:      beforeBytes,
        afterUrl:         afterUrl,
        correctionsCount: correctionsCount,
        microProofs:      microProofs,
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

  static Future<void> _shareBytes(
      Uint8List bytes, String name, String? text) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'image/png')],
      text: text,
    );
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
            child: ColoredBox(color: AppColors.base, child: widget),
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
            color: AppColors.gold.withValues(alpha: 0.35), width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            SizedBox(width: 22, height: 22,
              child: CircularProgressIndicator(
                color: AppColors.gold, strokeWidth: 2)),
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
