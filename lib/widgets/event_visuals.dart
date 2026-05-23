import 'package:flutter/material.dart';
import '../models/traffic_event.dart';

/// Shared colour / icon / label mapping for traffic-event severities, used by
/// the map markers, the events list, and the event detail sheet.
class EventVisuals {
  EventVisuals._();

  static Color color(EventSeverity s) => switch (s) {
    EventSeverity.closed => const Color(0xFFE53935), // red
    EventSeverity.jam => const Color(0xFFFB8C00), // orange
    EventSeverity.roadworks => const Color(0xFFFFB300), // amber
    EventSeverity.other => const Color(0xFF5DA9E9), // blue
  };

  static IconData icon(EventSeverity s) => switch (s) {
    EventSeverity.closed => Icons.do_not_disturb_on,
    EventSeverity.jam => Icons.traffic,
    EventSeverity.roadworks => Icons.construction,
    EventSeverity.other => Icons.warning_amber_rounded,
  };

  /// A cause-specific icon derived from the event's `Icon` filename and
  /// `VzrokShortName`, falling back to the severity icon. This is what the map
  /// markers and list use so the symbol reflects the actual vzrok.
  static IconData causeIcon(TrafficEvent e) {
    final s = '${e.iconName} ${e.cause}'.toLowerCase();
    bool has(String p) => s.contains(p);

    if (has('nesrec')) return Icons.car_crash; // prometna nesreča
    if (has('zastoj') || has('kolon')) return Icons.traffic; // jam
    if (has('zapor') || has('zaprt')) return Icons.do_not_disturb_on; // closure
    if (has('izmenic') || has('enosmer')) return Icons.swap_vert; // alternating
    if (has('del')) return Icons.construction; // roadworks
    if (has('ovir') || has('predmet')) return Icons.report_problem; // obstacle
    if (has('zim') || has('sneg') || has('led') || has('pluz')) {
      return Icons.ac_unit; // winter conditions
    }
    if (has('megl')) return Icons.foggy; // fog
    if (has('veter') || has('burj') || has('piš')) return Icons.air; // wind
    if (has('tovorn') || has('kamion')) return Icons.local_shipping; // trucks
    if (has('pocival') || has('parkir')) return Icons.local_parking; // rest area
    if (has('priredit') || has('shod')) return Icons.celebration; // event
    if (has('zival')) return Icons.pets; // animals
    return icon(e.severity);
  }

  static String label(EventSeverity s) => switch (s) {
    EventSeverity.closed => 'Zaprto',
    EventSeverity.jam => 'Zastoj',
    EventSeverity.roadworks => 'Dela',
    EventSeverity.other => 'Opozorilo',
  };

}
