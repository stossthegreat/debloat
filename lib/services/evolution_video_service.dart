import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// EVOLUTION VIDEO — builds the real, branded MP4 share clip for the
/// Face Evolution card. The GIF pipeline kept failing in the wild, so
/// this renders every frame in Dart (full branding, chips, glow
/// divider) and streams raw RGBA frames over a MethodChannel to a
/// native H.264 encoder (AVAssetWriter on iOS, MediaCodec+MediaMuxer
/// on Android). Output: a 720×1280 portrait MP4 that plays everywhere
/// a video plays — iMessage, IG stories, TikTok, WhatsApp.
///
/// Clip storyboard (~4.5s @ 24fps):
///   0.0–0.7s  hold on DAY 1 (the bloated before)
///   0.7–2.5s  glowing divider sweeps left→right revealing the drained
///             face underneath
///   2.5–4.5s  hold on the after; the "+N DRAINED SCORE" pill pops in
///
/// Returns the MP4 path, or null on ANY failure so callers can fall
/// back to the GIF/JPG share paths.
class EvolutionVideoService {
  static const _ch = MethodChannel('com.debloatos.app/video');

  static const int _w = 720;
  static const int _h = 1280;
  static const int _fps = 24;

  // Frame counts per storyboard phase.
  static const int _holdStart = 17; // ~0.7s
  static const int _sweep     = 43; // ~1.8s
  static const int _holdEnd   = 48; // ~2.0s

  // Brand palette (mirrors AppColors — kept literal so the renderer
  // has zero widget-layer dependencies).
  static const _base   = Color(0xFF05090B);
  static const _brand  = Color(0xFF22D3EE);
  static const _dim    = Color(0xFF0E7490);
  static const _green  = Color(0xFF4ADE80);
  static const _grey   = Color(0xFF9BA6AC);
  static const _panelR = 34.0;

  /// Renders + encodes the clip. Never throws — null means "use the
  /// fallback share path".
  static Future<String?> buildRevealVideo({
    required String beforePath,
    required String afterPath,
    required String dayLabel,     // e.g. 'DAY 14' / 'TODAY'
    required int scoreBefore,     // drained score at Day 1
    required int scoreAfter,      // drained score at the selected scan
  }) async {
    ui.Image? before;
    ui.Image? after;
    var started = false;
    try {
      before = await _loadImage(beforePath);
      after  = await _loadImage(afterPath);
      if (before == null || after == null) return null;

      final dir = await getTemporaryDirectory();
      final out =
          '${dir.path}/evolution_${DateTime.now().millisecondsSinceEpoch}.mp4';

      await _ch.invokeMethod('start', {
        'width': _w, 'height': _h, 'fps': _fps, 'path': out,
      });
      started = true;

      const total = _holdStart + _sweep + _holdEnd;
      for (var i = 0; i < total; i++) {
        // Reveal position 0..1 across the sweep phase.
        double t;
        if (i < _holdStart) {
          t = 0;
        } else if (i < _holdStart + _sweep) {
          t = Curves.easeInOutCubic
              .transform((i - _holdStart) / (_sweep - 1));
        } else {
          t = 1;
        }
        // End-card pop 0..1 over the first ~0.5s of the final hold.
        final pop = i < _holdStart + _sweep
            ? 0.0
            : Curves.easeOutBack.transform(
                ((i - _holdStart - _sweep) / 12).clamp(0.0, 1.0));

        final bytes = await _renderFrame(
          before: before, after: after, t: t, pop: pop,
          dayLabel: dayLabel,
          scoreBefore: scoreBefore, scoreAfter: scoreAfter,
        );
        // Await each frame — natural backpressure into the encoder.
        await _ch.invokeMethod('frame', bytes);
      }

      final path = await _ch.invokeMethod<String>('finish');
      started = false;
      if (path == null || !File(path).existsSync()) return null;
      return path;
    } catch (_) {
      if (started) {
        try { await _ch.invokeMethod('abort'); } catch (_) {}
      }
      return null;
    } finally {
      before?.dispose();
      after?.dispose();
    }
  }

