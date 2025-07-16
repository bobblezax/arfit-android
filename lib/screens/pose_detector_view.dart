// lib/screens/pose_detector_view.dart

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:permission_handler/permission_handler.dart';

// Enum to define different workout types
enum WorkoutType {
  pushups,
  bicepCurls,
  shoulderPress,
  squats,
  none,
}

class PoseDetectorView extends StatefulWidget {
  final WorkoutType workoutType;
  final int? targetReps;

  const PoseDetectorView({
    super.key,
    this.workoutType = WorkoutType.none,
    this.targetReps,
  });

  @override
  State<PoseDetectorView> createState() => _PoseDetectorViewState();
}

class _PoseDetectorViewState extends State<PoseDetectorView> with SingleTickerProviderStateMixin {
  DateTime _lastRepTime = DateTime.now();
  CameraController? _cameraController;
  late final PoseDetector _poseDetector;
  bool _isDetecting = false;
  CustomPaint? _customPaint;
  int _reps = 0;
  String _stage = ""; // "up" or "down" for reps
  String _feedback = "Initializing..."; // Initial feedback state
  String? _error;
  final Stopwatch _stopwatch = Stopwatch(); // Duration tracker
  double _calories = 0.0; // Calorie estimation
  double _feedbackOpacity = 1.0; // For fade animation
  int _lastRepCount = 0; // To detect rep changes for animation
  late AnimationController _animationController; // For bounce animation
  late Animation<double> _bounceAnimation;

