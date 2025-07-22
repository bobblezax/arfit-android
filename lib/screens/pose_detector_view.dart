import 'dart:async';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:ui' as ui; // Import specifically for UI operations like ParagraphBuilder

// Enum to define different workout types
enum WorkoutType {
  pushups,
  bicepCurls,
  shoulderPress,
  squats,
  none,
}

// Enum to define form feedback status
enum FormStatus {
  good,
  borderline,
  incorrect,
  none, // For parts not under specific form checks
}

// Updated: Class to hold form feedback AND angle values
class FormFeedback {
  // Form status for each rule
  FormStatus shoulderElbowAngleStatus = FormStatus.none; // For Shoulder Press
  FormStatus elbowTorsoDistanceStatus = FormStatus.none; // For Bicep Curl
  FormStatus kneeToePositionStatus = FormStatus.none; // For Squat
  FormStatus backAngleStatus = FormStatus.none; // For Squat
  FormStatus hipSagAngleStatus = FormStatus.none; // For Pushup

  // Actual angle/distance values to display
  double shoulderElbowAngleValue = 0.0;
  double elbowTorsoDistanceValue = 0.0; // Using normalized pixel value or similar
  double kneeToePositionValue = 0.0; // Using normalized pixel value or similar
  double backAngleValue = 0.0;
  double hipSagAngleValue = 0.0;

  // Add more as you extend to other exercises/rules
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

  late ConfettiController _confettiController;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _workoutCompleted = false;

  FormFeedback _formFeedback = FormFeedback(); // Now stores angles too
  Timer? _feedbackFadeTimer;

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

  Uint8List _convertYUV420ToNV21(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final int ySize = width * height;
    final int uvSize = ySize ~/ 2;

    final Uint8List nv21 = Uint8List(ySize + uvSize);

    // Copy Y plane
    final Uint8List yPlane = image.planes[0].bytes;
    nv21.setRange(0, ySize, yPlane);

    // Safely interleave V and U data
    final Uint8List uPlane = image.planes[1].bytes;
    final Uint8List vPlane = image.planes[2].bytes;

    int uvIndex = ySize;
    int uLen = uPlane.length;
    int vLen = vPlane.length;
    int len = (uLen < vLen ? uLen : vLen);

    for (int i = 0; i < len && (uvIndex + 1) < nv21.length; i++) {
      nv21[uvIndex++] = vPlane[i];
      nv21[uvIndex++] = uPlane[i];
    }

    return nv21;
  }

Future<void> _processCameraImage(CameraImage image) async {
  if (_isDetecting || !mounted || _cameraController == null || !_cameraController!.value.isInitialized) return;
  _isDetecting = true;

  try {
    // Step 1: Determine image rotation
    final InputImageRotation imageRotation =
        InputImageRotationValue.fromRawValue(_cameraController!.description.sensorOrientation) ??
        InputImageRotation.rotation0deg;

    // Step 2: Convert YUV_420_888 to NV21 (Android-friendly format)
    final Uint8List nv21Bytes = _convertYUV420ToNV21(image);

    // Step 3: Build InputImage
    final inputImage = InputImage.fromBytes(
      bytes: nv21Bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: imageRotation,
        format: InputImageFormat.nv21,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );

    // Step 4: Run pose detection
    final poses = await _poseDetector.processImage(inputImage);
    if (poses.isNotEmpty) {
      final pose = poses.first;
      if (pose.landmarks.length < 10) {
        _customPaint = null;
        _feedback = "Hold still. Pose unclear.";
        _stage = "unclear_pose";
        _formFeedback = FormFeedback(); // Reset form feedback
      } else {
        _customPaint = CustomPaint(
          painter: PosePainter(
            pose,
            Size(image.width.toDouble(), image.height.toDouble()),
            _cameraController!.description.lensDirection,
            imageRotation,
            _formFeedback,
          ),
        );
        _updateWorkoutState(pose);
      }
    } else {
      _customPaint = null;
      _feedback = "No pose detected. Adjust your position.";
      _stage = "no_pose";
      _formFeedback = FormFeedback(); // Reset form feedback
    }

    if (mounted) setState(() {});
  } catch (e) {
    debugPrint("Error processing camera image: $e");
  } finally {
    _isDetecting = false;
  }
}

