// lib/utils/pose_painter.dart

import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:camera/camera.dart'; // Import for CameraLensDirection
import 'package:flutter/foundation.dart'; // Import for defaultTargetPlatform

class PosePainter extends CustomPainter {
  final Pose pose;
  final Size imageSize;
  final CameraLensDirection cameraLensDirection; // Use CameraLensDirection
  final InputImageRotation rotation;
  final String currentPoseStageAI;
  final Map<String, String> formFeedback;

  PosePainter(
    this.pose,
    this.imageSize,
    this.cameraLensDirection,
    this.rotation,
    this.currentPoseStageAI,
    this.formFeedback,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final Paint landmarkPaint = Paint()
      ..color = Colors.blueAccent
      ..strokeWidth = 8
      ..style = PaintingStyle.fill;

    final Paint linePaint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke;

    final Paint feedbackPaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke;

    // Helper to determine if the camera is front-facing (and iOS for mirroring)
    final bool isIOSFrontCamera = cameraLensDirection == CameraLensDirection.front && defaultTargetPlatform == TargetPlatform.iOS;

    // Function to scale and mirror coordinates
    Offset transformPoint(Offset point) {
      final double scaleX = size.width / imageSize.width;
      final double scaleY = size.height / imageSize.height;

      double x = point.dx * scaleX;
      double y = point.dy * scaleY;

      // Mirror horizontally for front camera (or if specifically an iOS front camera, which tends to be mirrored by default)
      if (isIOSFrontCamera) {
        x = size.width - x;
      }

      return Offset(x, y);
    }

    // Draw landmarks
    for (final landmark in pose.landmarks.values) {
      final transformedPoint = transformPoint(Offset(landmark.x, landmark.y));
      canvas.drawCircle(transformedPoint, 4, landmarkPaint);
    }

    // Draw connections (lines) between key landmarks
    _drawConnections(canvas, linePaint, transformPoint);

    // Draw feedback highlights if any
    _drawFeedbackHighlights(canvas, feedbackPaint, transformPoint);
  }

  void _drawConnections(Canvas canvas, Paint paint, Function(Offset) transformPoint) {
    // Define the connections based on human anatomy
    final List<List<PoseLandmarkType>> connections = [
      // Face
      [PoseLandmarkType.nose, PoseLandmarkType.leftEyeInner],
      [PoseLandmarkType.leftEyeInner, PoseLandmarkType.leftEye],
      [PoseLandmarkType.leftEye, PoseLandmarkType.leftEyeOuter],
      [PoseLandmarkType.leftEyeOuter, PoseLandmarkType.leftEar],
      [PoseLandmarkType.nose, PoseLandmarkType.rightEyeInner],
      [PoseLandmarkType.rightEyeInner, PoseLandmarkType.rightEye],
      [PoseLandmarkType.rightEye, PoseLandmarkType.rightEyeOuter],
      [PoseLandmarkType.rightEyeOuter, PoseLandmarkType.rightEar],
      [PoseLandmarkType.nose, PoseLandmarkType.leftMouth],
      [PoseLandmarkType.leftMouth, PoseLandmarkType.rightMouth],
      [PoseLandmarkType.rightMouth, PoseLandmarkType.nose],

      // Torso
      [PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder],
      [PoseLandmarkType.leftHip, PoseLandmarkType.rightHip],
      [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip],
      [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip],

      // Left Arm
      [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow],
      [PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist],
      [PoseLandmarkType.leftWrist, PoseLandmarkType.leftThumb],
      [PoseLandmarkType.leftWrist, PoseLandmarkType.leftPinky],
      [PoseLandmarkType.leftWrist, PoseLandmarkType.leftIndex],

      // Right Arm
      [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow],
      [PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist],
      [PoseLandmarkType.rightWrist, PoseLandmarkType.rightThumb],
      [PoseLandmarkType.rightWrist, PoseLandmarkType.rightPinky],
      [PoseLandmarkType.rightWrist, PoseLandmarkType.rightIndex],

      // Left Leg
      [PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee],
      [PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle],
      [PoseLandmarkType.leftAnkle, PoseLandmarkType.leftHeel],
      [PoseLandmarkType.leftHeel, PoseLandmarkType.leftFootIndex],

      // Right Leg
      [PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee],
      [PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle],
      [PoseLandmarkType.rightAnkle, PoseLandmarkType.rightHeel],
      [PoseLandmarkType.rightHeel, PoseLandmarkType.rightFootIndex],
    ];

    for (final connection in connections) {
      final p1 = pose.landmarks[connection[0]];
      final p2 = pose.landmarks[connection[1]];
      if (p1 != null && p2 != null) {
        canvas.drawLine(transformPoint(Offset(p1.x, p1.y)), transformPoint(Offset(p2.x, p2.y)), paint);
      }
    }
  }

