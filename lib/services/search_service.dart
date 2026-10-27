import 'dart:convert';

import 'package:apple_maps_flutter/apple_maps_flutter.dart';
import 'package:http/http.dart' as http;

class Place {
  final String title; // e.g. "Meijer"
  final String subtitle; // rest of the address
  final LatLng location;

  const Place(this.title, this.subtitle, this.location);
}

/// Address search via OpenStreetMap Nominatim (free, no key).
/// Usage policy: max 1 request/second, identifying User-Agent, and no
/// search-as-you-type — so call this on submit only.
class SearchService {
  static const _userAgent = 'Vigilant/1.0 (github.com/Izem07/Vigilant-Maps)';
  static DateTime _lastRequest = DateTime.fromMillisecondsSinceEpoch(0);

  static Future<List<Place>> search(String query, LatLng near) async {
    final q = query.trim();
    if (q.isEmpty) return [];

    // Enforce the 1 req/s limit.
    final wait = const Duration(seconds: 1) -
        DateTime.now().difference(_lastRequest);
    if (!wait.isNegative) await Future.delayed(wait);
    _lastRequest = DateTime.now();

    // Prefer results within ~50 km of the driver without excluding others.
    const d = 0.5;
    final url = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': q,
      'format': 'jsonv2',
      'limit': '8',
      'addressdetails': '0',
      'viewbox': '${near.longitude - d},${near.latitude + d},'
          '${near.longitude + d},${near.latitude - d}',
    });

    final http.Response res;
    try {
      res = await http
          .get(url, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      return [];
    }
    if (res.statusCode != 200) return [];

    final results = jsonDecode(res.body) as List;
    return results.map((r) {
      final display = r['display_name'] as String? ?? '';
      final name = r['name'] as String? ?? '';
      final parts = display.split(', ');
      final title = name.isNotEmpty ? name : parts.first;
      final subtitle = (name.isNotEmpty && parts.first == name)
          ? parts.skip(1).join(', ')
          : display;
      return Place(
        title,
        subtitle,
        LatLng(double.parse(r['lat'] as String), double.parse(r['lon'] as String)),
      );
    }).toList();
  }
}
