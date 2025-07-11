 import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'add_workout.dart';
import 'workout.dart';

class AllWorkoutsScreen extends StatefulWidget {
  const AllWorkoutsScreen({super.key});

  @override
  State<AllWorkoutsScreen> createState() => _AllWorkoutsScreenState();
}

class _AllWorkoutsScreenState extends State<AllWorkoutsScreen> {
  final List<Map<String, dynamic>> workouts = [
    {
      'name': 'Lat pull downs',
      'duration': '30 minutes',
      'reps': 20,
      'sets': 15,
      'weight': 100,
    },
    {
      'name': 'Push ups',
      'duration': '30 minutes',
      'reps': 50,
      'sets': 2,
      'weight': 0,
    },
    {
      'name': 'Pull ups',
      'duration': '30 minutes',
      'reps': 15,
      'sets': 3,
      'weight': 0,
    },
  ];

  String searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final panelColor = const Color(0xFF0E1216);
    final accent = const Color(0xFFF06500);

    final filteredWorkouts = workouts
        .where((w) =>
            w['name'].toString().toLowerCase().contains(searchQuery.toLowerCase()))
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        title: Text('All Workouts', style: GoogleFonts.exo()),
        backgroundColor: panelColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddWorkoutScreen()),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Search bar
            TextField(
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search workouts',
                hintStyle: const TextStyle(color: Color(0xFFA1A1AA)),
                filled: true,
                fillColor: panelColor,
                prefixIcon: const Icon(Icons.search, color: Colors.white),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (val) {
                setState(() {
                  searchQuery = val;
                });
              },
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: filteredWorkouts.length,
                itemBuilder: (context, index) {
                  final workout = filteredWorkouts[index];
                  return Card(
                    color: panelColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    child: ListTile(
                      title: Text(
                        workout['name'],
                        style: GoogleFonts.exo(
                            fontWeight: FontWeight.bold, color: accent),
                      ),
                      subtitle: Text(
                        'Duration: ${workout['duration']}\nReps: ${workout['reps']}  Sets: ${workout['sets']}',
                        style: GoogleFonts.exo(color: Colors.white),
                      ),
                      isThreeLine: true,
                      trailing:
                          const Icon(Icons.chevron_right, color: Colors.white),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => WorkoutScreen(
                              exercise: workout['name'],
                              sets: workout['sets'],
                              reps: workout['reps'],
                              weight: workout['weight'],
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}