  void _drawFeedbackHighlights(Canvas canvas, Paint paint, Function(Offset) transformPoint) {
    if (formFeedback.isNotEmpty) {
      paint.color = Colors.redAccent; // Set highlight color for feedback
      paint.strokeWidth = 7; // Thicker line for emphasis

      // Example: Highlight elbows if there's "Elbows not tucked" feedback
      if (formFeedback.containsKey('leftElbow') || formFeedback.containsKey('rightElbow')) {
        final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
        final leftElbow = pose.landmarks[PoseLandmarkType.leftElbow];
        final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
        final rightElbow = pose.landmarks[PoseLandmarkType.rightElbow];

        if (leftShoulder != null && leftElbow != null && formFeedback.containsKey('leftElbow')) {
          canvas.drawLine(transformPoint(Offset(leftShoulder.x, leftShoulder.y)), transformPoint(Offset(leftElbow.x, leftElbow.y)), paint);
        }
        if (rightShoulder != null && rightElbow != null && formFeedback.containsKey('rightElbow')) {
          canvas.drawLine(transformPoint(Offset(rightShoulder.x, rightShoulder.y)), transformPoint(Offset(rightElbow.x, rightElbow.y)), paint);
        }
      }

      // Example: Highlight knees/toes if 'Knees past toes' feedback
      if (formFeedback.containsKey('leftKneePosition') || formFeedback.containsKey('rightKneePosition')) {
        final leftKnee = pose.landmarks[PoseLandmarkType.leftKnee];
        final leftAnkle = pose.landmarks[PoseLandmarkType.leftAnkle];
        final leftFootIndex = pose.landmarks[PoseLandmarkType.leftFootIndex];
        final rightKnee = pose.landmarks[PoseLandmarkType.rightKnee];
        final rightAnkle = pose.landmarks[PoseLandmarkType.rightAnkle];
        final rightFootIndex = pose.landmarks[PoseLandmarkType.rightFootIndex];

        if (leftKnee != null && leftAnkle != null && formFeedback.containsKey('leftKneePosition')) {
          canvas.drawLine(transformPoint(Offset(leftKnee.x, leftKnee.y)), transformPoint(Offset(leftAnkle.x, leftAnkle.y)), paint);
          if (leftFootIndex != null) {
            canvas.drawLine(transformPoint(Offset(leftAnkle.x, leftAnkle.y)), transformPoint(Offset(leftFootIndex.x, leftFootIndex.y)), paint);
          }
        }
        if (rightKnee != null && rightAnkle != null && formFeedback.containsKey('rightKneePosition')) {
          canvas.drawLine(transformPoint(Offset(rightKnee.x, rightKnee.y)), transformPoint(Offset(rightAnkle.x, rightAnkle.y)), paint);
          if (rightFootIndex != null) {
            canvas.drawLine(transformPoint(Offset(rightAnkle.x, rightAnkle.y)), transformPoint(Offset(rightFootIndex.x, rightFootIndex.y)), paint);
          }
        }
      }

      // Example: Highlight back/hip if 'Back angle incorrect' or 'Hip Sag' feedback
      if (formFeedback.containsKey('leftBackAngle') || formFeedback.containsKey('rightBackAngle') ||
          formFeedback.containsKey('leftHipSag') || formFeedback.containsKey('rightHipSag')) {
        final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
        final leftHip = pose.landmarks[PoseLandmarkType.leftHip];
        final leftKnee = pose.landmarks[PoseLandmarkType.leftKnee];
        final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
        final rightHip = pose.landmarks[PoseLandmarkType.rightHip];
        final rightKnee = pose.landmarks[PoseLandmarkType.rightKnee];

        if (leftShoulder != null && leftHip != null && leftKnee != null &&
            (formFeedback.containsKey('leftBackAngle') || formFeedback.containsKey('leftHipSag'))) {
          canvas.drawLine(transformPoint(Offset(leftShoulder.x, leftShoulder.y)), transformPoint(Offset(leftHip.x, leftHip.y)), paint);
          canvas.drawLine(transformPoint(Offset(leftHip.x, leftHip.y)), transformPoint(Offset(leftKnee.x, leftKnee.y)), paint);
        }
        if (rightShoulder != null && rightHip != null && rightKnee != null &&
            (formFeedback.containsKey('rightBackAngle') || formFeedback.containsKey('rightHipSag'))) {
          canvas.drawLine(transformPoint(Offset(rightShoulder.x, rightShoulder.y)), transformPoint(Offset(rightHip.x, rightHip.y)), paint);
          canvas.drawLine(transformPoint(Offset(rightHip.x, rightHip.y)), transformPoint(Offset(rightKnee.x, rightKnee.y)), paint);
        }
      }

      // Example: Highlight for Elbow Drift in Bicep Curls
      if (formFeedback.containsKey('leftElbowDrift') || formFeedback.containsKey('rightElbowDrift')) {
        final leftElbow = pose.landmarks[PoseLandmarkType.leftElbow];
        final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
        final rightElbow = pose.landmarks[PoseLandmarkType.rightElbow];
        final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];

        if (leftElbow != null && leftShoulder != null && formFeedback.containsKey('leftElbowDrift')) {
          canvas.drawLine(transformPoint(Offset(leftElbow.x, leftElbow.y)), transformPoint(Offset(leftShoulder.x, leftShoulder.y)), paint);
        }
        if (rightElbow != null && rightShoulder != null && formFeedback.containsKey('rightElbowDrift')) {
          canvas.drawLine(transformPoint(Offset(rightElbow.x, rightElbow.y)), transformPoint(Offset(rightShoulder.x, rightShoulder.y)), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant PosePainter oldDelegate) {
    // Repaint if the pose or feedback has changed
    return oldDelegate.pose != pose || oldDelegate.formFeedback != formFeedback || oldDelegate.currentPoseStageAI != currentPoseStageAI;
  }
}