  /// Decode a photo off disk, downscaled near the panel size so frame
  /// drawing stays cheap.
  static Future<ui.Image?> _loadImage(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final codec =
          await ui.instantiateImageCodec(bytes, targetHeight: 1000);
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  // ─── Frame renderer ──────────────────────────────────────────────

  static Future<Uint8List> _renderFrame({
    required ui.Image before,
    required ui.Image after,
    required double t,
    required double pop,
    required String dayLabel,
    required int scoreBefore,
    required int scoreAfter,
  }) async {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final full = Rect.fromLTWH(0, 0, _w.toDouble(), _h.toDouble());

    // Background — base black with a soft brand glow up top.
    c.drawRect(full, Paint()..color = _base);
    c.drawRect(full, Paint()
      ..shader = ui.Gradient.radial(
        const Offset(_w / 2, 140), 620,
        [_brand.withValues(alpha: 0.14), _brand.withValues(alpha: 0.0)],
      ));

    // Wordmark: DEBLOAT OS + FACE EVOLUTION.
    _text(c, 'DEBLOAT ', const Offset(_w / 2 - 4, 86),
        size: 58, weight: FontWeight.w800, color: Colors.white,
        anchor: _Anchor.right, spacing: -1.5);
    _text(c, 'OS', const Offset(_w / 2 - 4, 86),
        size: 58, weight: FontWeight.w800, color: _brand,
        anchor: _Anchor.left, spacing: -1.5);
    _text(c, 'FACE EVOLUTION', const Offset(_w / 2, 164),
        size: 21, weight: FontWeight.w800, color: _brand,
        anchor: _Anchor.center, spacing: 7);

    // Photo panel — 640×853 (3:4), rounded, hairline brand border.
    const panel = Rect.fromLTWH(40, 218, 640, 853);
    final rr = RRect.fromRectAndRadius(panel, const Radius.circular(_panelR));
    c.save();
    c.clipRRect(rr);
    _drawCover(c, before, panel);
    // AFTER revealed left→right.
    final revealW = panel.width * t;
    if (revealW > 0.5) {
      c.save();
      c.clipRect(Rect.fromLTWH(panel.left, panel.top, revealW, panel.height));
      _drawCover(c, after, panel);
      c.restore();
    }
    // Divider beam while sweeping.
    if (t > 0.001 && t < 0.999) {
      final x = panel.left + revealW;
      c.drawRect(
        Rect.fromLTWH(x - 22, panel.top, 22, panel.height),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(x - 22, 0), Offset(x, 0),
            [_brand.withValues(alpha: 0.0), _brand.withValues(alpha: 0.35)],
          ));
      c.drawRect(
        Rect.fromLTWH(x - 2, panel.top, 4, panel.height),
        Paint()
          ..color = Colors.white
          ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 3));
    }
    c.restore();
    c.drawRRect(rr, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = _brand.withValues(alpha: 0.5));

    // Corner chips — DAY 1 left (dims as it's wiped), day label right
    // (ignites as the reveal lands).
    _chip(c, 'DAY 1', const Offset(64, 244),
        fg: Colors.white.withValues(alpha: 1 - 0.65 * t),
        bg: Colors.black.withValues(alpha: 0.55));
    _chip(c, dayLabel, const Offset(_w - 64, 244),
        fg: Color.lerp(Colors.white70, _brand, t)!,
        bg: Colors.black.withValues(alpha: 0.55),
        anchor: _Anchor.right);

