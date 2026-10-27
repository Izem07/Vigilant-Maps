import 'dart:async';

import 'package:apple_maps_flutter/apple_maps_flutter.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/radar_service.dart';
import '../services/router_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const _alertRadiusMeters = 800.0; // ~0.5 mi
  static const _stepAdvanceMeters = 30.0;
  static const _offRouteMeters = 75.0;

  final RadarService _radarService = RadarService();
  final AudioPlayer _audioPlayer = AudioPlayer();
  AppleMapController? _mapController;

  LatLng _currentLocation = const LatLng(42.6808, -83.1340); // Rochester, MI
  bool _hasFix = false;

  // Navigation
  RouteResult? _route;
  LatLng? _destination;
  int _stepIndex = 0;
  bool _rerouting = false;
  Set<Polyline> _polylines = {};

  // Radar
  List<RadarTrap> _traps = [];
  final Set<String> _alertedTrapIds = {};
  String? _radarCell;
  StreamSubscription<List<RadarTrap>>? _radarSub;
  StreamSubscription<Position>? _positionSub;

  bool get _isNavigating => _route != null;

  @override
  void initState() {
    super.initState();
    _startLocationTracking();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _radarSub?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- Location

  Future<void> _startLocationTracking() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      _toast('Location services are off.');
      return;
    }

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      _toast('Vigilant needs location access to work.');
      return;
    }

    _positionSub = Geolocator.getPositionStream(
      locationSettings: AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
        activityType: ActivityType.automotiveNavigation,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
      ),
    ).listen(_onPosition, onError: (_) => _toast('Lost GPS signal.'));
  }

  void _onPosition(Position pos) {
    if (!mounted) return;
    final here = LatLng(pos.latitude, pos.longitude);
    final firstFix = !_hasFix;
    setState(() {
      _currentLocation = here;
      _hasFix = true;
    });

    if (firstFix || _isNavigating) {
      _mapController?.animateCamera(CameraUpdate.newLatLng(here));
    }

    _ensureRadarSubscription(here);
    _checkRadarProximity(here);
    if (_isNavigating) _updateNavigation(here);
  }

  // ------------------------------------------------------------------- Radar

  /// Re-subscribe only when the driver moves into a different geohash cell.
  void _ensureRadarSubscription(LatLng pos) {
    final cell = RadarService.cellFor(pos.latitude, pos.longitude);
    if (cell == _radarCell) return;
    _radarCell = cell;

    _radarSub?.cancel();
    _radarSub = _radarService
        .streamNearbyTraps(pos.latitude, pos.longitude)
        .listen((traps) {
      if (!mounted) return;
      setState(() => _traps = traps);
      _checkRadarProximity(_currentLocation);
    }, onError: (_) => _toast('Could not load nearby reports.'));
  }

  /// Alerts once per trap when it first comes within range.
  void _checkRadarProximity(LatLng userPos) {
    for (final trap in _traps) {
      if (_alertedTrapIds.contains(trap.id)) continue;
      final dist = Geolocator.distanceBetween(
        userPos.latitude,
        userPos.longitude,
        trap.latitude,
        trap.longitude,
      );
      if (dist <= _alertRadiusMeters) {
        _alertedTrapIds.add(trap.id);
        // Visual alert still shows if the sound file is missing.
        _audioPlayer
            .play(AssetSource('sounds/radar_alert.mp3'))
            .catchError((_) {});
        _toast(
          '⚠️ ${_labelFor(trap.type).toUpperCase()} REPORTED '
          '${(dist / 1609.34).toStringAsFixed(1)} MI AHEAD',
          color: Colors.redAccent,
        );
      }
    }
  }

  Future<void> _reportTrap() async {
    try {
      await _radarService.reportTrap(
        _currentLocation.latitude,
        _currentLocation.longitude,
        'cop',
      );
      _toast('Report sent. Thanks!', color: const Color(0xFF30D158));
    } catch (_) {
      _toast('Report failed. Check your connection.');
    }
  }

  Set<Annotation> get _trapAnnotations => {
        for (final t in _traps)
          Annotation(
            annotationId: AnnotationId('trap_${t.id}'),
            position: LatLng(t.latitude, t.longitude),
            infoWindow: InfoWindow(
              title: _labelFor(t.type),
              snippet:
                  '${DateTime.now().difference(t.timestamp).inMinutes} min ago',
            ),
          ),
        if (_destination != null)
          Annotation(
            annotationId: AnnotationId('destination'),
            position: _destination!,
            infoWindow: const InfoWindow(title: 'Destination'),
          ),
      };

  static String _labelFor(String type) => switch (type) {
        'camera' => 'Speed camera',
        'speed_trap' => 'Speed trap',
        _ => 'Police',
      };

  // -------------------------------------------------------------- Navigation

  Future<void> _startRoute(LatLng destination) async {
    if (!_hasFix) {
      _toast('Waiting for GPS…');
      return;
    }
    final route = await RouterService.fetchRoute(_currentLocation, destination);
    if (!mounted) return;
    if (route == null) {
      _toast('Could not find a route.');
      return;
    }

    setState(() {
      _route = route;
      _destination = destination;
      _stepIndex = route.steps.length > 1 ? 1 : 0; // skip "depart"
      _polylines = {
        Polyline(
          polylineId: PolylineId('route'),
          points: route.polylinePoints,
          color: const Color(0xFF007AFF),
          width: 6,
        ),
      };
    });
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(_currentLocation, 17));
  }

  void _stopRoute() {
    setState(() {
      _route = null;
      _destination = null;
      _stepIndex = 0;
      _polylines = {};
    });
  }

  void _updateNavigation(LatLng here) {
    final route = _route!;

    // Advance to the next maneuver once we reach the current one.
    final step = route.steps[_stepIndex];
    final toManeuver = Geolocator.distanceBetween(here.latitude, here.longitude,
        step.location.latitude, step.location.longitude);
    if (toManeuver < _stepAdvanceMeters) {
      if (_stepIndex >= route.steps.length - 1) {
        _toast('You have arrived.', color: const Color(0xFF30D158));
        _stopRoute();
        return;
      }
      setState(() => _stepIndex++);
    }

    // Reroute if we've drifted off the line.
    if (!_rerouting && _distanceToRoute(here, route) > _offRouteMeters) {
      _rerouting = true;
      _startRoute(_destination!).whenComplete(() => _rerouting = false);
    }
  }

  /// Rough off-route check: distance to the nearest route vertex.
  /// OSRM's full-overview geometry is dense enough for this to be reliable.
  double _distanceToRoute(LatLng here, RouteResult route) {
    var best = double.infinity;
    for (final p in route.polylinePoints) {
      final d = Geolocator.distanceBetween(
          here.latitude, here.longitude, p.latitude, p.longitude);
      if (d < best) best = d;
    }
    return best;
  }

  double get _distanceToNextManeuver {
    final step = _route!.steps[_stepIndex];
    return Geolocator.distanceBetween(
        _currentLocation.latitude,
        _currentLocation.longitude,
        step.location.latitude,
        step.location.longitude);
  }

  static IconData _iconFor(String instruction) {
    final s = instruction.toLowerCase();
    if (s.contains('u-turn')) return Icons.u_turn_left;
    if (s.contains('roundabout')) return Icons.roundabout_right;
    if (s.contains('slight left')) return Icons.turn_slight_left;
    if (s.contains('slight right')) return Icons.turn_slight_right;
    if (s.contains('sharp left')) return Icons.turn_sharp_left;
    if (s.contains('sharp right')) return Icons.turn_sharp_right;
    if (s.contains('left')) return Icons.turn_left;
    if (s.contains('right')) return Icons.turn_right;
    if (s.contains('arrived')) return Icons.flag;
    return Icons.straight;
  }

  static String _formatDistance(double meters) {
    final feet = meters * 3.28084;
    if (feet < 1000) return '${(feet / 50).round() * 50} ft';
    return '${(meters / 1609.34).toStringAsFixed(1)} mi';
  }

  // ---------------------------------------------------------------------- UI

  void _toast(String msg, {Color color = const Color(0xFF3A3A3C)}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        backgroundColor: color,
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
        duration: const Duration(seconds: 3),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          AppleMap(
            initialCameraPosition:
                CameraPosition(target: _currentLocation, zoom: 15),
            myLocationEnabled: true,
            polylines: _polylines,
            annotations: _trapAnnotations,
            onMapCreated: (c) => _mapController = c,
            onLongPress: _isNavigating ? null : _startRoute,
          ),

          if (_isNavigating) _buildInstructionCard(),
          if (!_isNavigating)
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              left: 16,
              right: 16,
              child: _panel(const Text(
                'Long-press the map to set a destination',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              )),
            ),

          Positioned(
            bottom: 30,
            right: 16,
            child: FloatingActionButton(
              heroTag: 'report',
              backgroundColor: const Color(0xFF30D158),
              onPressed: _reportTrap,
              child: const Icon(Icons.local_police, color: Colors.black),
            ),
          ),
          if (_isNavigating)
            Positioned(
              bottom: 30,
              left: 16,
              child: FloatingActionButton.extended(
                heroTag: 'end',
                backgroundColor: Colors.redAccent,
                onPressed: _stopRoute,
                icon: const Icon(Icons.close),
                label: Text(
                  '${_formatDistance(_route!.distanceMeters)} · '
                  '${(_route!.durationSeconds / 60).round()} min',
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInstructionCard() {
    final step = _route!.steps[_stepIndex];
    return Positioned(
      top: MediaQuery.of(context).padding.top + 12,
      left: 16,
      right: 16,
      child: _panel(Row(
        children: [
          Icon(_iconFor(step.instruction),
              color: const Color(0xFF30D158), size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatDistance(_distanceToNextManeuver),
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                Text(
                  step.instruction,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      )),
    );
  }

  Widget _panel(Widget child) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E).withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white24),
        ),
        child: child,
      );
}
