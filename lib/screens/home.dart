import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'calendar.dart';
import 'metrics.dart';
import 'workout.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _username = 'Athlete';
  String? _profileImageUrl;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchUserDataFromFirestore();
  }

  Future<void> _fetchUserDataFromFirestore() async {
    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (doc.exists) {
          final data = doc.data()!;
          if (data['username'] != null) {
            _username = data['username'];
          }
          if (data['profileImageUrl'] != null) {
            _profileImageUrl = data['profileImageUrl'];
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching user data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = const Color(0xFFF06500);
    final panelColor = const Color(0xFF0E1216);

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: panelColor,
        elevation: 0,
        title: _isLoading
            ? Text(
                'Loading...',
                style: GoogleFonts.exo(color: Colors.white),
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'Welcome back, ',
                    style: GoogleFonts.exo(
                      fontSize: 18,
                      color: Colors.white,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  Flexible(
                    child: Text(
                      _username,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.exo(
                        fontSize: 20,
                        color: accent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
        actions: [
          IconButton(
            onPressed: () async {
              await Navigator.pushNamed(context, '/profile');
              _fetchUserDataFromFirestore(); // Refresh on return
            },
            icon: _profileImageUrl != null
                ? CircleAvatar(
                    backgroundImage: NetworkImage(_profileImageUrl!),
                  )
                : const CircleAvatar(
                    backgroundColor: Colors.white24,
                    child: Icon(Icons.person, color: Colors.white),
                  ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.orange))
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  _buildWorkoutCard(
                    context,
                    title: 'Your next workout',
                    exercise: 'Push ups',
                    duration: '30 minutes',
                    reps: '50',
                    sets: '2',
                    buttonText: 'Start workout',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => WorkoutScreen(
                            exercise: 'Push ups',
                            sets: 2,
                            reps: 50,
                            weight: 0,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  _buildWorkoutCard(
                    context,
                    title: 'Your last workout',
                    exercise: 'Pull ups',
                    duration: '30 minutes',
                    reps: '25',
                    sets: '3',
                    buttonText: 'Continue workout',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => WorkoutScreen(
                            exercise: 'Pull ups',
                            sets: 3,
                            reps: 25,
                            weight: 0,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: panelColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Overall progress:',
                          style: GoogleFonts.exo(
                              color: Colors.white, fontSize: 16),
                        ),
                        Text(
                          '70%',
                          style: GoogleFonts.exo(
                            color: accent,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const MetricsScreen()),
                            );
                          },
                          child: const Text('See metrics'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildWorkoutCard(
    BuildContext context, {
    required String title,
    required String exercise,
    required String duration,
    required String reps,
    required String sets,
    required String buttonText,
    required VoidCallback onPressed,
  }) {
    final panelColor = const Color(0xFF0E1216);
    final textColor = Colors.white;
    final accent = const Color(0xFFF06500);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: GoogleFonts.exo(
                  fontSize: 18, fontWeight: FontWeight.bold, color: accent)),
          const SizedBox(height: 10),
          Text('Exercise: $exercise',
              style: GoogleFonts.exo(fontSize: 16, color: textColor)),
          Text('Duration: $duration',
              style: GoogleFonts.exo(fontSize: 16, color: textColor)),
          Text('Reps: $reps',
              style: GoogleFonts.exo(fontSize: 16, color: textColor)),
          Text('Sets: $sets',
              style: GoogleFonts.exo(fontSize: 16, color: textColor)),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(buttonText),
            ),
          ),
        ],
      ),
    );
  }
}