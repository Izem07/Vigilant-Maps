import 'package:cloud_firestore/cloud_firestore.dart';

import 'geohash.dart';

class RadarTrap {
  final String id;
  final double latitude;
  final double longitude;
  final String type; // 'cop', 'camera', 'speed_trap'
  final DateTime timestamp;

  const RadarTrap({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.type,
    required this.timestamp,
  });
}

class RadarService {
  /// Precision 5 ≈ 4.9 km x 4.9 km cells; the 3x3 neighborhood covers ~15 km.
  static const queryPrecision = 5;
  static const trapLifetime = Duration(minutes: 30);

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> reportTrap(double lat, double lng, String type) {
    final hash = Geohash.encode(lat, lng, precision: 9);
    return _db.collection('traps').add({
      'latitude': lat,
      'longitude': lng,
      'geohash': hash,
      'g5': hash.substring(0, queryPrecision), // equality-queryable cell
      'type': type,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Streams non-expired traps in the 9 cells around (lat, lng).
  /// Re-subscribe when [cellFor] changes for the user's position.
  Stream<List<RadarTrap>> streamNearbyTraps(double lat, double lng) {
    final cells = Geohash.neighborhood(lat, lng, queryPrecision);

    return _db
        .collection('traps')
        .where('g5', whereIn: cells)
        .snapshots()
        .map((snapshot) {
      final cutoff = DateTime.now().subtract(trapLifetime);
      return snapshot.docs
          .map((doc) {
            final d = doc.data();
            return RadarTrap(
              id: doc.id,
              latitude: (d['latitude'] as num).toDouble(),
              longitude: (d['longitude'] as num).toDouble(),
              type: d['type'] as String? ?? 'cop',
              // Pending server timestamp on our own fresh report -> treat as now.
              timestamp:
                  (d['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
            );
          })
          // Filter client-side so no composite index is needed; the cleanup
          // function deletes expired docs server-side.
          .where((t) => t.timestamp.isAfter(cutoff))
          .toList();
    });
  }

  static String cellFor(double lat, double lng) =>
      Geohash.encode(lat, lng, precision: queryPrecision);
}
