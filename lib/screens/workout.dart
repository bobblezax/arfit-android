import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'tutorial.dart';
import 'metrics.dart';

class WorkoutScreen extends StatefulWidget {
  final String exercise;
  final int sets;
  final int reps;
  final int weight;

  const WorkoutScreen({
    super.key,
    required this.exercise,
    required this.sets,
    required this.reps,
    required this.weight,
  });

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  int completedSets = 0;
  final int restSeconds = 80;

  @override
  Widget build(BuildContext context) {
    final panelColor = const Color(0xFF0E1216);
    final accent = const Color(0xFFF06500);

    return WillPopScope(
      onWillPop: () async {
        Navigator.popUntil(context, (route) => route.isFirst);
        return false;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF000000),
        appBar: AppBar(
          title: Text(widget.exercise, style: GoogleFonts.exo()),
          backgroundColor: panelColor,
        ),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.exercise,
                  style: GoogleFonts.exo(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: accent)),
              const SizedBox(height: 8),
              Text('Weight: ${widget.weight} lbs',
                  style: GoogleFonts.exo(color: Colors.white, fontSize: 16)),
              Text('Reps: ${widget.reps}', style: GoogleFonts.exo(color: Colors.white)),
              Text('Sets: ${widget.sets}', style: GoogleFonts.exo(color: Colors.white)),
              const SizedBox(height: 20),
              Text(
                'Completed Sets: $completedSets/${widget.sets}',
                style: GoogleFonts.exo(color: Colors.white, fontSize: 18),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    if (completedSets < widget.sets) {
                      completedSets++;
                      if (completedSets == widget.sets) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Workout complete!',
                              style: GoogleFonts.exo(color: Colors.white),
                            ),
                            backgroundColor: accent,
                          ),
                        );
                      }
                    }
                  });
                },
                child: const Text('Complete Set'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  minimumSize: const Size.fromHeight(50),
                ),
              ),
              const SizedBox(height: 16),
              Text('Rest: $restSeconds seconds',
                  style: GoogleFonts.exo(color: Colors.white, fontSize: 16)),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MetricsScreen()),
                  );
                },
                icon: const Icon(Icons.fitness_center),
                label: const Text('Enable Form Tracking'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  minimumSize: const Size.fromHeight(50),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TutorialScreen()),
                  );
                },
                icon: const Icon(Icons.play_circle_fill),
                label: const Text('Watch Tutorial Video'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  minimumSize: const Size.fromHeight(50),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
