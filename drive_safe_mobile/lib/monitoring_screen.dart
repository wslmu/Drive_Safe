import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_mesh_detection/google_mlkit_face_mesh_detection.dart';

import 'session_history.dart';

const _surface = Color(0xFF111E2D);
const _border = Color(0xFF243C55);
const _text = Color(0xFFF2F6FB);
const _muted = Color(0xFF8FA2B7);
const _green = Color(0xFF42C983);
const _amber = Color(0xFFF0B24D);
const _red = Color(0xFFFF6B78);
const _blue = Color(0xFF52A8FF);
const _cyan = Color(0xFF56E0D2);

class MonitoringScreen extends StatefulWidget {
  const MonitoringScreen({super.key});

  @override
  State<MonitoringScreen> createState() => _MonitoringScreenState();
}

class _MonitoringScreenState extends State<MonitoringScreen> {
  CameraController? _cameraController;
  late final FaceMeshDetector _meshDetector;
  late final AudioPlayer _alarmPlayer;

  bool _initializing = true;
  bool _isProcessing = false;
  bool _calibrated = false;
  DateTime _startedAt = DateTime.now();
  DateTime _calibrationStartedAt = DateTime.now();
  DateTime _blinkWindowStartedAt = DateTime.now();
  DateTime? _eyesClosedSince;
  DateTime? _mouthOpenSince;
  DateTime? _headTiltSince;
  DateTime? _forwardDropSince;
  final List<DateTime> _recentYawns = <DateTime>[];
  bool _yawnLatched = false;
  DateTime _lastAnalysisAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _previousEyesOpen = true;
  bool _alertActive = false;
  bool _alarmPlaying = false;

  double _baselineEar = 0.28;
  double _baselineMar = 0.12;
  double _baselineHeadAngle = 0;
  double _baselineForwardDrop = 0;
  double _baselineEarSum = 0;
  double _baselineMarSum = 0;
  double _baselineHeadAngleSum = 0;
  double _baselineForwardDropSum = 0;
  int _baselineSamples = 0;

  int _alerts = 0;
  int _blinksPerMinute = 0;
  int _blinkCounter = 0;
  int _fatigueScore = 0;
  int _maxFatigueScore = 0;
  int _fatigueScoreTotal = 0;
  int _fatigueScoreSamples = 0;
  bool _sessionSaved = false;
  final Map<String, int> _alertBreakdown = <String, int>{
    'eyes_closed': 0,
    'repeated_yawn': 0,
    'head_tilt': 0,
    'head_forward': 0,
  };
  final List<String> _alertEvents = <String>[];
  bool _eyeAlertPrevious = false;
  bool _mouthAlertPrevious = false;
  bool _headAlertPrevious = false;
  bool _forwardAlertPrevious = false;

  String _status = 'Initialisation camera...';
  String _eyes = 'En attente';
  String _mouth = 'En attente';
  String _head = 'En attente';
  String _quality = 'Recherche du visage';
  String _recommendation = 'Positionnez le smartphone face au conducteur.';

  @override
  void initState() {
    super.initState();
    _meshDetector = FaceMeshDetector(
      option: FaceMeshDetectorOptions.faceMesh,
    );
    _alarmPlayer = AudioPlayer();
    unawaited(_alarmPlayer.setReleaseMode(ReleaseMode.loop));
    _initCamera();
  }

  @override
  void dispose() {
    unawaited(_saveSessionIfNeeded());
    unawaited(_alarmPlayer.stop());
    _alarmPlayer.dispose();
    _cameraController?.dispose();
    _meshDetector.close();
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final format = defaultTargetPlatform == TargetPlatform.iOS
          ? ImageFormatGroup.bgra8888
          : ImageFormatGroup.nv21;

      final controller = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: format,
      );

      await controller.initialize();
      await controller.startImageStream(_processCameraImage);

