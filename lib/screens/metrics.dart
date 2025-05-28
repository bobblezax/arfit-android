import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'body_weight.dart';
import 'calories.dart';

class MetricsScreen extends StatelessWidget {
  const MetricsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final panelColor = const Color(0xFF0E1216);
    final accent = const Color(0xFFF06500);

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        title: Text('Metrics', style: GoogleFonts.exo()),
        backgroundColor: panelColor,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            _buildMetricCard(
              context,
              title: 'Body Weight',
              description: 'Input weight weekly to track progress.',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BodyWeightScreen()),
                );
              },
            ),
            const SizedBox(height: 20),
            _buildMetricCard(
              context,
              title: 'Calorie Tracking',
              description: 'Track calories burned and consumed.',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CaloriesScreen()),
                );
              },
            ),
            // Add more metric cards here as needed
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard(BuildContext context,
      {required String title, required String description, required VoidCallback onTap}) {
    final panelColor = const Color(0xFF0E1216);
    final accent = const Color(0xFFF06500);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: panelColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: GoogleFonts.exo(
                    color: accent, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(description,
                style: GoogleFonts.exo(color: Colors.white, fontSize: 16)),
          ],
        ),
      ),
    );
  }
}