  // ✅ ADDED: For workout completion effects
  late ConfettiController _confettiController;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _workoutCompleted = false;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 2));
    _poseDetector = PoseDetector(
      options: PoseDetectorOptions(
        mode: PoseDetectionMode.stream,
        model: PoseDetectionModel.accurate,
      ),
    );
    _initializeCamera();
    _stopwatch.start();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _bounceAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.elasticOut),
    );
  }

  Future<void> _initializeCamera() async {
    try {
      final status = await Permission.camera.request();
      if (status != PermissionStatus.granted) {
        if (mounted) setState(() => _error = "Camera permission denied");
        return;
      }
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _error = "Camera failed to load");
        return;
      }
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      _cameraController = CameraController(camera, ResolutionPreset.medium, enableAudio: false);
      await _cameraController!.initialize();
      if (_cameraController!.value.isInitialized) {
        await _cameraController!.startImageStream(_processCameraImage);
        if (mounted) setState(() => _feedback = "Stand in frame to begin.");
      } else {
        if (mounted) setState(() => _error = "Camera failed to initialize.");
      }
      if (mounted) setState(() => _error = null);
    } catch (e) {
      if (mounted) setState(() => _error = "Failed to initialize camera: $e");
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isDetecting || !mounted) return;
    _isDetecting = true;
    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();
      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: InputImageRotationValue.fromRawValue(_cameraController!.description.sensorOrientation) ?? InputImageRotation.rotation0deg,
          format: InputImageFormatValue.fromRawValue(image.format.raw) ?? InputImageFormat.nv21,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );
      final poses = await _poseDetector.processImage(inputImage);
      if (poses.isNotEmpty) {
        final pose = poses.first;
        if (pose.landmarks.length < 10) {
          _customPaint = null;
          _feedback = "Hold still. Pose unclear.";
        } else {
          _customPaint = CustomPaint(
            painter: PosePainter(
              pose,
              Size(image.width.toDouble(), image.height.toDouble()),
              _cameraController!.description.lensDirection,
              InputImageRotationValue.fromRawValue(_cameraController!.description.sensorOrientation) ?? InputImageRotation.rotation0deg,
            ),
          );
          _updateWorkoutState(pose);
        }
      } else {
        _customPaint = null;
        _feedback = "No pose detected. Adjust your position.";
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("Error processing image: $e");
    } finally {
      _isDetecting = false;
    }
  }

  void _updateWorkoutState(Pose pose) {
    if (_workoutCompleted) return;

    if (widget.workoutType == WorkoutType.none) {
      _feedback = "Error: Workout type not selected.";
      return;
    }

    if (_reps > _lastRepCount) {
      _animationController.forward().then((_) => _animationController.reverse());
      _lastRepCount = _reps;
    }

    _updateCalories();

    switch (widget.workoutType) {
      case WorkoutType.pushups:
        _trackPushups(pose);
        break;
      case WorkoutType.bicepCurls:
        _trackBicepCurls(pose);
        break;
      case WorkoutType.shoulderPress:
        _trackShoulderPress(pose);
        break;
      case WorkoutType.squats:
        _trackSquats(pose);
        break;
      case WorkoutType.none:
        _feedback = "Tracking not active.";
        break;
    }
  }

  void _handleWorkoutCompletion() {
    if (_workoutCompleted) return;
    setState(() {
      _workoutCompleted = true;
      _feedback = "Workout Complete!";
    });

    _confettiController.play();
    _audioPlayer.play(AssetSource('success.mp3'));

    Future.delayed(const Duration(milliseconds: 2000), () async {
      if (mounted) {
        final shouldExit = await _onPopInvoked();
        if (shouldExit) {
          Navigator.of(context).pop();
        }
      }
    });
  }

  void _trackPushups(Pose pose) {
    final lShoulder = _getLandmark(pose, PoseLandmarkType.leftShoulder);
    final lElbow = _getLandmark(pose, PoseLandmarkType.leftElbow);
    final lWrist = _getLandmark(pose, PoseLandmarkType.leftWrist);
    final rShoulder = _getLandmark(pose, PoseLandmarkType.rightShoulder);
    final rElbow = _getLandmark(pose, PoseLandmarkType.rightElbow);
    final rWrist = _getLandmark(pose, PoseLandmarkType.rightWrist);

    if (lShoulder != null && lElbow != null && lWrist != null && rShoulder != null && rElbow != null && rWrist != null) {
      final leftArmAngle = _calculateAngle(lShoulder, lElbow, lWrist);
      final rightArmAngle = _calculateAngle(rShoulder, rElbow, rWrist);

      if (leftArmAngle > 160 && rightArmAngle > 160) {
        _stage = "up";
        _feedback = "Push down!";
      }
      if (leftArmAngle < 90 && rightArmAngle < 90 && _stage == "up") {
        final now = DateTime.now();
        if (now.difference(_lastRepTime).inMilliseconds < 800) return;
        _lastRepTime = now;
        _stage = "down";
        _reps++;
        _feedback = "Push up!";
        if (widget.targetReps != null && _reps >= widget.targetReps!) {
          _handleWorkoutCompletion();
        }
      }
    } else {
      _feedback = "Adjust: Ensure elbows and shoulders are visible.";
    }
  }

  void _trackBicepCurls(Pose pose) {
    final lShoulder = _getLandmark(pose, PoseLandmarkType.leftShoulder);
    final lElbow = _getLandmark(pose, PoseLandmarkType.leftElbow);
    final lWrist = _getLandmark(pose, PoseLandmarkType.leftWrist);
    final rShoulder = _getLandmark(pose, PoseLandmarkType.rightShoulder);
    final rElbow = _getLandmark(pose, PoseLandmarkType.rightElbow);
    final rWrist = _getLandmark(pose, PoseLandmarkType.rightWrist);

    if (lShoulder != null && lElbow != null && lWrist != null && rShoulder != null && rElbow != null && rWrist != null) {
      final leftArmAngle = _calculateAngle(lShoulder, lElbow, lWrist);
      final rightArmAngle = _calculateAngle(rShoulder, rElbow, rWrist);

      if (leftArmAngle > 160 && rightArmAngle > 160) {
        _stage = "down";
        _feedback = "Curl up!";
      }
      if (leftArmAngle < 40 && rightArmAngle < 40 && _stage == 'down') {
        final now = DateTime.now();
        if (now.difference(_lastRepTime).inMilliseconds < 800) return;
        _lastRepTime = now;
        _stage = "up";
        _reps++;
        _feedback = "Lower down!";
        if (widget.targetReps != null && _reps >= widget.targetReps!) {
          _handleWorkoutCompletion();
        }
      }
    } else {
      _feedback = "Adjust: Ensure shoulders, elbows, and wrists are visible.";
    }
  }

  void _trackShoulderPress(Pose pose) {
    final lShoulder = _getLandmark(pose, PoseLandmarkType.leftShoulder);
    final lElbow = _getLandmark(pose, PoseLandmarkType.leftElbow);
    final lWrist = _getLandmark(pose, PoseLandmarkType.leftWrist);
    final rShoulder = _getLandmark(pose, PoseLandmarkType.rightShoulder);
    final rElbow = _getLandmark(pose, PoseLandmarkType.rightElbow);
    final rWrist = _getLandmark(pose, PoseLandmarkType.rightWrist);

    if (lShoulder != null && lElbow != null && lWrist != null && rShoulder != null && rElbow != null && rWrist != null) {
      final leftArmAngle = _calculateAngle(lShoulder, lElbow, lWrist);
      final rightArmAngle = _calculateAngle(rShoulder, rElbow, rWrist);

      if (leftArmAngle > 160 && rightArmAngle > 160) {
        _stage = "up";
        _feedback = "Lower weights!";
      }
      if (leftArmAngle < 90 && rightArmAngle < 90 && _stage == "up") {
        final now = DateTime.now();
        if (now.difference(_lastRepTime).inMilliseconds < 800) return;
        _lastRepTime = now;
        _stage = "down";
        _reps++;
        _feedback = "Press up!";
        if (widget.targetReps != null && _reps >= widget.targetReps!) {
          _handleWorkoutCompletion();
        }
      }
    } else {
      _feedback = "Adjust: Ensure shoulders, elbows, and wrists are visible.";
    }
  }

  void _trackSquats(Pose pose) {
    final lHip = _getLandmark(pose, PoseLandmarkType.leftHip);
    final lKnee = _getLandmark(pose, PoseLandmarkType.leftKnee);
    final lAnkle = _getLandmark(pose, PoseLandmarkType.leftAnkle);

    if (lHip != null && lKnee != null && lAnkle != null) {
      final kneeAngle = _calculateAngle(lHip, lKnee, lAnkle);
      if (kneeAngle > 160) {
        _stage = "up";
        _feedback = "Squat down!";
      }
      if (kneeAngle < 90 && _stage == "up") {
        final now = DateTime.now();
        if (now.difference(_lastRepTime).inMilliseconds < 800) return;
        _lastRepTime = now;
        _stage = "down";
        _reps++;
        _feedback = "Stand up!";
        if (widget.targetReps != null && _reps >= widget.targetReps!) {
          _handleWorkoutCompletion();
        }
      }
    } else {
      _feedback = "Adjust: Ensure hips, knees, and ankles are visible.";
    }
  }

  Future<bool> _onPopInvoked() async {
    _stopwatch.stop();
    _updateCalories();
    if (mounted) setState(() {});

    final shouldExit = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text(_workoutCompleted ? 'Workout Complete!' : 'Workout Summary', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reps: $_reps', style: const TextStyle(color: Colors.white, fontSize: 16)),
            const SizedBox(height: 8),
            Text('Duration: ${_formatDuration(_stopwatch.elapsed)}', style: const TextStyle(color: Colors.white, fontSize: 16)),
            const SizedBox(height: 8),
            Text('Calories Burned: ${_calories.toStringAsFixed(1)} kcal', style: const TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Exit', style: TextStyle(color: Colors.cyanAccent)),
          ),
        ],
      ),
    );
    return shouldExit ?? false;
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _poseDetector.close();
    _animationController.dispose();
    _confettiController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(appBar: AppBar(title: const Text('Pose Detector')), body: Center(child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 18), textAlign: TextAlign.center)));
    }
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return Scaffold(appBar: AppBar(title: const Text('Loading Camera...')), body: const Center(child: CircularProgressIndicator()));
    }
    final bool isIOSFrontCamera = _cameraController!.description.lensDirection == CameraLensDirection.front && defaultTargetPlatform == TargetPlatform.iOS;
    final Matrix4 cameraTransform = isIOSFrontCamera ? (Matrix4.identity()..scale(-1.0, 1.0)) : Matrix4.identity();

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final shouldExit = await _onPopInvoked();
        if (shouldExit && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('${widget.workoutType.toString().split('.').last.toUpperCase()} Tracker'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              final shouldExit = await _onPopInvoked();
              if (shouldExit && mounted) Navigator.of(context).pop();
            },
          ),
        ),
        body: Stack(
          children: [
            Positioned.fill(child: Transform(alignment: Alignment.center, transform: cameraTransform, child: AspectRatio(aspectRatio: _cameraController!.value.aspectRatio, child: CameraPreview(_cameraController!)))),
            if (_customPaint != null) Positioned.fill(child: _customPaint!),
            Positioned(
              bottom: 100,
              left: 20,
              right: 20,
              child: AnimatedOpacity(
                opacity: _feedbackOpacity,
                duration: const Duration(milliseconds: 300),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                  child: Text(_feedback, style: const TextStyle(color: Colors.yellow, fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                ),
              ),
            ),
            Positioned(
              bottom: 30,
              left: 20,
              child: AnimatedBuilder(
                animation: _bounceAnimation,
                builder: (context, child) => Transform.scale(
                  scale: _bounceAnimation.value,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                    child: Text('Reps: $_reps', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 30,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                child: Text('Time: ${_formatDuration(_stopwatch.elapsed)}', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              ),
            ),
            Positioned(
              top: 50,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                child: Text(_stage.toUpperCase(), style: TextStyle(color: _stage == 'up' || _stage == 'down' ? Colors.greenAccent : Colors.redAccent, fontSize: 20, fontWeight: FontWeight.bold)),
              ),
            ),
            Align(
              alignment: Alignment.topCenter,
              child: ConfettiWidget(
                confettiController: _confettiController,
                blastDirectionality: BlastDirectionality.explosive,
                shouldLoop: false,
                numberOfParticles: 30,
                gravity: 0.2,
                maxBlastForce: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- HELPER METHODS ---
  PoseLandmark? _getLandmark(Pose pose, PoseLandmarkType type) => pose.landmarks[type];
  double _calculateAngle(PoseLandmark p1, PoseLandmark p2, PoseLandmark p3) {
    final radians = atan2(p3.y - p2.y, p3.x - p2.x) - atan2(p1.y - p2.y, p1.x - p2.x);
    var angle = (radians * 180.0 / pi).abs();
    if (angle > 180.0) angle = 360 - angle;
    return angle;
  }
  void _updateCalories() {
    const caloriePerRep = {WorkoutType.pushups: 0.5, WorkoutType.bicepCurls: 0.3, WorkoutType.shoulderPress: 0.4, WorkoutType.squats: 0.6};
    _calories = _reps * (caloriePerRep[widget.workoutType] ?? 0.0);
  }
  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class PosePainter extends CustomPainter {
  final Pose pose;
  final Size imageSize;
  final CameraLensDirection cameraLensDirection;
  final InputImageRotation imageRotation;

  PosePainter(this.pose, this.imageSize, this.cameraLensDirection, this.imageRotation);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.lightBlueAccent
      ..strokeWidth = 5.0
      ..strokeCap = StrokeCap.round;

    final pointPaint = Paint()
      ..color = Colors.yellowAccent
      ..strokeWidth = 10.0;

    final bool shouldMirror = cameraLensDirection == CameraLensDirection.front && defaultTargetPlatform == TargetPlatform.iOS;
    
    Offset _translate(double x, double y, Size size, Size imageSize) {
      final double scaleX = size.width / imageSize.width;
      final double scaleY = size.height / imageSize.height;
      final double scale = min(scaleX, scaleY);
      final double offsetX = (size.width - imageSize.width * scale) / 2;
      final double offsetY = (size.height - imageSize.height * scale) / 2;
      return Offset(x * scale + offsetX, y * scale + offsetY);
    }
    
    final Map<PoseLandmarkType, Offset> points = {};
    pose.landmarks.forEach((type, landmark) {
      var translated = _translate(landmark.x, landmark.y, size, imageSize);
      if (shouldMirror) {
        translated = Offset(size.width - translated.dx, translated.dy);
      }
      points[type] = translated;
    });

    final connections = [
      [PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder],
      [PoseLandmarkType.leftHip, PoseLandmarkType.rightHip],
      [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip],
      [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip],
      [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow],
      [PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist],
      [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow],
      [PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist],
      [PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee],
      [PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle],
      [PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee],
      [PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle],
    ];

    for (var connection in connections) {
      final p1 = points[connection[0]];
      final p2 = points[connection[1]];
      if (p1 != null && p2 != null) {
        canvas.drawLine(p1, p2, paint);
      }
    }
    
    points.forEach((key, value) {
      canvas.drawCircle(value, 5, pointPaint);
    });
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}