      if (!mounted) return;
      setState(() {
        _cameraController = controller;
        _initializing = false;
        _startedAt = DateTime.now();
        _calibrationStartedAt = DateTime.now();
        _blinkWindowStartedAt = DateTime.now();
        _status = 'Calibration en cours';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _status = 'Erreur camera';
        _quality = error.toString();
      });
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isProcessing || _cameraController == null) return;

    final now = DateTime.now();
    if (now.difference(_lastAnalysisAt).inMilliseconds < 180) return;
    _lastAnalysisAt = now;
    _isProcessing = true;

    try {
      final inputImage = _buildInputImage(image, _cameraController!);
      if (inputImage == null) {
        _isProcessing = false;
        return;
      }

      final meshes = await _meshDetector.processImage(inputImage);
      if (!mounted) {
        _isProcessing = false;
        return;
      }

      if (meshes.isEmpty) {
        if (_alertActive) {
          unawaited(_stopAlarm());
        }
        setState(() {
          _quality = 'Visage non detecte';
          _status = 'Repositionnez le visage face a la camera';
          _eyes = 'Non detecte';
          _mouth = 'Non detecte';
          _head = 'Non detecte';
          _alertActive = false;
        });
        _resetTransientSignals();
        _isProcessing = false;
        return;
      }

      final points = meshes.first.points;
      if (points.length < 388) {
        _isProcessing = false;
        return;
      }

      final ear = (_ear(points, const [362, 385, 387, 263, 373, 380]) +
              _ear(points, const [33, 160, 158, 133, 153, 144])) /
          2;
      final mar = _mar(points, const [13, 14, 78, 308]);
      final angle = _headAngle(points);
      final forwardDrop = _forwardDrop(points);

      if (!_calibrated) {
        _baselineEarSum += ear;
        _baselineMarSum += mar;
        _baselineHeadAngleSum += angle;
        _baselineForwardDropSum += forwardDrop;
        _baselineSamples++;
        final elapsed = now.difference(_calibrationStartedAt).inSeconds;
        final remaining = math.max(0, 5 - elapsed);

        if (elapsed >= 5 && _baselineSamples > 0) {
          _baselineEar = _baselineEarSum / _baselineSamples;
          _baselineMar = _baselineMarSum / _baselineSamples;
          _baselineHeadAngle = _baselineHeadAngleSum / _baselineSamples;
          _baselineForwardDrop = _baselineForwardDropSum / _baselineSamples;
          _calibrated = true;
          _status = 'Calibration terminee';
        } else {
          setState(() {
            _status = 'Calibration en cours ($remaining s)';
            _quality = 'Visage detecte';
            _eyes = 'Calibration';
            _mouth = 'Calibration';
            _head = 'Calibration';
          });
          _isProcessing = false;
          return;
        }
      }

      final eyeThreshold = math.min(0.25, _baselineEar * 0.72);
      final mouthThreshold = math.max(0.50, _baselineMar * 2.2);
      final headDelta = (angle - _baselineHeadAngle).abs();
      final forwardDelta = forwardDrop - _baselineForwardDrop;

      final eyesOpen = ear >= eyeThreshold;
      if (!eyesOpen && _previousEyesOpen) {
        _blinkCounter++;
      }
      _previousEyesOpen = eyesOpen;

      final blinkElapsed = now.difference(_blinkWindowStartedAt).inSeconds;
      if (blinkElapsed >= 10) {
        _blinksPerMinute = ((_blinkCounter * 60) / blinkElapsed).round();
        _blinkCounter = 0;
        _blinkWindowStartedAt = now;
      }

      final eyeAlert = _checkTimedCondition(
        active: ear < eyeThreshold,
        startedAt: _eyesClosedSince,
        durationSeconds: 2,
        onStart: () => _eyesClosedSince = now,
        onReset: () => _eyesClosedSince = null,
      );
      final mouthOpen = mar > mouthThreshold;
      if (!mouthOpen) {
        _mouthOpenSince = null;
        _yawnLatched = false;
      } else {
        _mouthOpenSince ??= now;
        if (!_yawnLatched &&
            now.difference(_mouthOpenSince!).inMilliseconds >= 900) {
          _recentYawns.add(now);
          _yawnLatched = true;
        }
      }
      _recentYawns.removeWhere(
        (item) => now.difference(item).inSeconds > 18,
      );
      final mouthAlert = _recentYawns.length >= 2;
      final headAlert = _checkTimedCondition(
        active: headDelta > 15,
        startedAt: _headTiltSince,
        durationSeconds: 2,
        onStart: () => _headTiltSince = now,
        onReset: () => _headTiltSince = null,
      );
      final forwardAlert = _checkTimedCondition(
        active: forwardDelta > 0.035,
        startedAt: _forwardDropSince,
        durationSeconds: 2,
        onStart: () => _forwardDropSince = now,
        onReset: () => _forwardDropSince = null,
      );

      final score = _fatigueScoreFromSignals(
        ear: ear,
        mar: mar,
        headDelta: headDelta,
        forwardDelta: forwardDelta,
        eyeThreshold: eyeThreshold,
        mouthThreshold: mouthThreshold,
        blinksPerMinute: _blinksPerMinute,
        mouthAlert: mouthAlert,
      );

      final anyAlert = eyeAlert || mouthAlert || headAlert || forwardAlert;
      _trackAlertTransitions(
        eyeAlert: eyeAlert,
        mouthAlert: mouthAlert,
        headAlert: headAlert,
        forwardAlert: forwardAlert,
      );
      if (anyAlert && !_alertActive) {
        _alerts++;
        HapticFeedback.heavyImpact();
        unawaited(_startAlarm());
      } else if (!anyAlert && _alertActive) {
        unawaited(_stopAlarm());
      }

      _fatigueScore = score;
      _maxFatigueScore = math.max(_maxFatigueScore, score);
      _fatigueScoreTotal += score;
      _fatigueScoreSamples++;

      setState(() {
        _alertActive = anyAlert;
        _quality = 'Detection stable';
        _eyes = eyeAlert ? 'Fermes' : eyesOpen ? 'Ouverts' : 'Fatigue suspectee';
        _mouth = mouthAlert
          ? 'Baillements repetes'
          : mouthOpen
            ? 'Ouverte'
            : 'Normale';
        _head = headAlert
          ? ((angle - _baselineHeadAngle) > 0 ? 'Penchee gauche' : 'Penchee droite')
            : forwardAlert
                ? 'Tete vers avant'
                : 'Stable';
        _status = _statusFromScore(score, anyAlert);
        _recommendation = _recommendationFromScore(score, anyAlert);
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _quality = 'Analyse interrompue';
        });
      }
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _saveSessionIfNeeded() async {
    if (_sessionSaved) return;
    final durationSeconds = DateTime.now().difference(_startedAt).inSeconds;
    if (durationSeconds < 8 || _fatigueScoreSamples == 0) return;

    final averageFatigueScore =
        (_fatigueScoreTotal / _fatigueScoreSamples).round().clamp(0, 100);
    final dominantState = _statusFromScore(_maxFatigueScore, _alerts > 0);

    _sessionSaved = true;
    try {
      await SessionHistoryStore.saveSession(
        SessionRecord(
          startedAtIso: _startedAt.toUtc().toIso8601String(),
          durationSeconds: durationSeconds,
          alertCount: _alerts,
          alertBreakdown: Map<String, int>.from(_alertBreakdown),
          alertEvents: List<String>.from(_alertEvents),
          maxFatigueScore: _maxFatigueScore,
          averageFatigueScore: averageFatigueScore,
          dominantState: dominantState,
        ),
      );
    } catch (_) {
      _sessionSaved = false;
    }
  }

  void _trackAlertTransitions({
    required bool eyeAlert,
    required bool mouthAlert,
    required bool headAlert,
    required bool forwardAlert,
  }) {
    if (eyeAlert && !_eyeAlertPrevious) {
      _recordAlertEvent('eyes_closed', 'Yeux fermes trop longtemps');
    }
    if (mouthAlert && !_mouthAlertPrevious) {
      _recordAlertEvent('repeated_yawn', 'Baillements repetes');
    }
    if (headAlert && !_headAlertPrevious) {
      _recordAlertEvent('head_tilt', 'Tete inclinee');
    }
    if (forwardAlert && !_forwardAlertPrevious) {
      _recordAlertEvent('head_forward', 'Tete vers avant');
    }

    _eyeAlertPrevious = eyeAlert;
    _mouthAlertPrevious = mouthAlert;
    _headAlertPrevious = headAlert;
    _forwardAlertPrevious = forwardAlert;
  }

  void _recordAlertEvent(String key, String label) {
    _alertBreakdown[key] = (_alertBreakdown[key] ?? 0) + 1;
    final offsetSeconds = DateTime.now().difference(_startedAt).inSeconds;
    final mm = (offsetSeconds ~/ 60).toString().padLeft(2, '0');
    final ss = (offsetSeconds % 60).toString().padLeft(2, '0');
    _alertEvents.add('$mm:$ss - $label');
    if (_alertEvents.length > 60) {
      _alertEvents.removeAt(0);
    }
  }

  Future<void> _startAlarm() async {
    if (_alarmPlaying) return;
    try {
      await _alarmPlayer.play(AssetSource('audio/alarme.mp3'), volume: 1.0);
      _alarmPlaying = true;
    } catch (_) {
      _alarmPlaying = false;
    }
  }

  Future<void> _stopAlarm() async {
    if (!_alarmPlaying) return;
    try {
      await _alarmPlayer.stop();
    } finally {
      _alarmPlaying = false;
    }
  }

  bool _checkTimedCondition({
    required bool active,
    required DateTime? startedAt,
    required int durationSeconds,
    required VoidCallback onStart,
    required VoidCallback onReset,
  }) {
    if (!active) {
      onReset();
      return false;
    }

    if (startedAt == null) {
      onStart();
      return false;
    }

    return DateTime.now().difference(startedAt).inSeconds >= durationSeconds;
  }

  void _resetTransientSignals() {
    _eyesClosedSince = null;
    _mouthOpenSince = null;
    _headTiltSince = null;
    _forwardDropSince = null;
    _recentYawns.clear();
    _yawnLatched = false;
  }

  InputImage? _buildInputImage(
    CameraImage image,
    CameraController controller,
  ) {
    final rotation = InputImageRotationValue.fromRawValue(
      controller.description.sensorOrientation,
    );
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (rotation == null || format == null) return null;

    final bytes = _concatenatePlanes(image.planes);

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  Uint8List _concatenatePlanes(List<Plane> planes) {
    final writeBuffer = WriteBuffer();
    for (final plane in planes) {
      writeBuffer.putUint8List(plane.bytes);
    }
    return writeBuffer.done().buffer.asUint8List();
  }

  double _distance(FaceMeshPoint a, FaceMeshPoint b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  double _ear(List<FaceMeshPoint> points, List<int> idx) {
    final p1 = points[idx[0]];
    final p2 = points[idx[1]];
    final p3 = points[idx[2]];
    final p4 = points[idx[3]];
    final p5 = points[idx[4]];
    final p6 = points[idx[5]];
    final vertical = _distance(p2, p6) + _distance(p3, p5);
    final horizontal = _distance(p1, p4);
    if (horizontal == 0) return 0;
    return vertical / (2 * horizontal);
  }

  double _mar(List<FaceMeshPoint> points, List<int> idx) {
    final top = points[idx[0]];
    final bottom = points[idx[1]];
    final left = points[idx[2]];
    final right = points[idx[3]];
    final horizontal = _distance(left, right);
    if (horizontal == 0) return 0;
    return _distance(top, bottom) / horizontal;
  }

  double _headAngle(List<FaceMeshPoint> points) {
    final right = points[33];
    final left = points[263];
    return math.atan2(left.y - right.y, left.x - right.x) * 180 / math.pi;
  }

  double _forwardDrop(List<FaceMeshPoint> points) {
    return points[4].y - points[6].y;
  }

  int _fatigueScoreFromSignals({
    required double ear,
    required double mar,
    required double headDelta,
    required double forwardDelta,
    required double eyeThreshold,
    required double mouthThreshold,
    required int blinksPerMinute,
    required bool mouthAlert,
  }) {
    var score = 0;
    if (ear < eyeThreshold) {
      score += 30;
    } else if (ear < 0.28) {
      score += 10;
    }
    if (mouthAlert) {
      score += 20;
    } else if (mar > 0.35) {
      score += 5;
    }
    if (headDelta > 15) {
      score += 25;
    } else if (headDelta > 8) {
      score += 8;
    }
    if (blinksPerMinute > 25) {
      score += 15;
    }
    if (forwardDelta > 0.035) {
      score += 10;
    }
    return score.clamp(0, 100);
  }

  String _statusFromScore(int score, bool alert) {
    if (alert || score >= 60) return 'Vigilance critique';
    if (score >= 30) return 'Vigilance moderee';
    return 'Vigilance elevee';
  }

  String _recommendationFromScore(int score, bool alert) {
    if (alert || score >= 60) {
      return 'Pause immediate recommandee. Arretez-vous des que possible.';
    }
    if (score >= 30) {
      return 'Surveillez votre etat et planifiez une pause rapidement.';
    }
    return 'Session stable. Continuez a garder le visage bien visible.';
  }

  @override
  Widget build(BuildContext context) {
    final session = DateTime.now().difference(_startedAt).inSeconds;
    final vigilance = (100 - _fatigueScore).clamp(0, 100);
    final scoreColor = _fatigueScore >= 60
        ? _red
        : _fatigueScore >= 30
            ? _amber
            : _green;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _MonitoringHeader(),
          const SizedBox(height: 20),
          Container(
            height: 280,
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: _border),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: _buildPreview(),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: _border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Score de vigilance', style: TextStyle(color: _muted)),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$vigilance%',
                      style: const TextStyle(
                        color: _text,
                        fontSize: 38,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _status,
                        style: TextStyle(
                          color: scoreColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: vigilance / 100,
                    minHeight: 14,
                    color: scoreColor,
                    backgroundColor: const Color(0xFF223347),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(child: _MetricChip(title: 'Yeux', value: _eyes, color: _eyes == 'Ouverts' ? _blue : _red)),
                    const SizedBox(width: 10),
                    Expanded(child: _MetricChip(title: 'Bouche', value: _mouth, color: _mouth == 'Normale' ? _blue : _amber)),
                    const SizedBox(width: 10),
                    Expanded(child: _MetricChip(title: 'Tete', value: _head, color: _head == 'Stable' ? _blue : _amber)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _InfoPanel(title: 'Session', value: _formatDuration(session), accent: _blue)),
              const SizedBox(width: 12),
              Expanded(child: _InfoPanel(title: 'Detection', value: _quality, accent: _cyan)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _InfoPanel(title: 'Clin/min', value: '$_blinksPerMinute', accent: _amber)),
              const SizedBox(width: 12),
              Expanded(child: _InfoPanel(title: 'Alertes', value: '$_alerts', accent: _alertActive ? _red : _green)),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _alertActive ? const Color(0x33FF6B78) : const Color(0xFF16283C),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _border),
            ),
            child: Row(
              children: [
                Icon(
                  _alertActive ? Icons.warning_amber_rounded : Icons.tips_and_updates_rounded,
                  color: _alertActive ? _red : _amber,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _recommendation,
                    style: const TextStyle(color: _text, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    if (_initializing) {
      return const Center(
        child: CircularProgressIndicator(color: _blue),
      );
    }

    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Center(
        child: Text(
          'Camera indisponible',
          style: TextStyle(color: _text),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreview(_cameraController!),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.black.withValues(alpha: 0.15),
                Colors.transparent,
                Colors.black.withValues(alpha: 0.25),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        Center(
          child: Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: _cyan.withValues(alpha: 0.8), width: 2),
            ),
          ),
        ),
        Positioned(
          top: 16,
          left: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: (_alertActive ? _red : _green).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              _alertActive ? 'ALERTE ACTIVE' : 'SURVEILLANCE ACTIVE',
              style: TextStyle(
                color: _alertActive ? _red : _green,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 16,
          left: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Text(
              'Traitement local uniquement. Aucune video n est enregistree.',
              style: TextStyle(color: _text),
            ),
          ),
        ),
      ],
    );
  }

  String _formatDuration(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

class _MonitoringHeader extends StatelessWidget {
  const _MonitoringHeader();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Surveillance',
                style: TextStyle(
                  color: _text,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Camera frontale + Face Mesh + score de vigilance temps reel',
                style: TextStyle(color: _muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String title;
  final String value;
  final Color color;

  const _MetricChip({
    required this.title,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF16283C),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _muted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  final String title;
  final String value;
  final Color accent;

  const _InfoPanel({
    required this.title,
    required this.value,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _muted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              color: accent,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
