import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';

class BodyWeightScreen extends StatefulWidget {
  const BodyWeightScreen({super.key});

  @override
  State<BodyWeightScreen> createState() => _BodyWeightScreenState();
}

class _BodyWeightScreenState extends State<BodyWeightScreen> {
  final List<FlSpot> weightSpots = [
    FlSpot(1, 130),
    FlSpot(2, 140),
    FlSpot(3, 145),
    FlSpot(4, 150),
    FlSpot(5, 155),
    FlSpot(6, 160),
    FlSpot(7, 158),
    FlSpot(8, 155),
  ];

  final TextEditingController weightController = TextEditingController();

  void _addWeight() {
    final text = weightController.text;
    if (text.isEmpty) return;
    final weight = double.tryParse(text);
    if (weight == null) return;
    setState(() {
      weightSpots.add(FlSpot(weightSpots.length + 1, weight));
      weightController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final panelColor = const Color(0xFF0E1216);
    final accent = const Color(0xFFF06500);
    final textColor = Colors.white;

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        title: Text('Body Weight', style: GoogleFonts.exo()),
        backgroundColor: panelColor,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(
              'Input weight weekly to track progress.',
              style: GoogleFonts.exo(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 250,
              child: LineChart(
                LineChartData(
                  backgroundColor: panelColor,
                  gridData: FlGridData(show: true, horizontalInterval: 10),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: true, interval: 10, getTitlesWidget: (val, _) {
                        return Text('${val.toInt()}', style: GoogleFonts.exo(color: textColor, fontSize: 12));
                      }),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: true, interval: 1, getTitlesWidget: (val, _) {
                        return Text('W${val.toInt()}', style: GoogleFonts.exo(color: textColor, fontSize: 12));
                      }),
                    ),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: true, border: Border.all(color: accent)),
                  lineBarsData: [
                    LineChartBarData(
                      spots: weightSpots,
                      isCurved: true,
                      color: accent,
                      barWidth: 3,
                      dotData: FlDotData(show: true),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: weightController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Add new weight (kg)',
                labelStyle: const TextStyle(color: Color(0xFFA1A1AA)),
                filled: true,
                fillColor: panelColor,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _addWeight,
                child: const Text('Add Weight'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
