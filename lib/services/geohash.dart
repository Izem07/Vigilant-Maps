/// Minimal geohash encoder with 3x3 neighborhood lookup.
/// Self-contained so we don't depend on a third-party package's API.
class Geohash {
  static const _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';

  static String encode(double lat, double lng, {int precision = 9}) {
    double latMin = -90, latMax = 90, lngMin = -180, lngMax = 180;
    final buf = StringBuffer();
    var bit = 0, ch = 0;
    var evenBit = true; // even bits encode longitude

    while (buf.length < precision) {
      if (evenBit) {
        final mid = (lngMin + lngMax) / 2;
        if (lng >= mid) {
          ch = (ch << 1) | 1;
          lngMin = mid;
        } else {
          ch = ch << 1;
          lngMax = mid;
        }
      } else {
        final mid = (latMin + latMax) / 2;
        if (lat >= mid) {
          ch = (ch << 1) | 1;
          latMin = mid;
        } else {
          ch = ch << 1;
          latMax = mid;
        }
      }
      evenBit = !evenBit;
      if (++bit == 5) {
        buf.write(_base32[ch]);
        bit = 0;
        ch = 0;
      }
    }
    return buf.toString();
  }

  /// The cell containing (lat, lng) plus its 8 neighbors.
  /// Querying all 9 avoids missing traps just across a cell boundary.
  static List<String> neighborhood(double lat, double lng, int precision) {
    final totalBits = precision * 5;
    final lngBits = (totalBits + 1) ~/ 2;
    final latBits = totalBits ~/ 2;
    final cellH = 180 / (1 << latBits);
    final cellW = 360 / (1 << lngBits);

    final cells = <String>{};
    for (final dy in [-1, 0, 1]) {
      for (final dx in [-1, 0, 1]) {
        final la = (lat + dy * cellH).clamp(-89.999999, 89.999999);
        var lo = lng + dx * cellW;
        if (lo >= 180) lo -= 360;
        if (lo < -180) lo += 360;
        cells.add(encode(la, lo, precision: precision));
      }
    }
    return cells.toList();
  }
}
