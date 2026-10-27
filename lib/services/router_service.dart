import 'dart:convert';

import 'package:apple_maps_flutter/apple_maps_flutter.dart';
import 'package:http/http.dart' as http;

class RouteStep {
  final String instruction;
  final LatLng location; // where the maneuver happens
  final double distanceMeters; // length of this step

  const RouteStep(this.instruction, this.location, this.distanceMeters);
}

class RouteResult {
  final List<LatLng> polylinePoints;
  final double distanceMeters;
  final double durationSeconds;
  final List<RouteStep> steps;

  const RouteResult({
    required this.polylinePoints,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.steps,
  });
}

class RouterService {
  // NOTE: the public demo server is for development only (see its usage
  // policy). Point this at a self-hosted OSRM instance before release.
  static const _baseUrl = 'https://router.project-osrm.org';

  static Future<RouteResult?> fetchRoute(LatLng start, LatLng end) async {
    final url = Uri.parse(
      '$_baseUrl/route/v1/driving/'
      '${start.longitude},${start.latitude};${end.longitude},${end.latitude}'
      '?overview=full&geometries=geojson&steps=true',
    );

    final http.Response res;
    try {
      res = await http.get(url).timeout(const Duration(seconds: 15));
    } catch (_) {
      return null;
    }
    if (res.statusCode != 200) return null;

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final routes = data['routes'] as List?;
    if (data['code'] != 'Ok' || routes == null || routes.isEmpty) return null;

    final route = routes.first as Map<String, dynamic>;
    final coords = route['geometry']['coordinates'] as List;
    final points = coords
        .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
        .toList();

    final steps = <RouteStep>[];
    for (final leg in route['legs'] as List) {
      for (final step in leg['steps'] as List) {
        final m = step['maneuver'] as Map<String, dynamic>;
        final loc = m['location'] as List;
        steps.add(RouteStep(
          _instructionFor(m, step['name'] as String? ?? ''),
          LatLng((loc[1] as num).toDouble(), (loc[0] as num).toDouble()),
          (step['distance'] as num).toDouble(),
        ));
      }
    }

    return RouteResult(
      polylinePoints: points,
      distanceMeters: (route['distance'] as num).toDouble(),
      durationSeconds: (route['duration'] as num).toDouble(),
      steps: steps,
    );
  }

  /// OSRM does not return human-readable text; build it from type/modifier/name.
  static String _instructionFor(Map<String, dynamic> m, String road) {
    final type = m['type'] as String? ?? '';
    final modifier = (m['modifier'] as String? ?? '').replaceAll('_', ' ');
    final onto = road.isNotEmpty ? ' onto $road' : '';

    switch (type) {
      case 'depart':
        return road.isNotEmpty ? 'Head out on $road' : 'Start driving';
      case 'arrive':
        return 'You have arrived';
      case 'roundabout':
      case 'rotary':
        final exit = m['exit'];
        return exit != null
            ? 'At the roundabout, take exit $exit$onto'
            : 'Enter the roundabout$onto';
      case 'merge':
        return 'Merge$onto';
      case 'on ramp':
        return 'Take the ramp$onto';
      case 'off ramp':
        return 'Take the exit$onto';
      case 'fork':
        return 'Keep $modifier at the fork$onto';
      case 'end of road':
        return 'At the end of the road, turn $modifier$onto';
      case 'continue':
      case 'new name':
        return road.isNotEmpty ? 'Continue on $road' : 'Continue';
      default: // 'turn' and anything else
        if (modifier == 'straight') return 'Continue straight$onto';
        if (modifier == 'uturn') return 'Make a U-turn$onto';
        return modifier.isNotEmpty ? 'Turn $modifier$onto' : 'Continue$onto';
    }
  }
}
