import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:google_fonts/google_fonts.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  Widget build(BuildContext context) {
    final panelColor = const Color(0xFF0E1216);
    final accent = const Color(0xFFF06500);
    final textColor = Colors.white;

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        title: Text('Calendar', style: GoogleFonts.exo()),
        backgroundColor: panelColor,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: TableCalendar(
          firstDay: DateTime.utc(2020, 1, 1),
          lastDay: DateTime.utc(2030, 12, 31),
          focusedDay: _focusedDay,
          selectedDayPredicate: (day) {
            return isSameDay(_selectedDay, day);
          },
          onDaySelected: (selectedDay, focusedDay) {
            setState(() {
              _selectedDay = selectedDay;
              _focusedDay = focusedDay;
            });
          },
          calendarStyle: CalendarStyle(
            defaultTextStyle: GoogleFonts.exo(color: textColor),
            weekendTextStyle: GoogleFonts.exo(color: accent),
            todayDecoration: BoxDecoration(
              color: accent,
              shape: BoxShape.circle,
            ),
            selectedDecoration: BoxDecoration(
              color: accent.withOpacity(0.7),
              shape: BoxShape.circle,
            ),
            outsideDaysVisible: false,
          ),
          headerStyle: HeaderStyle(
            formatButtonVisible: false,
            titleCentered: true,
            titleTextStyle: GoogleFonts.exo(color: Colors.white, fontSize: 18),
            leftChevronIcon: Icon(Icons.chevron_left, color: Colors.white),
            rightChevronIcon: Icon(Icons.chevron_right, color: Colors.white),
            headerPadding: const EdgeInsets.symmetric(vertical: 8),
          ),
          calendarBuilders: CalendarBuilders(
            dowBuilder: (context, day) {
              final text = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][day.weekday % 7];
              return Center(
                child: Text(
                  text,
                  style: GoogleFonts.exo(color: accent, fontWeight: FontWeight.bold),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
