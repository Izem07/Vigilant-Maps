import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'geohash.dart';

/// Report categories. [id] is what's stored in Firestore.
enum ReportType {
  cop('cop', 'Police'),
  camera('camera', 'Speed camera'),
  hazard('hazard', 'Hazard');

  const ReportType(this.id, this.label);
  final String id;
  final String label;

  /// Unknown or legacy values (e.g. 'speed_trap') display as police.
  static ReportType fromId(String? id) =>
      values.firstWhere((t) => t.id == id, orElse: () => cop);
}

class Report {
  final String id;
  final double latitude;
  final double longitude;
  final ReportType type;
  final DateTime timestamp;
  final String? reporterId;

  const Report({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.type,
    required this.timestamp,
    this.reporterId,
  });
}

class RadarService {
  /// Precision 5 ≈ 4.9 km x 4.9 km cells; the 3x3 neighborhood covers ~15 km.
  static const queryPrecision = 5;
  static const reportLifetime = Duration(minutes: 30);

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Anonymous Firebase user ID: stable per install, no sign-up, and
  /// verifiable in security rules (unlike a self-generated device ID).
  Future<String> _reporterId() async {
    final user = _auth.currentUser ?? (await _auth.signInAnonymously()).user!;
    return user.uid;
  }

  Future<void> reportHazard(double lat, double lng, ReportType type) async {
    await _db.collection('reports').add({
      'latitude': lat,
      'longitude': lng,
      'geohash': cellFor(lat, lng), // queryable grid cell
      'type': type.id,
      'timestamp': FieldValue.serverTimestamp(),
      'reporterId': await _reporterId(),
    });
  }

  /// Streams non-expired reports in the 9 cells around (lat, lng).
  /// Re-subscribe when [cellFor] changes for the user's position.
  Stream<List<Report>> streamNearbyReports(double lat, double lng) {
    final cells = Geohash.neighborhood(lat, lng, queryPrecision);

    return _db
        .collection('reports')
        .where('geohash', whereIn: cells)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) {
              final d = doc.data();
              return Report(
                id: doc.id,
                latitude: (d['latitude'] as num).toDouble(),
                longitude: (d['longitude'] as num).toDouble(),
                type: ReportType.fromId(d['type'] as String?),
                // Pending server timestamp on our own fresh report -> now.
                timestamp:
                    (d['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
                reporterId: d['reporterId'] as String?,
              );
            })
            // Client-side expiry keeps this free without the cleanup function.
            .where((r) => isReportValid(r.timestamp))
            .toList());
  }

  static bool isReportValid(DateTime timestamp) =>
      DateTime.now().difference(timestamp) <= reportLifetime;

  static String cellFor(double lat, double lng) =>
      Geohash.encode(lat, lng, precision: queryPrecision);
}
