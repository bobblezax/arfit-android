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

  const PoseDetectorView({Key? key, this.workoutType = WorkoutType.none}) : super(key: key);

  @override
  State<PoseDetectorView> createState() => _PoseDetectorViewState();
}

class _PoseDetectorViewState extends State<PoseDetectorView> {
  CameraController? _cameraController;
  late final PoseDetector _poseDetector;
  bool _isDetecting = false;
  CustomPaint? _customPaint;
  int _reps = 0;
  String _stage = ""; // "up" or "down" for reps
  String _feedback = "Initializing..."; // Initial feedback state
  String? _error;

  @override
  void initState() {
    super.initState();
    _poseDetector = PoseDetector(
      options: PoseDetectorOptions(
        mode: PoseDetectionMode.stream,
        model: PoseDetectionModel.accurate, // Using accurate model
      ),
    );
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final status = await Permission.camera.request();
      if (status != PermissionStatus.granted) {
        setState(() => _error = "Camera permission denied");
        return;
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = "No cameras found on device");
        return;
      }

      // Prioritize front camera for user-facing pose detection
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first, // Fallback to any camera if front is not found
      );

      _cameraController = CameraController(
        camera,
        ResolutionPreset.medium, // Using medium resolution
        enableAudio: false,
      );

      await _cameraController!.initialize();
      // Start image stream only after camera is initialized successfully
      if (_cameraController!.value.isInitialized) {
        await _cameraController!.startImageStream(_processCameraImage);
        setState(() => _feedback = "Stand in frame to begin.");
      } else {
        setState(() => _error = "Camera failed to initialize.");
      }

      setState(() => _error = null);
    } catch (e) {
      setState(() => _error = "Failed to initialize camera: $e");
    }
  }

Future<void> _processCameraImage(CameraImage image) async {
  if (_isDetecting || !mounted) return; // Throttle processing
  _isDetecting = true;

  if (_cameraController == null || !_cameraController!.value.isInitialized) {
    await Future.delayed(const Duration(milliseconds: 100));
    _isDetecting = false;
    return;
  }

  try {
    // Function to convert YUV_420_888 to a contiguous Uint8List
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

    // Convert image to NV21 format
    final bytes = _convertYUV420ToNV21(image);

    final camera = _cameraController!.description;
    final imageRotation =
        InputImageRotationValue.fromRawValue(camera.sensorOrientation) ??
            InputImageRotation.rotation0deg;

    // Use NV21 format for Android
    const inputImageFormat = InputImageFormat.nv21;

    // Log image information for debugging
    if (kDebugMode) {
      print('--- Camera Image Info ---');
      print('Image Format Raw: ${image.format.raw}');
      print('Image Width: ${image.width}, Height: ${image.height}');
      if (image.planes.isNotEmpty) {
        print('Bytes per Row (Y Plane): ${image.planes[0].bytesPerRow}');
        print('Bytes per Row (U Plane): ${image.planes[1].bytesPerRow}');
        print('Bytes per Row (V Plane): ${image.planes[2].bytesPerRow}');
      }
      print('Camera Sensor Orientation: ${camera.sensorOrientation}');
      print('Camera Lens Direction: ${camera.lensDirection}');
      print('InputImageRotation: $imageRotation');
      print('InputImageFormat (used): $inputImageFormat');
      print('Total bytes length: ${bytes.length}');
      print('Expected bytes for NV21: ${image.width * image.height * 3 ~/ 2}');
      print('--- End Camera Image Info ---');
    }

    // Verify byte length
    final expectedSize = image.width * image.height * 3 ~/ 2;
    if (bytes.length != expectedSize) {
      print('! Byte length mismatch: got ${bytes.length}, expected $expectedSize');
      _isDetecting = false;
      return;
    }

    final inputImage = InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        rotation: imageRotation,
        format: inputImageFormat,
        bytesPerRow: image.planes[0].bytesPerRow, // Y plane stride
        size: Size(image.width.toDouble(), image.height.toDouble()),
      ),
    );

    final poses = await _poseDetector.processImage(inputImage);

    if (poses.isNotEmpty) {
      final pose = poses.first;
      _customPaint = CustomPaint(
        painter: PosePainter(
          pose,
          Size(image.width.toDouble(), image.height.toDouble()),
          camera.lensDirection,
          imageRotation,
        ),
      );
      if (kDebugMode) print("Pose detected. Updating custom paint.");
      _updateWorkoutState(pose);
    } else {
      _customPaint = null;
      _feedback = "No pose detected. Adjust your position.";
      if (kDebugMode) print("No pose detected.");
    }

    if (mounted) {
      setState(() {});
    }
  } catch (e) {
    print("Error processing image: $e");
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

  double _calculateAngle(
      PoseLandmark p1, PoseLandmark p2, PoseLandmark p3) {
    final a = Offset(p1.x, p1.y);
    final b = Offset(p2.x, p2.y);
    final c = Offset(p3.x, p3.y);

    final radians = atan2(c.dy - b.dy, c.dx - b.dx) -
        atan2(a.dy - b.dy, a.dx - b.dx);
    double angle = (radians * 180.0 / pi).abs();

    if (angle > 180.0) {
      angle = 360 - angle;
    }
    return angle;
  }

  void _updateWorkoutState(Pose pose) {
    if (widget.workoutType == WorkoutType.none) {
      _feedback = "Error: Workout type not selected. Please restart.";
      return;
    }

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
        _stage = "down";
        _reps++;
        _feedback = "Stand up!";
      }
    } else {
      _feedback = "Adjust for Squats: Ensure hips, knees, and ankles are visible.";
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _poseDetector.close();
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

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.workoutType.toString().split('.').last.toUpperCase()} Tracker'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context);
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
          // Skeletal overlay
          if (_customPaint != null)
            Positioned.fill( // Ensure CustomPaint fills the screen
              child: _customPaint!,
            ),
          // Feedback text
          Positioned(
            bottom: 100,
            left: 20,
            right: 20,
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
          // Reps counter
          Positioned(
            bottom: 30,
            left: 20,
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
           // Stage indicator
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
    );
  }
}

