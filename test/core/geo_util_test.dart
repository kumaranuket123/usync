import 'package:flutter_test/flutter_test.dart';
import 'package:usync/core/utils/geo_util.dart';

void main() {
  group('distanceMetres', () {
    test('is zero for the same point', () {
      expect(GeoUtil.distanceMetres(28.6, 77.2, 28.6, 77.2), 0);
    });

    test('matches a known distance (Delhi to Mumbai is about 1150 km)', () {
      final m = GeoUtil.distanceMetres(28.6139, 77.2090, 19.0760, 72.8777);
      expect(m / 1000, inInclusiveRange(1140, 1160));
    });

    test('is symmetric', () {
      expect(GeoUtil.distanceMetres(10, 20, 30, 40), closeTo(GeoUtil.distanceMetres(30, 40, 10, 20), 1e-6));
    });
  });

  group('formatDistance', () {
    test('uses metres, then one-decimal km, then whole km', () {
      expect(GeoUtil.formatDistance(850), '850 m');
      expect(GeoUtil.formatDistance(4230), '4.2 km');
      expect(GeoUtil.formatDistance(420400), '420 km');
    });
  });
}
