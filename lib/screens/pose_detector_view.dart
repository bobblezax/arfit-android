import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:camera/camera.dart';
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
  final WorkoutType workoutType; // Pass the selected workout type

  const PoseDetectorView({super.key, this.workoutType = WorkoutType.none});

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

  @override
  void initState() {
    super.initState();
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
        if (mounted) {
          setState(() => _error = "Camera permission denied");
        }
        return;
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          setState(() => _error = "Camera failed to load");
        }
        return;
      }

      // Select front camera, fallback to first available camera
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () {
          // Explicitly return the first camera or throw an error if empty
          if (cameras.isNotEmpty) return cameras.first;
          throw Exception('No cameras available');
        },
      );

      _cameraController = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController!.initialize();
      
      if (_cameraController!.value.isInitialized) {
        await _cameraController!.startImageStream(_processCameraImage);
        if (mounted) {
          setState(() => _feedback = "Stand in frame to begin.");
        }
      } else {
        if (mounted) {
          setState(() => _error = "Camera failed to initialize.");
        }
      }

      if (mounted) {
        setState(() => _error = null);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = "Failed to initialize camera: $e");
      }
    }
  }

// Add these helper functions in _PoseDetectorViewState class
Uint8List _concatenatePlanes(List<Plane> planes) {
  final WriteBuffer allBytes = WriteBuffer();
  for (final Plane plane in planes) {
    allBytes.putUint8List(
      Uint8List.view(plane.bytes.buffer, plane.bytes.offsetInBytes, plane.bytes.lengthInBytes),
    );
  }
  return allBytes.done().buffer.asUint8List();
}

Uint8List _convertYUV420ToNV21(CameraImage image) {
  final int width = image.width;
  final int height = image.height;

  // Calculate expected sizes
  final int ySize = width * height; // Y plane size
  final int uvSize = (width ~/ 2) * (height ~/ 2); // U and V planes (subsampled)

  final Uint8List yuvBytes = Uint8List(ySize + 2 * uvSize); // NV21 format: Y + interleaved UV

  // Y plane: Copy directly, accounting for stride
  int index = 0;
  final yPlane = image.planes[0];
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      yuvBytes[index++] = yPlane.bytes[y * yPlane.bytesPerRow + x];
    }
  }

  // UV planes: Interleave U and V (NV21 format expects VU order)
  final uPlane = image.planes[1];
  final vPlane = image.planes[2];
  for (int y = 0; y < height ~/ 2; y++) {
    for (int x = 0; x < width ~/ 2; x++) {
      // NV21: VU interleaved
      yuvBytes[index++] = vPlane.bytes[y * vPlane.bytesPerRow + x];
      yuvBytes[index++] = uPlane.bytes[y * uPlane.bytesPerRow + x];
    }
  }

  return yuvBytes;
}