    // End card — delta pill pops under the panel, tagline beneath.
    // easeOutBack overshoots past 1.0, so alpha uses the clamped value
    // and only the scale keeps the bounce.
    final popA = pop.clamp(0.0, 1.0);
    final delta = scoreAfter - scoreBefore;
    final pillLabel = delta > 0
        ? '+$delta DRAINED SCORE'
        : 'DRAINED SCORE $scoreAfter';
    if (pop > 0.01) {
      c.save();
      c.translate(_w / 2, 1136);
      c.scale(0.6 + 0.4 * pop);
      _pill(c, pillLabel, Offset.zero,
          fg: const Color(0xFF03181C),
          bg: delta > 0 ? _green : _brand,
          alpha: popA);
      c.restore();
    }
    _text(c, 'Find the face under the bloat.',
        const Offset(_w / 2, 1210),
        size: 23, weight: FontWeight.w600,
        color: _grey.withValues(alpha: 0.55 + 0.45 * popA),
        anchor: _Anchor.center);

    final picture = rec.endRecording();
    final img = await picture.toImage(_w, _h);
    picture.dispose();
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    img.dispose();
    return data!.buffer.asUint8List();
  }

  /// Cover-fit draw of [img] into [dst] (centre-crop, slight upward bias
  /// so faces sit high like the in-app card).
  static void _drawCover(Canvas c, ui.Image img, Rect dst) {
    final iw = img.width.toDouble(), ih = img.height.toDouble();
    final scale = (dst.width / iw) > (dst.height / ih)
        ? dst.width / iw
        : dst.height / ih;
    final sw = dst.width / scale, sh = dst.height / scale;
    final sx = (iw - sw) / 2;
    final sy = ((ih - sh) / 2 * 0.7).clamp(0.0, ih - sh); // bias up
    c.drawImageRect(
      img,
      Rect.fromLTWH(sx, sy, sw, sh),
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  static void _chip(Canvas c, String label, Offset at,
      {required Color fg, required Color bg, _Anchor anchor = _Anchor.left}) {
    final tp = _painter(label, 20, FontWeight.w800, fg, 2.2);
    const padX = 18.0, padY = 10.0;
    final w = tp.width + padX * 2, h = tp.height + padY * 2;
    final left = switch (anchor) {
      _Anchor.left => at.dx,
      _Anchor.right => at.dx - w,
      _Anchor.center => at.dx - w / 2,
    };
    final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, at.dy, w, h), Radius.circular(h / 2));
    c.drawRRect(rect, Paint()..color = bg);
    tp.paint(c, Offset(left + padX, at.dy + padY));
  }

  static void _pill(Canvas c, String label, Offset centre,
      {required Color fg, required Color bg, required double alpha}) {
    final tp = _painter(label, 26, FontWeight.w900, fg.withValues(alpha: alpha), 1.6);
    const padX = 30.0, padY = 16.0;
    final w = tp.width + padX * 2, h = tp.height + padY * 2;
    final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: centre, width: w, height: h),
        Radius.circular(h / 2));
    c.drawRRect(rect, Paint()
      ..color = bg.withValues(alpha: 0.35 * alpha)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18));
    c.drawRRect(rect, Paint()..color = bg.withValues(alpha: alpha));
    tp.paint(c, Offset(centre.dx - tp.width / 2, centre.dy - tp.height / 2));
  }

  static void _text(Canvas c, String s, Offset at,
      {required double size,
      required FontWeight weight,
      required Color color,
      _Anchor anchor = _Anchor.left,
      double spacing = 0}) {
    final tp = _painter(s, size, weight, color, spacing);
    final dx = switch (anchor) {
      _Anchor.left => at.dx,
      _Anchor.right => at.dx - tp.width,
      _Anchor.center => at.dx - tp.width / 2,
    };
    tp.paint(c, Offset(dx, at.dy));
  }

  static TextPainter _painter(
      String s, double size, FontWeight w, Color color, double spacing) {
    return TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          color: color, fontSize: size,
          fontWeight: w, letterSpacing: spacing,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }
}

enum _Anchor { left, right, center }
