import 'package:flutter/material.dart';

import '../models/traffic_event.dart';
import 'event_visuals.dart';
import 'temperature_marker.dart' show MapPinStyle;

/// A circular map pin for a traffic event, coloured by severity with the
/// shared white pin rim and the severity icon. Place with `alignment: Alignment.center`.
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
              // Same rim, shadow and gradient as the other map pins.
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [MapPinStyle.lighten(color, 0.08), color],
                ),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: MapPinStyle.rim),
                boxShadow: MapPinStyle.shadow,
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