// Ensure _processCameraImage uses these functions (this is the reverted version from my previous response)
Future<void> _processCameraImage(CameraImage image) async {
  if (_isDetecting || !mounted) return;
  _isDetecting = true;

  if (_cameraController == null || !_cameraController!.value.isInitialized) {
    await Future.delayed(const Duration(milliseconds: 100));
    _isDetecting = false;
    return;
  }

  try {
    // Determine platform and process image accordingly
    late Uint8List bytes;
    late InputImageFormat inputImageFormat;
    late int expectedSize;

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // iOS: Use BGRA8888
      inputImageFormat = InputImageFormat.bgra8888;
      bytes = _concatenatePlanes(image.planes);
      expectedSize = image.width * image.height * 4; // 4 bytes per pixel
    } else {
      // Android: Convert YUV_420_888 to NV21
      inputImageFormat = InputImageFormat.nv21;
      bytes = _convertYUV420ToNV21(image);
      expectedSize = image.width * image.height * 3 ~/ 2; // 1.5 bytes per pixel
    }

    if (kDebugMode) {
      debugPrint('--- Camera Image Info ---');
      debugPrint('Image Format Raw: ${image.format.raw}');
      debugPrint('Image Width: ${image.width}, Height: ${image.height}');
      if (image.planes.isNotEmpty) {
        debugPrint('Bytes per Row (Plane 0): ${image.planes[0].bytesPerRow}');
        if (image.planes.length > 1) {
          debugPrint('Bytes per Row (Plane 1): ${image.planes[1].bytesPerRow}');
          debugPrint('Bytes per Row (Plane 2): ${image.planes[2].bytesPerRow}');
        }
      }
      debugPrint('Camera Sensor Orientation: ${_cameraController!.description.sensorOrientation}');
      debugPrint('Camera Lens Direction: ${_cameraController!.description.lensDirection}');
      debugPrint('InputImageRotation: ${InputImageRotationValue.fromRawValue(_cameraController!.description.sensorOrientation)}');
      debugPrint('InputImageFormat (used): $inputImageFormat');
      debugPrint('Total bytes length: ${bytes.length}');
      debugPrint('Expected bytes: $expectedSize');
      debugPrint('--- End Camera Image Info ---');
    }

    if (bytes.length != expectedSize) {
      debugPrint('Byte length mismatch: got ${bytes.length}, expected $expectedSize');
      _isDetecting = false;
      return;
    }

    final inputImage = InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        rotation: InputImageRotationValue.fromRawValue(_cameraController!.description.sensorOrientation) ?? InputImageRotation.rotation0deg,
        format: inputImageFormat,
        bytesPerRow: image.planes[0].bytesPerRow,
        size: Size(image.width.toDouble(), image.height.toDouble()),
      ),
    );

    final poses = await _poseDetector.processImage(inputImage);

    if (poses.isNotEmpty) {
      final pose = poses.first;
      if (pose.landmarks.length < 10) {
        _customPaint = null;
        _feedback = "Hold still. Pose unclear.";
        if (mounted) setState(() {});
        _isDetecting = false;
        return;
      }
      _customPaint = CustomPaint(
        painter: PosePainter(
          pose,
          Size(image.width.toDouble(), image.height.toDouble()),
          _cameraController!.description.lensDirection,
          InputImageRotationValue.fromRawValue(_cameraController!.description.sensorOrientation) ?? InputImageRotation.rotation0deg,
        ),
      );
      if (kDebugMode) debugPrint("Pose detected. Updating custom paint.");
      _updateWorkoutState(pose);
    } else {
      _customPaint = null;
      _feedback = "No pose detected. Adjust your position.";
      if (kDebugMode) debugPrint("No pose detected.");
    }

    if (mounted) {
      setState(() {});
    }
  } catch (e) {
    debugPrint("Error processing image: $e");
    if (mounted) {
      setState(() {
        _feedback = "Error processing image: $e";
      });
    }
  } finally {
    _isDetecting = false;
  }
}

  PoseLandmark? _getLandmark(Pose pose, PoseLandmarkType type) {
    return pose.landmarks[type];
  }

  double _calculateAngle(PoseLandmark p1, PoseLandmark p2, PoseLandmark p3) {
    final a = Offset(p1.x, p1.y);
    final b = Offset(p2.x, p2.y);
    final c = Offset(p3.x, p3.y);
    final radians = atan2(c.dy - b.dy, c.dx - b.dx) - atan2(a.dy - b.dy, a.dx - b.dx);
    var angle = (radians * 180.0 / pi).abs();
    if (angle > 180.0) {
      angle = 360 - angle;
    }
    return angle;
  }

  void _updateCalories() {
    const caloriePerRep = {
      WorkoutType.pushups: 0.5,
      WorkoutType.bicepCurls: 0.3,
      WorkoutType.shoulderPress: 0.4,
      WorkoutType.squats: 0.6,
    };
    final caloriesPerRep = caloriePerRep[widget.workoutType] ?? 0.0;
    _calories = _reps * caloriesPerRep;
  }

  void _updateWorkoutState(Pose pose) {
    if (widget.workoutType == WorkoutType.none) {
      _feedback = "Error: Workout type not selected. Please restart.";
      return;
    }

    if (mounted) {
      setState(() {
        _feedbackOpacity = 0.0;
      });
    }
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        setState(() {
          _feedbackOpacity = 1.0;
        });
      }
    });

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
        _feedback = "Tracking not active. Please select a workout.";
        break;
    }
  }

  void _trackPushups(Pose pose) {
    final lShoulder = _getLandmark(pose, PoseLandmarkType.leftShoulder);
    final lElbow = _getLandmark(pose, PoseLandmarkType.leftElbow);
    final lWrist = _getLandmark(pose, PoseLandmarkType.leftWrist);
    final rShoulder = _getLandmark(pose, PoseLandmarkType.rightShoulder);
    final rElbow = _getLandmark(pose, PoseLandmarkType.rightElbow);
    final rWrist = _getLandmark(pose, PoseLandmarkType.rightWrist);
    final lHip = _getLandmark(pose, PoseLandmarkType.leftHip);
    final lAnkle = _getLandmark(pose, PoseLandmarkType.leftAnkle);

    if (lShoulder != null && lElbow != null && lWrist != null &&
        rShoulder != null && rElbow != null && rWrist != null &&
        lHip != null && lAnkle != null) {
      final leftArmAngle = _calculateAngle(lShoulder, lElbow, lWrist);
      final rightArmAngle = _calculateAngle(rShoulder, rElbow, rWrist);
      final backAngle = _calculateAngle(lShoulder, lHip, lAnkle);

      if (leftArmAngle > 160 && rightArmAngle > 160 && backAngle > 150) {
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
      }
    } else {
      _feedback = "Adjust for Push-Ups: Ensure elbows, shoulders, hips, and ankles are visible.";
    }
  }

  void _trackBicepCurls(Pose pose) {
    final lShoulder = _getLandmark(pose, PoseLandmarkType.leftShoulder);
    final lElbow = _getLandmark(pose, PoseLandmarkType.leftElbow);
    final lWrist = _getLandmark(pose, PoseLandmarkType.leftWrist);
    final rShoulder = _getLandmark(pose, PoseLandmarkType.rightShoulder);
    final rElbow = _getLandmark(pose, PoseLandmarkType.rightElbow);
    final rWrist = _getLandmark(pose, PoseLandmarkType.rightWrist);

    if (lShoulder != null && lElbow != null && lWrist != null &&
        rShoulder != null && rElbow != null && rWrist != null) {
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
      }
    } else {
      _feedback = "Adjust for Bicep Curls: Ensure shoulders, elbows, and wrists are visible.";
    }
  }

  void _trackShoulderPress(Pose pose) {
    final lShoulder = _getLandmark(pose, PoseLandmarkType.leftShoulder);
    final lElbow = _getLandmark(pose, PoseLandmarkType.leftElbow);
    final lWrist = _getLandmark(pose, PoseLandmarkType.leftWrist);
    final rShoulder = _getLandmark(pose, PoseLandmarkType.rightShoulder);
    final rElbow = _getLandmark(pose, PoseLandmarkType.rightElbow);
    final rWrist = _getLandmark(pose, PoseLandmarkType.rightWrist);

    if (lShoulder != null && lElbow != null && lWrist != null &&
        rShoulder != null && rElbow != null && rWrist != null) {
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
      }
    } else {
      _feedback = "Adjust for Shoulder Press: Ensure shoulders, elbows, and wrists are visible.";
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
      }
    } else {
      _feedback = "Adjust for Squats: Ensure hips, knees, and ankles are visible.";
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<bool> _onPopInvoked() async {
    _stopwatch.stop();
    _updateCalories();
    if (mounted) {
      setState(() {});
    }
    if (kDebugMode) {
      debugPrint('--- Workout Summary Data ---');
      debugPrint('Workout Type: ${widget.workoutType.toString().split('.').last.toUpperCase()}');
      debugPrint('Reps: $_reps');
      debugPrint('Duration: ${_formatDuration(_stopwatch.elapsed)}');
      debugPrint('Calories: ${_calories.toStringAsFixed(1)} kcal');
      debugPrint('--- End Workout Summary Data ---');
    }

    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'Workout Summary',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Container(
          constraints: const BoxConstraints(maxHeight: 200),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Workout: ${widget.workoutType.toString().split('.').last.toUpperCase()}',
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  'Reps: $_reps',
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  'Duration: ${_formatDuration(_stopwatch.elapsed)}',
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  'Calories Burned: ${_calories.toStringAsFixed(1)} kcal',
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _stopwatch.start();
              Navigator.of(context).pop(false);
            },
            child: const Text(
              'Continue',
              style: TextStyle(color: Colors.cyanAccent),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Exit',
              style: TextStyle(color: Colors.cyanAccent),
            ),
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pose Detector')),
        body: Center(
          child: Text(
            _error!,
            style: const TextStyle(color: Colors.red, fontSize: 18),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return Scaffold(
        appBar: AppBar(title: const Text('Loading Camera...')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return PopScope(
      canPop: false, // Prevent default pop until dialog is resolved
      onPopInvoked: (didPop) async {
        if (didPop) return; // Skip if already popped
        final shouldExit = await _onPopInvoked();
        if (shouldExit && mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('${widget.workoutType.toString().split('.').last.toUpperCase()} Tracker'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              final shouldExit = await _onPopInvoked();
              if (shouldExit && mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: AspectRatio(
                aspectRatio: _cameraController!.value.aspectRatio,
                child: CameraPreview(_cameraController!),
              ),
            ),
            if (_customPaint != null)
              Positioned.fill(
                child: _customPaint!,
              ),
            Positioned(
              bottom: 100,
              left: 20,
              right: 20,
              child: AnimatedOpacity(
                opacity: _feedbackOpacity,
                duration: const Duration(milliseconds: 300),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _feedback,
                    style: const TextStyle(
                      color: Colors.yellow,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
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
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Reps: $_reps',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 30,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Time: ${_formatDuration(_stopwatch.elapsed)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 50,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _stage.toUpperCase(),
                  style: TextStyle(
                    color: _stage == 'up' || _stage == 'down' ? Colors.greenAccent : Colors.redAccent,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PosePainter extends CustomPainter {
  final Pose pose;
  final Size imageSize;
  final CameraLensDirection cameraLensDirection;
  final InputImageRotation imageRotation;

  PosePainter(this.pose, this.imageSize, this.cameraLensDirection, this.imageRotation);

  void _drawLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    canvas.drawLine(p1, p2, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [Colors.blueAccent, Colors.purpleAccent],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..strokeWidth = 5.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final pointPaint = Paint()
      ..color = Colors.cyanAccent
      ..strokeWidth = 10.0
      ..style = PaintingStyle.fill;

    // Mirror x-coordinates for front-facing camera on iOS
    final bool shouldMirror = cameraLensDirection == CameraLensDirection.front &&
        defaultTargetPlatform == TargetPlatform.iOS;

    // Determine effective image dimensions after rotation
    double effectiveImageWidth = imageSize.width;
    double effectiveImageHeight = imageSize.height;

    if (imageRotation == InputImageRotation.rotation90deg ||
        imageRotation == InputImageRotation.rotation270deg) {
      effectiveImageWidth = imageSize.height;
      effectiveImageHeight = imageSize.width;
    }

    // Map landmark points to screen coordinates
    final Map<PoseLandmarkType, Offset> points = {};
    pose.landmarks.forEach((type, landmark) {
      // Scale based on the effective image dimensions
      double x = landmark.x * size.width / effectiveImageWidth;
      double y = landmark.y * size.height / effectiveImageHeight;

      // Flip x-coordinate for front-facing camera on iOS
      if (shouldMirror) {
        x = size.width - x;
      }

      points[type] = Offset(x, y);
    });

    // Define connections for the skeletal overlay
    final connections = [
      // Torso
      [PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder],
      [PoseLandmarkType.leftHip, PoseLandmarkType.rightHip],
      [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip],
      [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip],
      // Left Arm
      [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow],
      [PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist],
      // Right Arm
      [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow],
      [PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist],
      // Left Leg
      [PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee],
      [PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle],
      // Right Leg
      [PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee],
      [PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle],
      // Face/Head
      [PoseLandmarkType.nose, PoseLandmarkType.leftEyeInner],
      [PoseLandmarkType.leftEyeInner, PoseLandmarkType.leftEye],
      [PoseLandmarkType.leftEye, PoseLandmarkType.leftEyeOuter],
      [PoseLandmarkType.leftEyeOuter, PoseLandmarkType.leftEar],
      [PoseLandmarkType.nose, PoseLandmarkType.rightEyeInner],
      [PoseLandmarkType.rightEyeInner, PoseLandmarkType.rightEye],
      [PoseLandmarkType.rightEye, PoseLandmarkType.rightEyeOuter],
      [PoseLandmarkType.rightEyeOuter, PoseLandmarkType.rightEar],
      [PoseLandmarkType.leftEar, PoseLandmarkType.leftShoulder],
      [PoseLandmarkType.rightEar, PoseLandmarkType.rightShoulder],
      // Feet
      [PoseLandmarkType.leftAnkle, PoseLandmarkType.leftHeel],
      [PoseLandmarkType.leftHeel, PoseLandmarkType.leftFootIndex],
      [PoseLandmarkType.rightAnkle, PoseLandmarkType.rightHeel],
      [PoseLandmarkType.rightHeel, PoseLandmarkType.rightFootIndex],
    ];

    // Draw skeleton lines
    for (var connection in connections) {
      final p1 = points[connection[0]];
      final p2 = points[connection[1]];
      if (p1 != null && p2 != null) {
        _drawLine(canvas, p1, p2, paint);
      }
    }

    // Draw landmarks as circles
    for (final point in points.values) {
      canvas.drawCircle(point, 4, pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}