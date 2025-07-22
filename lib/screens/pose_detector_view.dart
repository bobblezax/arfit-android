import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui'; // For Color, Paint
import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:tflite_flutter/tflite_flutter.dart'; // Import tflite_flutter
import 'package:flutter/services.dart'; // Add this import for MissingPluginException

import '../utils/pose_painter.dart'; // Make sure this path is correct, assuming utils folder for painter

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
  String _stage = ""; // "up" or "down" for reps (manual tracking stage)
  String _feedback = "Initializing..."; // Initial feedback state
  String? _error;
  final Stopwatch _stopwatch = Stopwatch(); // Duration tracker
  double _calories = 0.0; // Calorie estimation
  double _feedbackOpacity = 1.0; // For fade animation
  int _lastRepCount = 0; // To detect rep changes for animation
  late AnimationController _animationController; // For bounce animation
  late Animation<double> _bounceAnimation;

  // For workout completion effects
  late ConfettiController _confettiController;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _workoutCompleted = false;

  // AI Model and Form Feedback additions
  Interpreter? _interpreter;
  List<String>? _labels;
  String _currentPoseStageAI = 'standing'; // AI classified pose stage
  Map<String, String> _formFeedback = {}; // Stores feedback for each rule (e.g., 'leftElbow': 'Flared Elbow')


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
    _loadModelAndLabels(); // Load TFLite model and labels
    _stopwatch.start();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _bounceAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.elasticOut),
    );
  }

  // UPDATED _loadModelAndLabels for more specific error messages
  Future<void> _loadModelAndLabels() async {
    try {
      print('Attempting to load TFLite model from assets/pose_classifier.tflite...');
      _interpreter = await Interpreter.fromAsset('assets/pose_classifier.tflite');
      print('TFLite Model loaded successfully!');

      print('Attempting to load labels from assets/pose_labels.txt...');
      final labelFile = await DefaultAssetBundle.of(context).loadString('assets/pose_labels.txt');
      _labels = labelFile.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      print('TFLite Labels loaded successfully: $_labels');
    } catch (e) {
      print('ERROR: Failed to load TFLite model or labels. Exception: $e');
      if (e is MissingPluginException) {
        setState(() => _error = "Missing Plugin Error: Is tflite_flutter correctly installed? Run 'flutter pub get' and rebuild.");
      } else if (e is FlutterError && e.message.contains('Unable to load asset')) {
        setState(() => _error = "Asset Loading Error: 'pose_classifier.tflite' or 'pose_labels.txt' not found or accessible. Check pubspec.yaml and file path/casing.");
      } else {
        setState(() => _error = "An unexpected error occurred during model loading: $e");
      }
      debugPrintStack(); // Print the full stack trace for more details
    }
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
        if (mounted) setState(() => _error = "No cameras found.");
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
      final Uint8List nv21Bytes = _convertYUV420ToNV21(image);

      final inputImage = InputImage.fromBytes(
        bytes: nv21Bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: InputImageRotationValue.fromRawValue(_cameraController!.description.sensorOrientation) ?? InputImageRotation.rotation0deg,
          format: InputImageFormat.nv21,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );

      final poses = await _poseDetector.processImage(inputImage);
      if (poses.isNotEmpty) {
        final pose = poses.first;
        if (pose.landmarks.length < 10) { // Simple check for a "good enough" pose
          _customPaint = null;
          _feedback = "Hold still. Pose unclear.";
        } else {
          // AI Classification and Form Rule Evaluation
          _currentPoseStageAI = _classifyPoseStageAI(pose, inputImage.metadata!.size); // Pass image size
          _formFeedback = _evaluateForm(pose); // Rule-based feedback

          _customPaint = CustomPaint(
            painter: PosePainter(
              pose,
              Size(image.width.toDouble(), image.height.toDouble()),
              _cameraController!.description.lensDirection,
              InputImageRotationValue.fromRawValue(_cameraController!.description.sensorOrientation) ?? InputImageRotation.rotation0deg,
              _currentPoseStageAI, // Pass AI stage
              _formFeedback,     // Pass form feedback map
            ),
          );
          _updateWorkoutState(pose); // Update rep count based on angles
        }
      } else {
        _customPaint = null;
        _feedback = "No pose detected. Adjust your position.";
        _currentPoseStageAI = 'standing'; // Reset AI stage if no pose
        _formFeedback = {}; // Clear feedback
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("Error processing image: $e");
    } finally {
      _isDetecting = false;
    }
  }

  Uint8List _convertYUV420ToNV21(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final int ySize = width * height;
    final int uvSize = width * height ~/ 4;
    final Uint8List nv21 = Uint8List(ySize + uvSize * 2);

    final yPlane = image.planes[0].bytes;
    nv21.setRange(0, ySize, yPlane);

    final uPlane = image.planes[1].bytes;
    final vPlane = image.planes[2].bytes;
    final int uvPixelStride = image.planes[1].bytesPerPixel ?? 1;
    final int uvRowStride = image.planes[1].bytesPerRow;

    int nv21Index = ySize;
    for (int y = 0; y < height ~/ 2; y++) {
      for (int x = 0; x < width ~/ 2; x++) {
        final int uvIndex = y * uvRowStride + x * uvPixelStride;
        nv21[nv21Index++] = vPlane[uvIndex]; // V
        nv21[nv21Index++] = uPlane[uvIndex]; // U
      }
    }
    return nv21;
  }

  // --- AI Pose Classification ---
  String _classifyPoseStageAI(Pose pose, Size imageSize) { // Add imageSize parameter
    if (_interpreter == null || _labels == null) {
      debugPrint("AI model or labels not loaded. Cannot classify pose.");
      return 'standing'; // Model not loaded, default to standing
    }

    // Prepare input for the TFLite model
    final List<double> input = [];
    final double imgWidth = imageSize.width; // Use passed imageSize
    final double imgHeight = imageSize.height; // Use passed imageSize

    // Use a fixed order of landmarks as expected by your model
    final List<PoseLandmarkType> desiredLandmarksOrder = [
      PoseLandmarkType.nose, PoseLandmarkType.leftEyeInner, PoseLandmarkType.leftEye,
      PoseLandmarkType.leftEyeOuter, PoseLandmarkType.rightEyeInner, PoseLandmarkType.rightEye,
      PoseLandmarkType.rightEyeOuter, PoseLandmarkType.leftEar, PoseLandmarkType.rightEar,
      PoseLandmarkType.leftMouth, PoseLandmarkType.rightMouth, PoseLandmarkType.leftShoulder,
      PoseLandmarkType.rightShoulder, PoseLandmarkType.leftElbow, PoseLandmarkType.rightElbow,
      PoseLandmarkType.leftWrist, PoseLandmarkType.rightWrist, PoseLandmarkType.leftPinky,
      PoseLandmarkType.rightPinky, PoseLandmarkType.leftIndex, PoseLandmarkType.rightIndex,
      PoseLandmarkType.leftThumb, PoseLandmarkType.rightThumb, PoseLandmarkType.leftHip,
      PoseLandmarkType.rightHip, PoseLandmarkType.leftKnee, PoseLandmarkType.rightKnee,
      PoseLandmarkType.leftAnkle, PoseLandmarkType.rightAnkle, PoseLandmarkType.leftHeel,
      PoseLandmarkType.rightHeel, PoseLandmarkType.leftFootIndex, PoseLandmarkType.rightFootIndex
    ];

    for (final type in desiredLandmarksOrder) {
      final landmark = pose.landmarks[type];
      if (landmark != null) {
        input.add(landmark.x / imgWidth); // Normalize x
        input.add(landmark.y / imgHeight); // Normalize y
        // If your model expects confidence/score, add landmark.z or landmark.likelihood here
      } else {
        // If a landmark is missing, provide default values (e.g., 0.0)
        // This is crucial for consistent input shape.
        input.add(0.0);
        input.add(0.0);
      }
    }

    // Ensure input has the correct size (e.g., 33 landmarks * 2 coords = 66)
    // Adjust this based on your model's actual input shape
    if (input.length != 66) { // Assuming 33 landmarks * 2 coordinates per landmark (x, y)
        debugPrint("Input size mismatch for TFLite: Expected 66, got ${input.length}");
        return 'standing';
    }

    // Define the output map for multiple outputs
    // The keys are the output tensor indices.
    // We want the output that corresponds to our 9 labels.
    // Based on previous information, the [1,9] output is likely at index 0 or 1.
    // Netron (or the model's structure) would show the exact index.
    // Let's assume index 0 based on the "main" output in your screenshot.
    final Map<int, Object> outputs = {
      // The output tensor at index 0, which corresponds to the [-1, 9] output.
      // Make sure the size matches your labels count, and it's a 2D list for batch size 1.
      0: List.filled(1 * _labels!.length, 0.0).reshape([1, _labels!.length]),
    };

    try {
      _interpreter?.run(input.reshape([1, input.length]), outputs);
    } catch (e) {
      debugPrint("TFLite inference error: $e");
      return 'standing';
    }

    // Retrieve the output for the 9-class classification (assuming it's at index 0)
    final List<List<double>> outputProbabilities = outputs[0] as List<List<double>>;
    if (outputProbabilities.isEmpty || outputProbabilities[0].isEmpty) {
        debugPrint("TFLite output is empty.");
        return 'standing';
    }

    final List<double> probabilities = outputProbabilities[0]; // Get the probabilities for the first (and likely only) batch item
    int maxProbIndex = 0;
    double maxProb = 0.0;
    for (int i = 0; i < probabilities.length; i++) {
      if (probabilities[i] > maxProb) {
        maxProb = probabilities[i];
        maxProbIndex = i;
      }
    }

    // Ensure maxProbIndex is within bounds of _labels list
    if (maxProbIndex < 0 || maxProbIndex >= _labels!.length) {
      debugPrint("Error: maxProbIndex ($maxProbIndex) out of bounds for labels list (size ${_labels!.length})");
      return 'standing';
    }

    return _labels![maxProbIndex];
  }

  // --- Update Workout State & Rep Counting ---
  void _updateWorkoutState(Pose pose) {
    if (_workoutCompleted) return;

    // Determine feedback based on AI stage and form rules
    if (_formFeedback.isNotEmpty) {
      _feedback = _formFeedback.values.first; // Display the first active feedback
      _feedbackOpacity = 1.0;
      // Optional: Dim feedback after a short period
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _feedbackOpacity = 0.0);
      });
    } else {
      _feedback = "Good form!";
      _feedbackOpacity = 1.0;
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) setState(() => _feedbackOpacity = 0.0);
      });
    }

    // Rep counting logic, now relying on AI _currentPoseStageAI
    bool repIncremented = false;
    // Debug prints to see AI stage and internal stage transitions
    debugPrint("AI Stage: $_currentPoseStageAI, Current App Stage: $_stage, Reps: $_reps, Form Feedback: $_formFeedback");

    switch (widget.workoutType) {
      case WorkoutType.pushups:
        if (_currentPoseStageAI == "pushup_up") {
          _stage = "up";
          if (_formFeedback.isEmpty) _feedback = "Lower down!"; // Provide positive feedback if form is good
        } else if (_currentPoseStageAI == "pushup_down" && _stage == "up") {
          final now = DateTime.now();
          if (now.difference(_lastRepTime).inMilliseconds >= 800) {
            if (_formFeedback.isEmpty) { // Only count rep if form is good
                _lastRepTime = now;
                _stage = "down";
                _reps++;
                repIncremented = true;
                _feedback = "Push up!";
            } else {
                _feedback = _formFeedback.values.first; // Keep displaying error
            }
          }
        }
        break;
      case WorkoutType.bicepCurls:
        if (_currentPoseStageAI == "curl_down") {
          _stage = "down";
          if (_formFeedback.isEmpty) _feedback = "Curl up!";
        } else if (_currentPoseStageAI == "curl_up" && _stage == "down") {
          final now = DateTime.now();
          if (now.difference(_lastRepTime).inMilliseconds >= 800) {
            if (_formFeedback.isEmpty) {
                _lastRepTime = now;
                _stage = "up";
                _reps++;
                repIncremented = true;
                _feedback = "Lower down!";
            } else {
                _feedback = _formFeedback.values.first;
            }
          }
        }
        break;
      case WorkoutType.shoulderPress:
        if (_currentPoseStageAI == "press_up") {
          _stage = "up";
          if (_formFeedback.isEmpty) _feedback = "Lower weights!";
        } else if (_currentPoseStageAI == "press_down" && _stage == "up") {
          final now = DateTime.now();
          if (now.difference(_lastRepTime).inMilliseconds >= 800) {
            if (_formFeedback.isEmpty) {
                _lastRepTime = now;
                _stage = "down";
                _reps++;
                repIncremented = true;
                _feedback = "Press up!";
            } else {
                _feedback = _formFeedback.values.first;
            }
          }
        }
        break;
      case WorkoutType.squats:
        if (_currentPoseStageAI == "squat_up") {
          _stage = "up";
          if (_formFeedback.isEmpty) _feedback = "Squat down!";
        } else if (_currentPoseStageAI == "squat_down" && _stage == "up") {
          final now = DateTime.now();
          if (now.difference(_lastRepTime).inMilliseconds >= 800) {
            if (_formFeedback.isEmpty) {
                _lastRepTime = now;
                _stage = "down";
                _reps++;
                repIncremented = true;
                _feedback = "Stand up!";
            } else {
                _feedback = _formFeedback.values.first;
            }
          }
        }
        break;
      case WorkoutType.none:
        _feedback = "Tracking not active.";
        break;
    }

    if (repIncremented) {
      _animationController.forward().then((_) => _animationController.reverse());
      _lastRepCount = _reps; // Update last rep count for animation trigger
    }

    _updateCalories();
    if (widget.targetReps != null && _reps >= widget.targetReps!) {
      _handleWorkoutCompletion();
    }
  }

  void _handleWorkoutCompletion() {
    if (_workoutCompleted) return;
    setState(() {
      _workoutCompleted = true;
      _feedback = "Workout Complete!";
      _feedbackOpacity = 1.0;
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

  // Helper to update calories (placeholder)
  void _updateCalories() {
    // This is a simplified placeholder.
    // Calorie calculation is complex and depends on many factors:
    // User's weight, height, age, gender, exercise intensity, duration, etc.
    // For a real application, consider a more sophisticated model or API.
    _calories = _reps * 0.5; // Example: 0.5 calories per rep
    // Or based on duration for a continuous exercise:
    // _calories = _stopwatch.elapsed.inSeconds * 0.01; // Example: 0.01 kcal per second
  }

  // Helper to format duration
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }


  // --- Angle and Distance Calculation Helper Functions (moved from last response) ---

  // Calculates angle in degrees between three points (midPoint is the vertex)
  double _getAngle(PoseLandmark p1, PoseLandmark p2, PoseLandmark p3) { // Corrected type: PoseLandmark
    final double radians = atan2(p3.y - p2.y, p3.x - p2.x) - atan2(p1.y - p2.y, p1.x - p2.x);
    double angle = (radians * 180 / pi).abs();
    if (angle > 180.0) {
      angle = 360 - angle;
    }
    return angle;
  }

  // Calculates Euclidean distance between two points
  double _getDistance(PoseLandmark p1, PoseLandmark p2) {
    return sqrt(pow(p1.x - p2.x, 2) + pow(p1.y - p2.y, 2));
  }

  PoseLandmark? _getLandmark(Pose pose, PoseLandmarkType type) {
    return pose.landmarks[type];
  }

  // --- Exercise-Specific Form Rules (from last response) ---
  Map<String, String> _evaluateForm(Pose pose) {
    Map<String, String> feedback = {};

    switch (widget.workoutType) { // Evaluate based on selected workout type
      case WorkoutType.shoulderPress:
        if (_currentPoseStageAI == 'press_down') {
          feedback.addAll(_checkShoulderPressForm(pose));
        }
        break;
      case WorkoutType.bicepCurls:
        if (_currentPoseStageAI == 'curl_up') {
          feedback.addAll(_checkBicepCurlForm(pose));
        }
        break;
      case WorkoutType.squats:
        if (_currentPoseStageAI == 'squat_down') {
          feedback.addAll(_checkSquatForm(pose));
        }
        break;
      case WorkoutType.pushups:
        if (_currentPoseStageAI == 'pushup_down') {
          feedback.addAll(_checkPushupForm(pose));
        }
        break;
      case WorkoutType.none:
        // No specific form feedback for none
        break;
    }
    return feedback;
  }

  Map<String, String> _checkShoulderPressForm(Pose pose) {
    Map<String, String> feedback = {};
    final leftHip = _getLandmark(pose, PoseLandmarkType.leftHip);
    final leftShoulder = _getLandmark(pose, PoseLandmarkType.leftShoulder);
    final leftElbow = _getLandmark(pose, PoseLandmarkType.leftElbow);
    final rightHip = _getLandmark(pose, PoseLandmarkType.rightHip);
    final rightShoulder = _getLandmark(pose, PoseLandmarkType.rightShoulder);
    final rightElbow = _getLandmark(pose, PoseLandmarkType.rightElbow);

    if (leftHip != null && leftShoulder != null && leftElbow != null) {
      final angle = _getAngle(leftHip, leftShoulder, leftElbow);
      // Changed to a single range for "flared or not tucked"
      if (angle < 45 || angle > 60) {
        feedback['leftElbow'] = 'Elbows not tucked (Left)';
      }
    }

    if (rightHip != null && rightShoulder != null && rightElbow != null) {
      final angle = _getAngle(rightHip, rightShoulder, rightElbow);
      if (angle < 45 || angle > 60) {
        feedback['rightElbow'] = 'Elbows not tucked (Right)';
      }
    }
    return feedback;
  }

  Map<String, String> _checkBicepCurlForm(Pose pose) {
    Map<String, String> feedback = {};
    final leftElbow = _getLandmark(pose, PoseLandmarkType.leftElbow);
    final leftShoulder = _getLandmark(pose, PoseLandmarkType.leftShoulder);
    final rightElbow = _getLandmark(pose, PoseLandmarkType.rightElbow);
    final rightShoulder = _getLandmark(pose, PoseLandmarkType.rightShoulder);

    // Elbow Drift - check distance from elbow to torso (shoulder)
    // Using x-coordinate difference as a proxy for lateral movement
    final double thresholdPixels = 15.0; // Example threshold, needs calibration

    if (leftElbow != null && leftShoulder != null) {
      final distance = (leftElbow.x - leftShoulder.x).abs();
      if (distance > thresholdPixels) {
        feedback['leftElbowDrift'] = 'Elbow Drift (Left)';
      }
    }
    if (rightElbow != null && rightShoulder != null) {
      final distance = (rightElbow.x - rightShoulder.x).abs();
      if (distance > thresholdPixels) {
        feedback['rightElbowDrift'] = 'Elbow Drift (Right)';
      }
    }
    return feedback;
  }

  Map<String, String> _checkSquatForm(Pose pose) {
    Map<String, String> feedback = {};
    final leftKnee = _getLandmark(pose, PoseLandmarkType.leftKnee);
    final leftToe = _getLandmark(pose, PoseLandmarkType.leftFootIndex);
    final leftShoulder = _getLandmark(pose, PoseLandmarkType.leftShoulder);
    final leftHip = _getLandmark(pose, PoseLandmarkType.leftHip);

    final rightKnee = _getLandmark(pose, PoseLandmarkType.rightKnee);
    final rightToe = _getLandmark(pose, PoseLandmarkType.rightFootIndex);
    final rightShoulder = _getLandmark(pose, PoseLandmarkType.rightShoulder);
    final rightHip = _getLandmark(pose, PoseLandmarkType.rightHip);

    // Rule 1: Knees should not go more than X cm past the toes
    // Using x-coordinate difference as a proxy for lateral movement
    final double kneeToeThreshold = 20.0; // Pixels, needs calibration
    // Assuming user faces camera and x increases to the right of the screen
    // For left leg: if knee.x is much greater than toe.x -> past toes (for user facing camera from left side)
    // For right leg: if knee.x is much less than toe.x -> past toes (for user facing camera from right side)
    // This is highly dependent on camera perspective and user orientation.
    // A more robust solution might involve relative distances or 3D pose.
    // For now, let's simplify for a typical front-facing camera view or average.
    // If the person is facing perfectly straight, leftKnee.x should be slightly left of leftToe.x
    // and rightKnee.x slightly right of rightToe.x.
    // If knee.x is 'further' in the direction of the toe (i.e., past it from a side view perspective), it's wrong.
    // This is tricky for 2D. Let's assume a simplified straight-on view or average.
    // A more common 'knees past toes' check is if the knee is forward of the ankle.
    // For 2D, we can use x-coordinates, but it's an approximation.
    // Let's use the relative horizontal position.
    if (leftKnee != null && leftToe != null) {
      // If the knee's x-coordinate is significantly past the toe's x-coordinate,
      // assuming a typical frontal view where "past toes" means more to the right for left leg, more to the left for right leg.
      if ((leftKnee.x - leftToe.x).abs() > kneeToeThreshold) { // Simple distance check
        feedback['leftKneePosition'] = 'Knees past toes (Left)';
      }
    }
    if (rightKnee != null && rightToe != null) {
      if ((rightKnee.x - rightToe.x).abs() > kneeToeThreshold) {
        feedback['rightKneePosition'] = 'Knees past toes (Right)';
      }
    }


    // Rule 2: Back angle (shoulder → hip → knee) should be roughly 45°–70°
    if (leftShoulder != null && leftHip != null && leftKnee != null) {
      final backAngle = _getAngle(leftShoulder, leftHip, leftKnee);
      if (backAngle < 45 || backAngle > 70) {
        feedback['leftBackAngle'] = 'Back angle incorrect (Left)';
      }
    }
    if (rightShoulder != null && rightHip != null && rightKnee != null) {
      final backAngle = _getAngle(rightShoulder, rightHip, rightKnee);
      if (backAngle < 45 || backAngle > 70) {
        feedback['rightBackAngle'] = 'Back angle incorrect (Right)';
      }
    }
    return feedback;
  }

  Map<String, String> _checkPushupForm(Pose pose) {
    Map<String, String> feedback = {};
    final leftShoulder = _getLandmark(pose, PoseLandmarkType.leftShoulder);
    final leftHip = _getLandmark(pose, PoseLandmarkType.leftHip);
    final leftKnee = _getLandmark(pose, PoseLandmarkType.leftKnee);
    final rightShoulder = _getLandmark(pose, PoseLandmarkType.rightShoulder);
    final rightHip = _getLandmark(pose, PoseLandmarkType.rightHip);
    final rightKnee = _getLandmark(pose, PoseLandmarkType.rightKnee);

    // Rule: The angle between shoulder → hip → knee should stay near 180° for no hip sag.
    // Hip sag occurs if this angle drops to 150° or less.
    if (leftShoulder != null && leftHip != null && leftKnee != null) {
      final hipAngle = _getAngle(leftShoulder, leftHip, leftKnee);
      if (hipAngle < 150) {
        feedback['leftHipSag'] = 'Hip Sag (Left)';
      }
    }
    if (rightShoulder != null && rightHip != null && rightKnee != null) {
      final hipAngle = _getAngle(rightShoulder, rightHip, rightKnee);
      if (hipAngle < 150) {
        feedback['rightHipSag'] = 'Hip Sag (Right)';
      }
    }
    return feedback;
  }

  // --- End of Form Rules ---

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
    _interpreter?.close(); // Close the TFLite interpreter
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
            Positioned.fill(
              child: Transform(
                alignment: Alignment.center,
                transform: cameraTransform,
                child: AspectRatio(
                  aspectRatio: _cameraController!.value.aspectRatio,
                  child: CameraPreview(_cameraController!),
                ),
              ),
            ),
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
                child: Text(
                  _currentPoseStageAI.toUpperCase().replaceAll('_', ' '), // Display AI stage
                  style: TextStyle(
                    color: _currentPoseStageAI.contains('down') || _currentPoseStageAI.contains('up') ? Colors.lightGreenAccent : Colors.white70,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
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
}