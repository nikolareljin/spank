import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';

void main() {
  group('Detector', () {
    test('ignores idle noise', () {
      final detector = Detector(
        threshold: 1.5,
        cooldown: const Duration(seconds: 1),
      );
      final now = DateTime(2026, 1, 1);
      final samples = <MotionSample>[
        MotionSample(timestamp: now, x: 0, y: 0, z: 1),
        MotionSample(
          timestamp: now.add(const Duration(milliseconds: 40)),
          x: 0.02,
          y: 0.01,
          z: 1.01,
        ),
        MotionSample(
          timestamp: now.add(const Duration(milliseconds: 80)),
          x: 0.01,
          y: -0.01,
          z: 0.99,
        ),
      ];

      for (final sample in samples) {
        expect(detector.process(sample), isNull);
      }
    });

    test('triggers on sharp motion', () {
      final detector = Detector(
        threshold: 1,
        cooldown: const Duration(seconds: 1),
      );
      final now = DateTime(2026, 1, 1);
      expect(
        detector.process(MotionSample(timestamp: now, x: 0, y: 0, z: 1)),
        isNull,
      );

      final event = detector.process(
        MotionSample(
          timestamp: now.add(const Duration(milliseconds: 50)),
          x: 2.5,
          y: 0,
          z: 0.2,
        ),
      );

      expect(event, isNotNull);
      expect(event!.severity, greaterThan(1));
    });

    test('suppresses repeated hits during cooldown', () {
      final detector = Detector(
        threshold: 0.8,
        cooldown: const Duration(milliseconds: 500),
      );
      final now = DateTime(2026, 1, 1);
      detector.process(MotionSample(timestamp: now, x: 0, y: 0, z: 1));

      final first = detector.process(
        MotionSample(
          timestamp: now.add(const Duration(milliseconds: 10)),
          x: 3,
          y: 0,
          z: 0,
        ),
      );
      final second = detector.process(
        MotionSample(
          timestamp: now.add(const Duration(milliseconds: 100)),
          x: 3,
          y: 0,
          z: 0,
        ),
      );

      expect(first, isNotNull);
      expect(second, isNull);
    });
  });

  test('settings round-trip keeps persisted values', () {
    final settings = SpankSettings.defaults().copyWith(
      threshold: 1.2,
      sampleIntervalMs: 32,
      cooldownMs: 900,
      soundPack: 'halo',
      volume: 0.4,
      dryRun: true,
    );

    final restored = SpankSettings.fromMap(settings.toMap());
    expect(restored.threshold, settings.threshold);
    expect(restored.sampleIntervalMs, settings.sampleIntervalMs);
    expect(restored.cooldownMs, settings.cooldownMs);
    expect(restored.soundPack, settings.soundPack);
    expect(restored.volume, settings.volume);
    expect(restored.dryRun, settings.dryRun);
  });
}
