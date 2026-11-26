import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promet/widgets/webcam_thumbnail.dart';

void main() {
  group('webcamCacheBucket', () {
    test('rounds down to 5-minute steps', () {
      final a = DateTime.utc(2026, 11, 26, 12, 0, 1);
      final b = DateTime.utc(2026, 11, 26, 12, 4, 59);
      final c = DateTime.utc(2026, 11, 26, 12, 5);
      expect(
        webcamCacheBucket(a),
        DateTime.utc(2026, 11, 26, 12).millisecondsSinceEpoch,
      );
      expect(webcamCacheBucket(a), webcamCacheBucket(b));
      expect(webcamCacheBucket(c), c.millisecondsSinceEpoch);
    });
  });

  group('ThumbnailSize.forZoom', () {
    test('weather tiers', () {
      expect(ThumbnailSize.forZoom(10.9), isNull);
      expect(ThumbnailSize.forZoom(11), ThumbnailSize.small);
      expect(ThumbnailSize.forZoom(12.9), ThumbnailSize.small);
      expect(ThumbnailSize.forZoom(13), ThumbnailSize.medium);
      expect(ThumbnailSize.forZoom(14.4), ThumbnailSize.medium);
      expect(ThumbnailSize.forZoom(14.5), ThumbnailSize.large);
    });

    test('camera tiers start at 13', () {
      expect(ThumbnailSize.forZoom(12.9, minZoom: 13), isNull);
      expect(ThumbnailSize.forZoom(13, minZoom: 13), ThumbnailSize.medium);
      expect(ThumbnailSize.forZoom(16, minZoom: 13), ThumbnailSize.large);
    });
  });

  for (final size in ThumbnailSize.values) {
    testWidgets('WebcamThumbnail sizes its frame (${size.name})', (
      tester,
    ) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: WebcamThumbnail.sized('https://example.invalid/c.jpg', size),
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(WebcamThumbnail)),
        Size(size.width, size.height),
      );
    });
  }
}
