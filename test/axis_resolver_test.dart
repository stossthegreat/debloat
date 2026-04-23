import 'package:flutter_test/flutter_test.dart';
import 'package:mirror/models/face_geometry.dart';
import 'package:mirror/services/protocol_service.dart';

/// Verifies [ProtocolService.resolveAxis] against realistic backend
/// pulldown prose + geometry snapshots. This is the contract between the
/// backend's prose output and our protocol template library — if this
/// drifts, users get the wrong protocol.

void main() {
  group('axis resolver — keyword match on prose', () {
    test('midface softness → falls through to geometry fallback', () {
      // Example pulldown from analyse.js comment: "midface softness that
      // body-fat below 14% solves". No direct axis keyword — should fall
      // to geometry. With balanced geometry → Foundations.
      expect(
        ProtocolService.resolveAxis(
          pulldown: 'midface softness that body-fat below 14% solves in six weeks',
          geometry: _balanced(),
        ),
        'Foundations',
      );
    });

    test('"long forehead" prose + geometry balanced → Foundations', () {
      expect(
        ProtocolService.resolveAxis(
          pulldown: 'a long forehead drags the upper third out of balance',
          geometry: _balanced(),
        ),
        'Foundations',
      );
    });

    test('"jaw angle 124°, soft" → Jaw definition', () {
      expect(
        ProtocolService.resolveAxis(
          pulldown: 'jaw angle 124° reads soft — fightable with body-fat and masseter',
          geometry: _balanced(),
        ),
        'Jaw definition',
      );
    });

    test('"chin projection" prose → Chin (chin checked before jaw)', () {
      expect(
        ProtocolService.resolveAxis(
          pulldown: 'chin projection is weak — mental eminence recessed',
          geometry: _balanced(),
        ),
        'Chin projection',
      );
    });

    test('"canthal tilt" prose → Hunter Eyes', () {
      expect(
        ProtocolService.resolveAxis(
          pulldown: 'negative canthal tilt is dragging the whole read',
          geometry: _balanced(),
        ),
        'Hunter Eyes',
      );
    });

    test('"hooded eyes" prose → Hunter Eyes (extended keyword)', () {
      expect(
        ProtocolService.resolveAxis(
          pulldown: 'hooded eyes mask the upper lid exposure',
          geometry: _balanced(),
        ),
        'Hunter Eyes',
      );
    });

    test('"skin texture" prose → Skin', () {
      expect(
        ProtocolService.resolveAxis(
          pulldown: 'skin texture is the bottleneck — everything else reads elite',
          geometry: _balanced(),
        ),
        'Skin',
      );
    });

    test('"receding hairline" prose → Hair', () {
      expect(
        ProtocolService.resolveAxis(
          pulldown: 'the receding hairline is fightable with minoxidil + dermaroll',
          geometry: _balanced(),
        ),
        'Hair',
      );
    });

    test('"puffy face" prose → Puffiness', () {
      expect(
        ProtocolService.resolveAxis(
          pulldown: 'puffy face reads soft — sodium and alcohol audit',
          geometry: _balanced(),
        ),
        'Puffiness',
      );
    });

    test('"neck forward" prose → Posture', () {
      expect(
        ProtocolService.resolveAxis(
          pulldown: 'neck forward posture is dragging the jaw line down',
          geometry: _balanced(),
        ),
        'Posture',
      );
    });
  });

  group('axis resolver — geometry fallback when prose misses', () {
    test('no keyword + soft jaw → Jaw definition', () {
      expect(
        ProtocolService.resolveAxis(
          pulldown: 'something vague and structural',
          geometry: _balanced()._copy(jawAngle: 132),
        ),
        'Jaw definition',
      );
    });

    test('no keyword + neutral canthal → Hunter Eyes', () {
      expect(
        ProtocolService.resolveAxis(
          pulldown: 'something vague and structural',
          geometry: _balanced()._copy(canthalTilt: 0.5),
        ),
        'Hunter Eyes',
      );
    });

    test('no keyword + low symmetry → Symmetry', () {
      expect(
        ProtocolService.resolveAxis(
          pulldown: 'something vague and structural',
          geometry: _balanced()._copy(symmetryScore: 72),
        ),
        'Symmetry',
      );
    });

    test('no keyword + balanced geometry → Foundations', () {
      expect(
        ProtocolService.resolveAxis(
          pulldown: 'something vague and structural',
          geometry: _balanced(),
        ),
        'Foundations',
      );
    });

    test('empty pulldown + balanced geometry → Foundations (safe default)', () {
      expect(
        ProtocolService.resolveAxis(
          pulldown: '',
          geometry: _balanced(),
        ),
        'Foundations',
      );
    });
  });
}

// Balanced reference — inside tolerance on every axis so geometry
// fallback only fires when explicitly perturbed.
FaceGeometry _balanced() => const FaceGeometry(
  canthalTilt: 3.5, symmetryScore: 85, facialThirdTop: 33,
  facialThirdMid: 33, facialThirdLow: 34, fwhr: 1.95, eyeSpacingRatio: 0.46,
  jawAngle: 118, chinProjection: 0.5, hasReliableData: true,
  faceLengthRatio: 1.30,
);

extension _FG on FaceGeometry {
  FaceGeometry _copy({
    double? canthalTilt, double? symmetryScore, double? jawAngle,
    double? fwhr, double? faceLengthRatio,
  }) => FaceGeometry(
    canthalTilt:    canthalTilt ?? this.canthalTilt,
    symmetryScore:  symmetryScore ?? this.symmetryScore,
    facialThirdTop: facialThirdTop,
    facialThirdMid: facialThirdMid,
    facialThirdLow: facialThirdLow,
    fwhr:           fwhr ?? this.fwhr,
    eyeSpacingRatio: eyeSpacingRatio,
    jawAngle:       jawAngle ?? this.jawAngle,
    chinProjection: chinProjection,
    hasReliableData: hasReliableData,
    faceLengthRatio: faceLengthRatio ?? this.faceLengthRatio,
    noseLengthRatio: noseLengthRatio,
    lipFullness:    lipFullness,
    brow2EyeGap:    brow2EyeGap,
    philtrumRatio:  philtrumRatio,
    interpupillaryRatio: interpupillaryRatio,
    headShape:      headShape,
  );
}
