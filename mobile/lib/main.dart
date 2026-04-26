import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SpankApp());
}

class SpankApp extends StatelessWidget {
  const SpankApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFD65A31),
      brightness: Brightness.light,
    );

    return MaterialApp(
      title: 'Spank Mobile',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFFF4E9DC),
        useMaterial3: true,
        textTheme: ThemeData.light().textTheme.apply(
          bodyColor: const Color(0xFF261C15),
          displayColor: const Color(0xFF261C15),
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final PlatformBridge _bridge = PlatformBridge();
  final Random _random = Random();

  late SpankSettings _settings;

  StreamSubscription<MotionSample>? _subscription;
  AudioCatalog _catalog = AudioCatalog.empty();
  MotionReading? _lastReading;
  DetectionEvent? _lastEvent;
  String _status = 'Loading assets and saved settings...';
  String? _error;
  bool _armed = false;
  bool _loading = true;
  bool _foregroundServiceActive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _settings = SpankSettings.defaults();
    unawaited(_initialize());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_stopMonitoring());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (Platform.isAndroid && _foregroundServiceActive) {
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      unawaited(_stopMonitoring(updateStatus: false));
    }
  }

  Future<void> _initialize() async {
    try {
      final results = await Future.wait<dynamic>([
        _bridge.loadSettings(),
        AudioCatalog.load(),
      ]);
      final stored = results[0] as SpankSettings;
      final catalog = results[1] as AudioCatalog;

      if (!mounted) {
        return;
      }

      setState(() {
        _settings = stored.withAvailableSound(catalog.availablePacks);
        _catalog = catalog;
        _loading = false;
        _status = 'Ready. Tap arm to start listening for impact.';
      });
    } catch (err) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = err.toString();
        _status = 'Initialization failed.';
      });
    }
  }

  Future<void> _toggleMonitoring() async {
    if (_armed) {
      await _stopMonitoring();
      return;
    }

    setState(() {
      _error = null;
      _status = 'Monitoring accelerometer input...';
      _lastEvent = null;
    });

    final detector = Detector(
      threshold: _settings.threshold,
      cooldown: Duration(milliseconds: _settings.cooldownMs),
    );

    try {
      final stream = _bridge.motionEvents(
        sampleIntervalMs: _settings.sampleIntervalMs,
      );
      final subscription = stream.listen(
        (sample) async {
          final event = detector.process(sample);
          if (!mounted) {
            return;
          }

          setState(() {
            _lastReading = MotionReading.from(sample, detector.baseline);
          });

          if (event == null) {
            return;
          }

          setState(() {
            _lastEvent = event;
            _status =
                'Impact detected: severity ${event.severity.toStringAsFixed(2)}';
          });

          if (_settings.dryRun) {
            return;
          }

          final asset = _catalog.randomAsset(_settings.soundPack, _random);
          if (asset == null) {
            setState(() {
              _error =
                  'No packaged audio assets found for ${_settings.soundPack}.';
            });
            return;
          }
          try {
            await _bridge.playAsset(
              asset,
              volume: _settings.volume,
              audioMode: _settings.callMode ? _settings.audioMode : null,
            );
          } catch (err) {
            if (!mounted) {
              return;
            }
            setState(() {
              _error = 'Audio playback failed: $err';
            });
          }
        },
        onError: (Object err) {
          if (!mounted) {
            return;
          }
          setState(() {
            _error = 'Sensor stream failed: $err';
            _status = 'Monitoring stopped because sensor access failed.';
          });
          unawaited(_stopMonitoring(updateStatus: false));
        },
        cancelOnError: true,
      );

      if (!mounted) {
        await subscription.cancel();
        return;
      }

      setState(() {
        _subscription = subscription;
        _armed = true;
      });

      if (_settings.callMode) {
        try {
          await _bridge.startForegroundService();
          _foregroundServiceActive = true;
        } catch (err) {
          if (mounted) {
            setState(() {
              _error =
                  'Background service unavailable: $err. Monitoring active in foreground only.';
            });
          }
        }
      }
    } catch (err) {
      await _stopMonitoring(updateStatus: false);
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Unable to start monitoring: $err';
        _status = 'Monitoring did not start.';
      });
    }
  }

  Future<void> _stopMonitoring({bool updateStatus = true}) async {
    await _subscription?.cancel();
    _subscription = null;
    if (_foregroundServiceActive) {
      try {
        await _bridge.stopForegroundService();
      } catch (err) {
        debugPrint('stopForegroundService failed: $err');
        if (mounted) {
          setState(() {
            _error = 'Failed to stop background service: $err';
          });
        }
      }
      _foregroundServiceActive = false;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _armed = false;
      if (updateStatus) {
        _status = 'Monitoring stopped.';
      }
    });
  }

  Future<void> _saveSettings(SpankSettings next) async {
    final normalized = next.withAvailableSound(_catalog.availablePacks);
    setState(() {
      _settings = normalized;
    });
    await _bridge.saveSettings(normalized);
    if (_armed) {
      await _stopMonitoring(updateStatus: false);
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Settings updated. Tap arm to restart monitoring.';
      });
    }
  }

  Future<void> _playPreview() async {
    final asset = _catalog.randomAsset(_settings.soundPack, _random);
    if (asset == null) {
      setState(() {
        _error = 'No audio clips available for ${_settings.soundPack}.';
      });
      return;
    }

    try {
      await _bridge.playAsset(
        asset,
        volume: _settings.volume,
        audioMode: _settings.callMode ? _settings.audioMode : null,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Previewed ${_settings.soundPack} pack.';
      });
    } catch (err) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Preview failed: $err';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heading = theme.textTheme.headlineMedium?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: -0.8,
    );

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF8F1E8), Color(0xFFE6D2BE)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text('Spank Mobile', style: heading),
                    const SizedBox(height: 8),
                    Text(
                      'Phone accelerometer trigger with the same threshold, baseline, and cooldown logic as the Go version.',
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 20),
                    _HeroCard(
                      armed: _armed,
                      dryRun: _settings.dryRun,
                      status: _status,
                      error: _error,
                      onToggle: () {
                        unawaited(_toggleMonitoring());
                      },
                      onPreview: () {
                        unawaited(_playPreview());
                      },
                    ),
                    const SizedBox(height: 16),
                    _LiveMetricsCard(
                      reading: _lastReading,
                      event: _lastEvent,
                      threshold: _settings.threshold,
                    ),
                    const SizedBox(height: 16),
                    _PresetCard(
                      onSelect: (preset) {
                        unawaited(
                          _saveSettings(
                            _settings.copyWith(
                              threshold: preset.threshold,
                              cooldownMs: preset.cooldownMs,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    _SettingsCard(
                      settings: _settings,
                      availablePacks: _catalog.availablePacks,
                      armed: _armed,
                      onChanged: (next) {
                        unawaited(_saveSettings(next));
                      },
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.armed,
    required this.dryRun,
    required this.status,
    required this.error,
    required this.onToggle,
    required this.onPreview,
  });

  final bool armed;
  final bool dryRun;
  final String status;
  final String? error;
  final VoidCallback onToggle;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: armed
                      ? const Color(0xFF1D6F42)
                      : const Color(0xFF8A3B12),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                armed ? 'Armed for impact' : 'Idle',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (dryRun)
                Chip(
                  label: const Text('Dry run'),
                  backgroundColor: const Color(0xFFFFE7A7),
                  side: BorderSide.none,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(status, style: theme.textTheme.bodyLarge),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(
              error!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF9F1C1C),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonal(
                  onPressed: onToggle,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: armed
                        ? const Color(0xFF261C15)
                        : const Color(0xFFD65A31),
                    foregroundColor: Colors.white,
                  ),
                  child: Text(armed ? 'Stop' : 'Arm'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: onPreview,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Preview Sound'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LiveMetricsCard extends StatelessWidget {
  const _LiveMetricsCard({
    required this.reading,
    required this.event,
    required this.threshold,
  });

  final MotionReading? reading;
  final DetectionEvent? event;
  final double threshold;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tap Test',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          if (reading == null)
            Text(
              'Start monitoring to see live accelerometer magnitude, baseline drift, and trigger deltas.',
              style: theme.textTheme.bodyLarge,
            )
          else
            Wrap(
              runSpacing: 12,
              spacing: 12,
              children: [
                _MetricChip('X', reading!.sample.x.toStringAsFixed(2)),
                _MetricChip('Y', reading!.sample.y.toStringAsFixed(2)),
                _MetricChip('Z', reading!.sample.z.toStringAsFixed(2)),
                _MetricChip(
                  'Magnitude',
                  reading!.sample.magnitude.toStringAsFixed(2),
                ),
                _MetricChip('Baseline', reading!.baseline.toStringAsFixed(2)),
                _MetricChip('Delta', reading!.delta.toStringAsFixed(2)),
                _MetricChip('Threshold', threshold.toStringAsFixed(2)),
              ],
            ),
          if (event != null) ...[
            const SizedBox(height: 16),
            Text(
              'Last hit: ${event!.timestamp.toLocal()} | delta ${event!.delta.toStringAsFixed(2)} | severity ${event!.severity.toStringAsFixed(2)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({required this.onSelect});

  final ValueChanged<SensitivityPreset> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sensitivity Presets',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: SensitivityPreset.values
                .map(
                  (preset) => ActionChip(
                    label: Text(preset.label),
                    onPressed: () => onSelect(preset),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.settings,
    required this.availablePacks,
    required this.onChanged,
    required this.armed,
  });

  final SpankSettings settings;
  final List<String> availablePacks;
  final ValueChanged<SpankSettings> onChanged;
  final bool armed;

  @override
  Widget build(BuildContext context) {
    final packs = availablePacks.isEmpty
        ? const ['pain', 'halo', 'sexy']
        : availablePacks;
    final theme = Theme.of(context);

    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Settings',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Changes are stored on-device and take effect the next time monitoring is armed.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          _SliderRow(
            label: 'Threshold',
            valueLabel: settings.threshold.toStringAsFixed(2),
            value: settings.threshold,
            min: 0.4,
            max: 4.0,
            onChanged: (value) =>
                onChanged(settings.copyWith(threshold: value)),
          ),
          _SliderRow(
            label: 'Sample Interval',
            valueLabel: '${settings.sampleIntervalMs} ms',
            value: settings.sampleIntervalMs.toDouble(),
            min: 16,
            max: 120,
            divisions: 13,
            onChanged: (value) =>
                onChanged(settings.copyWith(sampleIntervalMs: value.round())),
          ),
          _SliderRow(
            label: 'Cooldown',
            valueLabel: '${settings.cooldownMs} ms',
            value: settings.cooldownMs.toDouble(),
            min: 150,
            max: 2500,
            divisions: 47,
            onChanged: (value) =>
                onChanged(settings.copyWith(cooldownMs: value.round())),
          ),
          _SliderRow(
            label: 'Volume',
            valueLabel: settings.volume.toStringAsFixed(2),
            value: settings.volume,
            min: 0,
            max: 1,
            divisions: 10,
            onChanged: (value) => onChanged(settings.copyWith(volume: value)),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: packs.contains(settings.soundPack)
                ? settings.soundPack
                : packs.first,
            decoration: const InputDecoration(
              labelText: 'Sound Pack',
              border: OutlineInputBorder(),
            ),
            items: packs
                .map(
                  (pack) => DropdownMenuItem<String>(
                    value: pack,
                    child: Text(pack == 'pain' ? 'default / pain' : pack),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) {
                onChanged(settings.copyWith(soundPack: value));
              }
            },
          ),
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Dry run'),
            subtitle: const Text('Detect impacts without playing audio.'),
            value: settings.dryRun,
            onChanged: (value) => onChanged(settings.copyWith(dryRun: value)),
          ),
          if (Platform.isAndroid) ...[
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Call mode'),
              subtitle: Text(
                armed
                    ? 'Stop monitoring before changing this setting.'
                    : 'Keep monitoring when app is in the background (e.g. during a video call).',
              ),
              value: settings.callMode,
              onChanged: armed
                  ? null
                  : (value) => onChanged(settings.copyWith(callMode: value)),
            ),
          ],
          if (Platform.isAndroid && settings.callMode) ...[
            const SizedBox(height: 8),
            Text(
              'Audio routing',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: SpankSettings.audioModePrivate,
                  label: Text('Private'),
                  icon: Icon(Icons.hearing),
                ),
                ButtonSegment(
                  value: SpankSettings.audioModeShared,
                  label: Text('Shared'),
                  icon: Icon(Icons.volume_up),
                ),
              ],
              selected: {settings.audioMode},
              onSelectionChanged: armed
                  ? null
                  : (set) => onChanged(settings.copyWith(audioMode: set.first)),
            ),
            const SizedBox(height: 4),
            Text(
              settings.audioMode == SpankSettings.audioModePrivate
                  ? 'Earpiece only — others on the call cannot hear the sound.'
                  : 'Loudspeaker — the call mic picks it up, others can hear it.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: const Color(0xFF6B4A36)),
            ),
          ],
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
  });

  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          Row(
            children: [
              Text(label),
              const Spacer(),
              Text(
                valueLabel,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: const Color(0xFF6B4A36)),
          ),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class Detector {
  Detector({required this.threshold, required this.cooldown});

  final double threshold;
  final Duration cooldown;
  final double alpha = 0.18;

  double baseline = 0;
  DateTime? lastEvent;
  bool ready = false;

  DetectionEvent? process(MotionSample sample) {
    final magnitude = sample.magnitude;
    if (!ready) {
      baseline = magnitude;
      ready = true;
      return null;
    }

    baseline = alpha * magnitude + (1 - alpha) * baseline;
    final delta = (magnitude - baseline).abs();
    if (delta < threshold) {
      return null;
    }

    if (lastEvent != null &&
        sample.timestamp.difference(lastEvent!) < cooldown) {
      return null;
    }

    lastEvent = sample.timestamp;
    return DetectionEvent(
      timestamp: sample.timestamp,
      delta: delta,
      severity: delta / threshold,
    );
  }
}

class DetectionEvent {
  DetectionEvent({
    required this.timestamp,
    required this.delta,
    required this.severity,
  });

  final DateTime timestamp;
  final double delta;
  final double severity;
}

class MotionReading {
  MotionReading({required this.sample, required this.baseline})
    : delta = (sample.magnitude - baseline).abs();

  factory MotionReading.from(MotionSample sample, double baseline) {
    return MotionReading(sample: sample, baseline: baseline);
  }

  final MotionSample sample;
  final double baseline;
  final double delta;
}

class MotionSample {
  MotionSample({
    required this.timestamp,
    required this.x,
    required this.y,
    required this.z,
  }) : magnitude = sqrt(x * x + y * y + z * z);

  factory MotionSample.fromEvent(dynamic raw) {
    final map = Map<dynamic, dynamic>.from(raw as Map);
    return MotionSample(
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (map['timestampMs'] as num).round(),
      ),
      x: (map['x'] as num).toDouble(),
      y: (map['y'] as num).toDouble(),
      z: (map['z'] as num).toDouble(),
    );
  }

  final DateTime timestamp;
  final double x;
  final double y;
  final double z;
  final double magnitude;
}

class SpankSettings {
  static const String audioModePrivate = 'private';
  static const String audioModeShared = 'shared';

  SpankSettings({
    required this.threshold,
    required this.sampleIntervalMs,
    required this.cooldownMs,
    required this.soundPack,
    required this.volume,
    required this.dryRun,
    required this.callMode,
    required this.audioMode,
  });

  factory SpankSettings.defaults() {
    return SpankSettings(
      threshold: 1.8,
      sampleIntervalMs: 40,
      cooldownMs: 1200,
      soundPack: 'pain',
      volume: 1.0,
      dryRun: false,
      callMode: false,
      audioMode: SpankSettings.audioModePrivate,
    );
  }

  factory SpankSettings.fromMap(Map<Object?, Object?>? map) {
    final defaults = SpankSettings.defaults();
    if (map == null) {
      return defaults;
    }

    return SpankSettings(
      threshold: ((map['threshold'] as num?)?.toDouble() ?? defaults.threshold)
          .clamp(0.1, 10.0),
      sampleIntervalMs:
          ((map['sampleIntervalMs'] as num?)?.round() ??
                  defaults.sampleIntervalMs)
              .clamp(16, 500),
      cooldownMs: ((map['cooldownMs'] as num?)?.round() ?? defaults.cooldownMs)
          .clamp(0, 10000),
      soundPack: (map['soundPack'] as String?)?.trim().isNotEmpty == true
          ? map['soundPack']! as String
          : defaults.soundPack,
      volume: ((map['volume'] as num?)?.toDouble() ?? defaults.volume).clamp(
        0.0,
        1.0,
      ),
      dryRun: map['dryRun'] as bool? ?? defaults.dryRun,
      callMode: map['callMode'] as bool? ?? defaults.callMode,
      audioMode:
          (map['audioMode'] as String?)?.trim() == SpankSettings.audioModeShared
          ? SpankSettings.audioModeShared
          : SpankSettings.audioModePrivate,
    );
  }

  final double threshold;
  final int sampleIntervalMs;
  final int cooldownMs;
  final String soundPack;
  final double volume;
  final bool dryRun;
  final bool callMode;
  final String audioMode;

  Map<String, Object> toMap() {
    return <String, Object>{
      'threshold': threshold,
      'sampleIntervalMs': sampleIntervalMs,
      'cooldownMs': cooldownMs,
      'soundPack': soundPack,
      'volume': volume,
      'dryRun': dryRun,
      'callMode': callMode,
      'audioMode': audioMode,
    };
  }

  SpankSettings copyWith({
    double? threshold,
    int? sampleIntervalMs,
    int? cooldownMs,
    String? soundPack,
    double? volume,
    bool? dryRun,
    bool? callMode,
    String? audioMode,
  }) {
    return SpankSettings(
      threshold: threshold ?? this.threshold,
      sampleIntervalMs: sampleIntervalMs ?? this.sampleIntervalMs,
      cooldownMs: cooldownMs ?? this.cooldownMs,
      soundPack: soundPack ?? this.soundPack,
      volume: volume ?? this.volume,
      dryRun: dryRun ?? this.dryRun,
      callMode: callMode ?? this.callMode,
      audioMode: audioMode ?? this.audioMode,
    );
  }

  SpankSettings withAvailableSound(List<String> availablePacks) {
    if (availablePacks.isEmpty) {
      return this;
    }
    if (availablePacks.contains(soundPack)) {
      return this;
    }
    if (soundPack == 'default' && availablePacks.contains('pain')) {
      return copyWith(soundPack: 'pain');
    }
    return copyWith(soundPack: availablePacks.first);
  }
}

class AudioCatalog {
  AudioCatalog(this._packAssets);

  factory AudioCatalog.empty() => AudioCatalog(const {});

  static const String _prefix = 'assets/audio/';

  final Map<String, List<String>> _packAssets;

  List<String> get availablePacks {
    final packs = _packAssets.keys.toList()..sort();
    return packs.map((pack) => pack == 'pain' ? 'pain' : pack).toList();
  }

  String? randomAsset(String soundPack, Random random) {
    final canonical = soundPack == 'default' ? 'pain' : soundPack;
    final options = _packAssets[canonical];
    if (options == null || options.isEmpty) {
      return null;
    }
    return options[random.nextInt(options.length)];
  }

  static Future<AudioCatalog> load() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final packs = <String, List<String>>{};

    for (final asset in manifest.listAssets()) {
      if (!asset.startsWith(_prefix) || !asset.endsWith('.mp3')) {
        continue;
      }
      final relative = asset.substring(_prefix.length);
      final slash = relative.indexOf('/');
      if (slash <= 0) {
        continue;
      }
      final pack = relative.substring(0, slash);
      packs.putIfAbsent(pack, () => <String>[]).add(asset);
    }

    for (final assets in packs.values) {
      assets.sort();
    }

    return AudioCatalog(packs);
  }
}

class PlatformBridge {
  static const MethodChannel _methods = MethodChannel('spank/methods');
  static const EventChannel _motion = EventChannel('spank/motion');

  Future<SpankSettings> loadSettings() async {
    final raw = await _methods.invokeMapMethod<Object?, Object?>(
      'loadSettings',
    );
    return SpankSettings.fromMap(raw);
  }

  Future<void> saveSettings(SpankSettings settings) {
    return _methods.invokeMethod<void>('saveSettings', settings.toMap());
  }

  Future<void> playAsset(
    String assetPath, {
    required double volume,
    String? audioMode,
  }) {
    final args = <String, Object>{'assetPath': assetPath, 'volume': volume};
    if (audioMode != null) {
      args['audioMode'] = audioMode;
    }
    return _methods.invokeMethod<void>('playAsset', args);
  }

  Future<void> startForegroundService() {
    if (!Platform.isAndroid) {
      return Future.value();
    }
    return _methods.invokeMethod<void>('startForegroundService');
  }

  Future<void> stopForegroundService() {
    if (!Platform.isAndroid) {
      return Future.value();
    }
    return _methods.invokeMethod<void>('stopForegroundService');
  }

  Stream<MotionSample> motionEvents({required int sampleIntervalMs}) {
    return _motion
        .receiveBroadcastStream(<String, Object>{
          'sampleIntervalMs': sampleIntervalMs,
        })
        .map(MotionSample.fromEvent);
  }
}

enum SensitivityPreset {
  light('Light taps', 1.0, 700),
  medium('Medium taps', 1.8, 1200),
  heavy('Hard slaps', 2.6, 1500);

  const SensitivityPreset(this.label, this.threshold, this.cooldownMs);

  final String label;
  final double threshold;
  final int cooldownMs;
}
