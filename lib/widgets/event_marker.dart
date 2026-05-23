import 'package:flutter/material.dart';
import '../models/traffic_event.dart';
import 'event_visuals.dart';

/// A circular map pin for a traffic event, coloured by severity with a white
/// outline and the severity icon. Place with `alignment: Alignment.center`.
class EventMarker extends StatelessWidget {
  final TrafficEvent event;
  final VoidCallback onTap;

  const EventMarker({super.key, required this.event, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = EventVisuals.color(event.severity);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: const [
            BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2)),
          ],
        ),
        child: Icon(
          EventVisuals.causeIcon(event),
          size: 16,
          color: Colors.white,
        ),
      ),
    );
  }
}
