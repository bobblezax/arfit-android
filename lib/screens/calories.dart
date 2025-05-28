import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class CaloriesScreen extends StatelessWidget {
  const CaloriesScreen({super.key});

  final List<Map<String, dynamic>> recentExercises = const [
    {'name': 'Push ups', 'reps': 10, 'calories': 150},
    {'name': 'Squats', 'reps': 7, 'calories': 85},
    {'name': 'Deadlift', 'reps': 10, 'calories': 165},
  ];

  @override
  Widget build(BuildContext context) {
    final panelColor = const Color(0xFF0E1216);
    final accent = const Color(0xFFF06500);
    final textColor = Colors.white;

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        title: Text('Calories', style: GoogleFonts.exo()),
        backgroundColor: panelColor,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total Calories burned',
                style: GoogleFonts.exo(color: Colors.white, fontSize: 18)),
            const SizedBox(height: 8),
            Text('3,600 cal',
                style: GoogleFonts.exo(
                    color: accent,
                    fontSize: 36,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            Text('Today: Reps completed',
                style: GoogleFonts.exo(color: Colors.white, fontSize: 18)),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: recentExercises.length,
                itemBuilder: (context, index) {
                  final exercise = recentExercises[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: panelColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(exercise['name'],
                            style: GoogleFonts.exo(
                                color: accent,
                                fontWeight: FontWeight.bold,
                                fontSize: 16)),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('${exercise['reps']}/10 reps',
                                style: GoogleFonts.exo(color: Colors.white)),
                            Text('${exercise['calories']} cal',
                                style: GoogleFonts.exo(color: Colors.white)),
                          ],
                        )
                      ],
                    ),
                  );
                },
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  // TODO: Add calorie input logic
                },
                child: const Text('Add calories'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

