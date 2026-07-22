import 'package:flutter_test/flutter_test.dart';
import 'package:debloat_os/models/face_geometry.dart';
import 'package:debloat_os/services/protocol_service.dart';

/// Debloat OS runs exactly ONE protocol axis. The resolver's contract
/// is total: whatever prose the backend sends and whatever the geometry
/// looks like, the answer is the Debloat axis. These cases pin that
/// down against realistic pulldown prose so a future re-expansion of
/// the axis roster has to consciously rewrite this file.
void main() {
  group('axis resolver — everything lands on Debloat', () {
    const pulldowns = <String>[
      'midface softness that body-fat below 14% solves in six weeks',
      'a long forehead drags the upper third out of balance',
      'puffiness around the eyes and jawline from water retention',
      'jaw definition is blurred by submental fullness',
      'skin texture is uneven with visible pores',
      'hairline is beginning to recede at the temples',
      '',
    ];
    for (final p in pulldowns) {
      test('"${p.isEmpty ? '<empty>' : p}" resolves to Debloat', () {
        expect(
          ProtocolService.resolveAxis(pulldown: p, geometry: _balanced()),
          kDebloatAxis,
        );
      });
    }

    test('extreme geometry still resolves to Debloat', () {
      expect(
        ProtocolService.resolveAxis(
          pulldown: 'no keywords here',
          geometry: _balanced()._copy(jawAngle: 140, canthalTilt: -2),
        ),
        kDebloatAxis,
      );
    });
  });
}

FaceGeometry _balanced() => const FaceGeometry(
  canthalTilt: 3.5, symmetryScore: 85, facialThirdTop: 33,
  facialThirdMid: 33, facialThirdLow: 34, fwhr: 1.95, eyeSpacingRatio: 0.46,
  jawAngle: 118, chinProjection: 0.5, hasReliableData: true,
  faceLengthRatio: 1.30,
);

extension _FG on FaceGeometry {
  FaceGeometry _copy({
    double? canthalTilt, double? jawAngle,
  }) => FaceGeometry(
    canthalTilt:    canthalTilt ?? this.canthalTilt,
    symmetryScore:  symmetryScore,
    facialThirdTop: facialThirdTop,
    facialThirdMid: facialThirdMid,
    facialThirdLow: facialThirdLow,
    fwhr:           fwhr,
    eyeSpacingRatio: eyeSpacingRatio,
    jawAngle:       jawAngle ?? this.jawAngle,
    chinProjection: chinProjection,
    hasReliableData: hasReliableData,
    faceLengthRatio: faceLengthRatio,
    noseLengthRatio: noseLengthRatio,
    lipFullness:    lipFullness,
    brow2EyeGap:    brow2EyeGap,
    philtrumRatio:  philtrumRatio,
    interpupillaryRatio: interpupillaryRatio,
    headShape:      headShape,
  );
}