class PosePainter extends CustomPainter {
  final Pose pose;
  final Size imageSize;
  final CameraLensDirection cameraLensDirection;
  final InputImageRotation imageRotation; // New: Pass image rotation

  // Update constructor to accept imageRotation
  PosePainter(this.pose, this.imageSize, this.cameraLensDirection, this.imageRotation);

  void _drawLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    canvas.drawLine(p1, p2, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red // Keep red for testing
      ..strokeWidth = 8.0
      ..style = PaintingStyle.stroke;

    final pointPaint = Paint()
      ..color = Colors.yellow // Keep yellow for testing
      ..strokeWidth = 12.0
      ..style = PaintingStyle.fill;

    // Remove the temporary purple circle once the skeletal overlay is correct
    // canvas.drawCircle(Offset(size.width / 2, size.height / 2), 30.0, Paint()..color = Colors.purple);


    // Determine the effective image dimensions after rotation for scaling
    // ML Kit returns coordinates based on the *rotated* image that it processed.
    // If the image was 480x640 and rotated 90deg, the ML Kit coordinates are relative to 640x480.
    double effectiveImageWidth = imageSize.width;
    double effectiveImageHeight = imageSize.height;

    if (imageRotation == InputImageRotation.rotation90deg ||
        imageRotation == InputImageRotation.rotation270deg) {
      // Swap width and height if image was rotated by 90 or 270 degrees
      effectiveImageWidth = imageSize.height;
      effectiveImageHeight = imageSize.width;
    }


    // Map landmark points to screen coordinates
    final Map<PoseLandmarkType, Offset> points = {};
    pose.landmarks.forEach((type, landmark) {
      // Scale based on the *effective* image dimensions
      double x = landmark.x * size.width / effectiveImageWidth;
      double y = landmark.y * size.height / effectiveImageHeight;

      // Adjust x-coordinate for front camera mirror effect
      if (cameraLensDirection == CameraLensDirection.front) {
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

      // Face/Head (optional, but good for completeness)
      [PoseLandmarkType.nose, PoseLandmarkType.leftEyeInner],
      [PoseLandmarkType.leftEyeInner, PoseLandmarkType.leftEye],
      [PoseLandmarkType.leftEye, PoseLandmarkType.leftEyeOuter],
      [PoseLandmarkType.leftEyeOuter, PoseLandmarkType.leftEar],
      [PoseLandmarkType.nose, PoseLandmarkType.rightEyeInner],
      [PoseLandmarkType.rightEyeInner, PoseLandmarkType.rightEye],
      [PoseLandmarkType.rightEye, PoseLandmarkType.rightEyeOuter],
      [PoseLandmarkType.rightEyeOuter, PoseLandmarkType.rightEar],
      // Connections from ear to shoulder for neck/upper body connection
      [PoseLandmarkType.leftEar, PoseLandmarkType.leftShoulder],
      [PoseLandmarkType.rightEar, PoseLandmarkType.rightShoulder],

      // Feet connections
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