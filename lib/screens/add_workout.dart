import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AddWorkoutScreen extends StatefulWidget {
  const AddWorkoutScreen({super.key});

  @override
  State<AddWorkoutScreen> createState() => _AddWorkoutScreenState();
}

class _AddWorkoutScreenState extends State<AddWorkoutScreen> {
  final titleController = TextEditingController();
  final repsController = TextEditingController();
  final weightController = TextEditingController();
  final restController = TextEditingController();
  final setsController = TextEditingController();

  String selectedType = 'Warm up';

  final List<String> workoutTypes = ['Warm up', 'Main', 'Cool Down'];

  @override
  Widget build(BuildContext context) {
    final panelColor = const Color(0xFF0E1216);
    final accent = const Color(0xFFF06500);

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        title: Text('Create Exercise', style: GoogleFonts.exo()),
        backgroundColor: panelColor,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
          child: Column(
            children: [
              _buildTextField('Title', titleController),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: selectedType,
                dropdownColor: panelColor,
                decoration: InputDecoration(
                  labelText: 'Type',
                  labelStyle: GoogleFonts.exo(color: Colors.white),
                  filled: true,
                  fillColor: panelColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                items: workoutTypes
                    .map((type) => DropdownMenuItem(
                          value: type,
                          child: Text(type, style: GoogleFonts.exo(color: Colors.white)),
                        ))
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      selectedType = val;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
              _buildTextField('Reps', repsController, keyboardType: TextInputType.number),
              const SizedBox(height: 16),
              _buildTextField('Weight (lbs)', weightController, keyboardType: TextInputType.number),
              const SizedBox(height: 16),
              _buildTextField('Rest Timer (seconds)', restController, keyboardType: TextInputType.number),
              const SizedBox(height: 16),
              _buildTextField('Sets', setsController, keyboardType: TextInputType.number),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    // TODO: Add workout creation logic
                    Navigator.pop(context);
                  },
                  child: const Text('Create Workout'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller,
      {TextInputType keyboardType = TextInputType.text}) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFFA1A1AA)),
        filled: true,
        fillColor: const Color(0xFF0E1216),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