  @override
  void dispose() {
    _cameraController?.dispose();
    _poseDetector.close();
    _animationController.dispose();
    _confettiController.dispose();
    _audioPlayer.dispose();
    _feedbackFadeTimer?.cancel();
    super.dispose();
  }

  // --- REPS TRACKING LOGIC (ORIGINAL STABLE CODE REINTEGRATED) ---
  void _updateWorkoutState(Pose pose) {
    if (_workoutCompleted) return;

    if (widget.workoutType == WorkoutType.none) {
      _feedback = "Error: Workout type not selected.";
      return;
    }

    if (_reps > _lastRepCount) {
      _animationController.forward().then((_) => _animationController.reverse()); // Corrected line
      _lastRepCount = _reps;
    }

    _updateCalories();

    // Reset form feedback for current frame before applying new rules
    _formFeedback = FormFeedback();

    // Rep tracking and stage determination
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

    // Apply form rules based on the newly determined _stage
    _applyFormRules(pose, _stage);
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
      if (!mounted) return;
      final shouldExit = await _onPopInvoked(true);
      if (shouldExit && mounted) {
        Navigator.of(context).pop();
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
    final rHip = _getLandmark(pose, PoseLandmarkType.rightHip);
    final rKnee = _getLandmark(pose, PoseLandmarkType.rightKnee);
    final rAnkle = _getLandmark(pose, PoseLandmarkType.rightAnkle);

    if (lHip != null && lKnee != null && lAnkle != null && rHip != null && rKnee != null && rAnkle != null) {
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

  // --- FORM RULES IMPLEMENTATION ---
  // These will now check based on the angle-derived _stage and update FormFeedback
  void _applyFormRules(Pose pose, String currentRepStage) {
    switch (widget.workoutType) {
      case WorkoutType.shoulderPress:
        _checkShoulderPressForm(pose, currentRepStage);
        break;
      case WorkoutType.bicepCurls:
        _checkBicepCurlForm(pose, currentRepStage);
        break;
      case WorkoutType.squats:
        _checkSquatForm(pose, currentRepStage);
        break;
      case WorkoutType.pushups:
        _checkPushupForm(pose, currentRepStage);
        break;
      case WorkoutType.none:
        // No form checking for 'none' workout type
        break;
    }
  }

  void _setFeedback(String newFeedback, {bool isFormError = false}) {
    if (isFormError) {
      _feedback = newFeedback;
      _feedbackOpacity = 1.0;
    } else if (_feedback.startsWith("Adjust:") || _feedback.startsWith("Error:") || _feedback == "Hold still. Pose unclear." || _feedback == "No pose detected. Adjust your position.") {
      _feedback = newFeedback;
      _feedbackOpacity = 1.0;
    } else { // Only overwrite if newFeedback is a general cue AND not conflicting with existing critical feedback
      // Prioritize actionable rep guidance over general feedback
      if (!newFeedback.startsWith("Adjust:") && !newFeedback.contains("!") && _feedback.contains("!")) {
        // Keep existing actionable feedback unless it's a new error.
      } else {
        _feedback = newFeedback;
        _feedbackOpacity = 1.0;
      }
    }
    _fadeFeedback();
  }

  void _fadeFeedback() {
    _feedbackFadeTimer?.cancel();
    _feedbackFadeTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _feedbackOpacity = 0.0;
        });
      }
    });
  }

  // Shoulder Press: Flared Elbows
  void _checkShoulderPressForm(Pose pose, String currentRepStage) {
    _formFeedback.shoulderElbowAngleStatus = FormStatus.none; // Reset for current frame
    _formFeedback.shoulderElbowAngleValue = 0.0; // Reset value

    if (currentRepStage == "down") { // Check when arms are in the "down" position (at shoulder level)
      final lHip = _getLandmark(pose, PoseLandmarkType.leftHip);
      final lShoulder = _getLandmark(pose, PoseLandmarkType.leftShoulder);
      final lElbow = _getLandmark(pose, PoseLandmarkType.leftElbow);
      final rHip = _getLandmark(pose, PoseLandmarkType.rightHip);
      final rShoulder = _getLandmark(pose, PoseLandmarkType.rightShoulder);
      final rElbow = _getLandmark(pose, PoseLandmarkType.rightElbow);

      if (lHip != null && lShoulder != null && lElbow != null &&
          rHip != null && rShoulder != null && rElbow != null) {
        final leftElbowAngle = _calculateAngle(lHip, lShoulder, lElbow);
        final rightElbowAngle = _calculateAngle(rHip, rShoulder, rElbow);

        final avgElbowAngle = (leftElbowAngle + rightElbowAngle) / 2;
        _formFeedback.shoulderElbowAngleValue = avgElbowAngle; // Store for display

        if (avgElbowAngle >= 80) { // Flared: 80-90+ degrees
          _formFeedback.shoulderElbowAngleStatus = FormStatus.incorrect;
          _setFeedback("Adjust: Elbows are flaring out!", isFormError: true);
        } else if (avgElbowAngle >= 60 && avgElbowAngle < 80) { // Borderline: 60-80
          _formFeedback.shoulderElbowAngleStatus = FormStatus.borderline;
          _setFeedback("Hint: Try to tuck elbows slightly.", isFormError: true);
        } else { // Good: 45-60
          _formFeedback.shoulderElbowAngleStatus = FormStatus.good;
        }
      } else {
        _setFeedback("Adjust: Ensure torso, shoulders, and elbows are visible for form check.", isFormError: true);
      }
    }
  }

  // Bicep Curl: Elbow Drift
  void _checkBicepCurlForm(Pose pose, String currentRepStage) {
    _formFeedback.elbowTorsoDistanceStatus = FormStatus.none; // Reset status
    _formFeedback.elbowTorsoDistanceValue = 0.0; // Reset value

    if (currentRepStage == "up") { // Check during the "up" position (elbows flexed)
      final lElbow = _getLandmark(pose, PoseLandmarkType.leftElbow);
      final lShoulder = _getLandmark(pose, PoseLandmarkType.leftShoulder);
      final rElbow = _getLandmark(pose, PoseLandmarkType.rightElbow);
      final rShoulder = _getLandmark(pose, PoseLandmarkType.rightShoulder);
      final lHip = _getLandmark(pose, PoseLandmarkType.leftHip);
      final rHip = _getLandmark(pose, PoseLandmarkType.rightHip);

      if (lElbow != null && lShoulder != null && rElbow != null && rShoulder != null && lHip != null && rHip != null) {
        final double midShoulderX = (lShoulder.x + rShoulder.x) / 2;
        final double midHipX = (lHip.x + rHip.x) / 2;
        final double avgTorsoX = (midShoulderX + midHipX) / 2;

        final double leftElbowXDrift = (lElbow.x - avgTorsoX).abs();
        final double rightElbowXDrift = (rElbow.x - avgTorsoX).abs();

        final double avgElbowXDrift = (leftElbowXDrift + rightElbowXDrift) / 2;
        _formFeedback.elbowTorsoDistanceValue = avgElbowXDrift; // Store for display

        final double shoulderWidth = _calculateDistance(lShoulder, rShoulder);
        const double maxNormalizedDrift = 0.08;

        if (avgElbowXDrift > (shoulderWidth * maxNormalizedDrift * 1.5)) {
          _formFeedback.elbowTorsoDistanceStatus = FormStatus.incorrect;
          _setFeedback("Adjust: Keep elbows tucked in!", isFormError: true);
        } else if (avgElbowXDrift > (shoulderWidth * maxNormalizedDrift)) {
          _formFeedback.elbowTorsoDistanceStatus = FormStatus.borderline;
          _setFeedback("Hint: Elbows drifting, keep them stable.", isFormError: true);
        } else {
          _formFeedback.elbowTorsoDistanceStatus = FormStatus.good;
        }
      } else {
        _setFeedback("Adjust: Ensure shoulders, elbows, and hips are visible for form check.", isFormError: true);
      }
    }
  }

  // Squats: Knee Position & Back Angle
  void _checkSquatForm(Pose pose, String currentRepStage) {
    _formFeedback.kneeToePositionStatus = FormStatus.none; // Reset status
    _formFeedback.kneeToePositionValue = 0.0; // Reset value
    _formFeedback.backAngleStatus = FormStatus.none; // Reset status
    _formFeedback.backAngleValue = 0.0; // Reset value

    if (currentRepStage == "down") { // Check during the "down" position (squatting)
      final lHip = _getLandmark(pose, PoseLandmarkType.leftHip);
      final lKneeRaw = _getLandmark(pose, PoseLandmarkType.leftKnee);
      final lAnkleRaw = _getLandmark(pose, PoseLandmarkType.leftAnkle);
      final lToeRaw = _getLandmark(pose, PoseLandmarkType.leftFootIndex);
      final rHip = _getLandmark(pose, PoseLandmarkType.rightHip);
      final rKneeRaw = _getLandmark(pose, PoseLandmarkType.rightKnee);
      final rAnkleRaw = _getLandmark(pose, PoseLandmarkType.rightAnkle);
      final rToeRaw = _getLandmark(pose, PoseLandmarkType.rightFootIndex);
      final lShoulder = _getLandmark(pose, PoseLandmarkType.leftShoulder);
      final rShoulder = _getLandmark(pose, PoseLandmarkType.rightShoulder);

      // Rule 1: Knees should not go more than X cm past the toes
      if ((lKneeRaw != null && lToeRaw != null && lAnkleRaw != null) && (rKneeRaw != null && rToeRaw != null && rAnkleRaw != null)) {
        double leftKneeOverToe = 0.0;
        double rightKneeOverToe = 0.0;

        leftKneeOverToe = lKneeRaw.x - lToeRaw.x;
        rightKneeOverToe = rKneeRaw.x - rToeRaw.x;

        final avgKneeOverToe = (leftKneeOverToe + rightKneeOverToe) / 2;
        _formFeedback.kneeToePositionValue = avgKneeOverToe; // Store for display

        const double kneeOverToeThreshold = 20.0; // Example pixel threshold

        if (avgKneeOverToe > kneeOverToeThreshold * 1.5) {
          _formFeedback.kneeToePositionStatus = FormStatus.incorrect;
          _setFeedback("Adjust: Knees are too far forward!", isFormError: true);
        } else if (avgKneeOverToe > kneeOverToeThreshold) {
          _formFeedback.kneeToePositionStatus = FormStatus.borderline;
          _setFeedback("Hint: Push hips back more, keep knees behind toes.", isFormError: true);
        } else {
          _formFeedback.kneeToePositionStatus = FormStatus.good;
        }
      } else {
          _setFeedback("Adjust: Ensure knees, ankles, and toes are visible for squat form.", isFormError: true);
      }

      // Rule 2: Back angle (shoulder → hip → knee) should be roughly 45°–70°
      if (lShoulder != null && lHip != null && lKneeRaw != null &&
          rShoulder != null && rHip != null && rKneeRaw != null) {
        final leftBackAngle = _calculateAngle(lShoulder, lHip, lKneeRaw);
        final rightBackAngle = _calculateAngle(rShoulder, rHip, rKneeRaw);
        final avgBackAngle = (leftBackAngle + rightBackAngle) / 2;
        _formFeedback.backAngleValue = avgBackAngle; // Store for display

        if (avgBackAngle < 40 || avgBackAngle > 75) {
          _formFeedback.backAngleStatus = FormStatus.incorrect;
          _setFeedback("Adjust: Maintain a neutral back angle (45-70°).", isFormError: true);
        } else if (avgBackAngle < 45 || avgBackAngle > 70) {
          _formFeedback.backAngleStatus = FormStatus.borderline;
          _setFeedback("Hint: Adjust your back angle slightly.", isFormError: true);
        } else {
          _formFeedback.backAngleStatus = FormStatus.good;
        }
      } else {
          _setFeedback("Adjust: Ensure shoulders, hips, and knees are visible for back angle.", isFormError: true);
      }
    }
  }

  // Pushups: Hip Sag
  void _checkPushupForm(Pose pose, String currentRepStage) {
    _formFeedback.hipSagAngleStatus = FormStatus.none; // Reset status
    _formFeedback.hipSagAngleValue = 0.0; // Reset value

    if (currentRepStage == "down") { // Check during the "down" position (chest near floor)
      final lShoulder = _getLandmark(pose, PoseLandmarkType.leftShoulder);
      final lHip = _getLandmark(pose, PoseLandmarkType.leftHip);
      final lKnee = _getLandmark(pose, PoseLandmarkType.leftKnee);
      final rShoulder = _getLandmark(pose, PoseLandmarkType.rightShoulder);
      final rHip = _getLandmark(pose, PoseLandmarkType.rightHip);
      final rKnee = _getLandmark(pose, PoseLandmarkType.rightKnee);

      if (lShoulder != null && lHip != null && lKnee != null &&
          rShoulder != null && rHip != null && rKnee != null) {
        final leftHipAngle = _calculateAngle(lShoulder, lHip, lKnee);
        final rightHipAngle = _calculateAngle(rShoulder, rHip, rKnee);
        final avgHipAngle = (leftHipAngle + rightHipAngle) / 2;
        _formFeedback.hipSagAngleValue = avgHipAngle; // Store for display

        if (avgHipAngle < 150) { // Significant sag (ideal is near 180)
          _formFeedback.hipSagAngleStatus = FormStatus.incorrect;
          _setFeedback("Adjust: Don't let your hips sag!", isFormError: true);
        } else if (avgHipAngle < 165) { // Borderline sag (allowing slight deviation from 180)
          _formFeedback.hipSagAngleStatus = FormStatus.borderline;
          _setFeedback("Hint: Keep your body straight, engage core.", isFormError: true);
        } else {
          _formFeedback.hipSagAngleStatus = FormStatus.good;
        }
      } else {
        _setFeedback("Adjust: Ensure shoulders, hips, and knees are visible for hip sag.", isFormError: true);
      }
    }
  }

  // --- HELPER METHODS ---
  PoseLandmark? _getLandmark(Pose pose, PoseLandmarkType type) => pose.landmarks[type];

  double _calculateAngle(PoseLandmark p1, PoseLandmark p2, PoseLandmark p3) {
    final radians = atan2(p3.y - p2.y, p3.x - p2.x) - atan2(p1.y - p2.y, p1.x - p2.x);
    var angle = (radians * 180.0 / pi).abs();
    if (angle > 180.0) angle = 360 - angle;
    return angle;
  }

  double _calculateDistance(PoseLandmark p1, PoseLandmark p2) {
    return sqrt(pow(p1.x - p2.x, 2) + pow(p1.y - p2.y, 2));
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

  Future<bool> _onPopInvoked([bool force = false]) async {
    if (!mounted) return false;

    if (_workoutCompleted || force) {
      _stopwatch.stop();
      _updateCalories();
      if (mounted) setState(() {});

      final bool? result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
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
              onPressed: () {
                if (mounted && Navigator.of(dialogContext).mounted) {
                  Navigator.of(dialogContext).pop(true);
                }
              },
              child: const Text('Exit', style: TextStyle(color: Colors.cyanAccent)),
            ),
          ],
        ),
      );
      return result ?? false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(appBar: AppBar(title: const Text('Pose Detector')), body: Center(child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 18), textAlign: TextAlign.center)));
    }
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return Scaffold(appBar: AppBar(title: const Text('Loading Camera...')), body: const Center(child: CircularProgressIndicator()));
    }
      final bool isFrontCamera = _cameraController!.description.lensDirection == CameraLensDirection.front;
      final Matrix4 cameraTransform = isFrontCamera ? (Matrix4.identity()..scale(-1.0, 1.0)) : Matrix4.identity();

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
            Center(
              child: ConfettiWidget(
                confettiController: _confettiController,
                blastDirection: pi / 2, // Downwards
                maxBlastForce: 20,
                minBlastForce: 5,
                emissionFrequency: 0.05,
                numberOfParticles: 50,
                gravity: 0.5,
                colors: const [Colors.green, Colors.blue, Colors.pink, Colors.orange, Colors.purple],
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
  final Size absoluteImageSize;
  final CameraLensDirection cameraLensDirection;
  final InputImageRotation rotation;
  final FormFeedback formFeedback;

  PosePainter(this.pose, this.absoluteImageSize, this.cameraLensDirection, this.rotation, this.formFeedback);

  @override
  void paint(Canvas canvas, Size size) {
    // Calculate scaling factors
    final scaleX = size.width / absoluteImageSize.width;
    final scaleY = size.height / absoluteImageSize.height;

    // Debug: Log sizes for verification
    debugPrint('Canvas size: ${size.width}x${size.height}, Image size: ${absoluteImageSize.width}x${absoluteImageSize.height}');
    debugPrint('Scale factors: scaleX=$scaleX, scaleY=$scaleY');

    Offset _getOffset(PoseLandmark landmark) {
      double x = landmark.x * scaleX  + 50;
      double y = landmark.y * scaleY - 75;

      // Apply mirroring for front camera
      if (cameraLensDirection == CameraLensDirection.front) {
        x = size.width - x; // Mirror horizontally
      }

      // Debug: Log transformed landmark position
      if (landmark.type == PoseLandmarkType.leftShoulder) {
        debugPrint('Transformed left shoulder: ($x, $y)');
      }

      return Offset(x, y);
    }

    final Paint landmarkPaint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 6.0
      ..style = PaintingStyle.fill;

    final Paint linePaint = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    final Paint goodFormPaint = Paint()
      ..color = Colors.green
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    final Paint borderlineFormPaint = Paint()
      ..color = Colors.orange
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    final Paint incorrectFormPaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    void drawLine(PoseLandmarkType p1Type, PoseLandmarkType p2Type, {FormStatus? status}) {
      final p1 = pose.landmarks[p1Type];
      final p2 = pose.landmarks[p2Type];
      if (p1 != null && p2 != null) {
        Paint currentPaint = linePaint;
        if (status != null) {
          switch (status) {
            case FormStatus.good:
              currentPaint = goodFormPaint;
              break;
            case FormStatus.borderline:
              currentPaint = borderlineFormPaint;
              break;
            case FormStatus.incorrect:
              currentPaint = incorrectFormPaint;
              break;
            case FormStatus.none:
              currentPaint = linePaint;
              break;
          }
        }
        canvas.drawLine(_getOffset(p1), _getOffset(p2), currentPaint);
      }
    }

    // Draw lines for body segments
    drawLine(PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder);
    drawLine(PoseLandmarkType.leftHip, PoseLandmarkType.rightHip);
    drawLine(PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip, status: formFeedback.hipSagAngleStatus != FormStatus.none ? formFeedback.hipSagAngleStatus : null);
    drawLine(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip, status: formFeedback.hipSagAngleStatus != FormStatus.none ? formFeedback.hipSagAngleStatus : null);
    drawLine(PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow, status: formFeedback.shoulderElbowAngleStatus != FormStatus.none ? formFeedback.shoulderElbowAngleStatus : null);
    drawLine(PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist);
    drawLine(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow, status: formFeedback.shoulderElbowAngleStatus != FormStatus.none ? formFeedback.shoulderElbowAngleStatus : null);
    drawLine(PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist);
    drawLine(PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee, status: formFeedback.backAngleStatus != FormStatus.none ? formFeedback.backAngleStatus : null);
    drawLine(PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle, status: formFeedback.kneeToePositionStatus != FormStatus.none ? formFeedback.kneeToePositionStatus : null);
    drawLine(PoseLandmarkType.leftAnkle, PoseLandmarkType.leftFootIndex, status: formFeedback.kneeToePositionStatus != FormStatus.none ? formFeedback.kneeToePositionStatus : null);
    drawLine(PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee, status: formFeedback.backAngleStatus != FormStatus.none ? formFeedback.backAngleStatus : null);
    drawLine(PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle, status: formFeedback.kneeToePositionStatus != FormStatus.none ? formFeedback.kneeToePositionStatus : null);
    drawLine(PoseLandmarkType.rightAnkle, PoseLandmarkType.rightFootIndex, status: formFeedback.kneeToePositionStatus != FormStatus.none ? formFeedback.kneeToePositionStatus : null);

    // Draw landmarks
    for (final landmark in pose.landmarks.values) {
      canvas.drawCircle(_getOffset(landmark), 4.0, landmarkPaint);
    }

    // Draw angle values for debugging
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
    );

    void drawAngle(double angleValue, PoseLandmark p1, PoseLandmark p2, PoseLandmark p3, String label, FormStatus status) {
      final centerOffset = Offset(
        (_getOffset(p1).dx + _getOffset(p2).dx + _getOffset(p3).dx) / 3,
        (_getOffset(p1).dy + _getOffset(p2).dy + _getOffset(p3).dy) / 3,
      );

      Color textColor;
      switch (status) {
        case FormStatus.good:
          textColor = Colors.green;
          break;
        case FormStatus.borderline:
          textColor = Colors.orange;
          break;
        case FormStatus.incorrect:
          textColor = Colors.red;
          break;
        case FormStatus.none:
        default:
          textColor = Colors.white;
          break;
      }

      textPainter.text = TextSpan(
        text: '$label: ${angleValue.toStringAsFixed(0)}°',
        style: TextStyle(color: textColor, fontSize: 14.0, fontWeight: FontWeight.bold),
      );
      textPainter.layout();
      textPainter.paint(canvas, centerOffset.translate(-textPainter.width / 2, -textPainter.height / 2));
    }

    if (formFeedback.shoulderElbowAngleStatus != FormStatus.none) {
      final lHip = pose.landmarks[PoseLandmarkType.leftHip];
      final lShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
      final lElbow = pose.landmarks[PoseLandmarkType.leftElbow];
      if (lHip != null && lShoulder != null && lElbow != null) {
        drawAngle(formFeedback.shoulderElbowAngleValue, lHip, lShoulder, lElbow, 'Elbow Flare', formFeedback.shoulderElbowAngleStatus);
      }
    }

    if (formFeedback.backAngleStatus != FormStatus.none) {
      final lShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
      final lHip = pose.landmarks[PoseLandmarkType.leftHip];
      final lKnee = pose.landmarks[PoseLandmarkType.leftKnee];
      if (lShoulder != null && lHip != null && lKnee != null) {
        drawAngle(formFeedback.backAngleValue, lShoulder, lHip, lKnee, 'Back Angle', formFeedback.backAngleStatus);
      }
    }

    if (formFeedback.hipSagAngleStatus != FormStatus.none) {
      final lShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
      final lHip = pose.landmarks[PoseLandmarkType.leftHip];
      final lKnee = pose.landmarks[PoseLandmarkType.leftKnee];
      if (lShoulder != null && lHip != null && lKnee != null) {
        drawAngle(formFeedback.hipSagAngleValue, lShoulder, lHip, lKnee, 'Hip Sag', formFeedback.hipSagAngleStatus);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}