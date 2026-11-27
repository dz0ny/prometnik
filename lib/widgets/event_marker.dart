import 'package:flutter/material.dart';

import '../models/traffic_event.dart';
import 'event_visuals.dart';

/// A circular map pin for a traffic event, coloured by severity with a white
/// outline and the severity icon. Place with `alignment: Alignment.center`.
class EventMarker extends StatelessWidget {
  /// Diameter of the visible pin.
  static const double pinSize = 28;

  final TrafficEvent event;
  final VoidCallback onTap;

  /// Tappable square around the pin; larger than [pinSize] adds transparent
  /// padding so small map pins are still easy to hit.
  final double hitSize;

  const EventMarker({
    super.key,
    required this.event,
    required this.onTap,
    this.hitSize = pinSize,
  });

  @override
  Widget build(BuildContext context) {
    final color = EventVisuals.color(event.severity);
    final label = event.title.isEmpty ? event.cause : event.title;
    return Semantics(
      button: true,
      label: event.road.isEmpty ? label : '$label, ${event.road}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox.square(
          dimension: hitSize < pinSize ? pinSize : hitSize,
          child: Center(
            child: Container(
              width: pinSize,
              height: pinSize,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black38,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                EventVisuals.causeIcon(event),
                size: 16,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
