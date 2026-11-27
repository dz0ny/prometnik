import 'package:flutter_test/flutter_test.dart';
import 'package:promet/providers/update_provider.dart';

void main() {
  test('date versions compare part by part', () {
    expect(isNewerVersion('2026.1127.2', '2026.1127.1'), isTrue);
    expect(isNewerVersion('2026.1201.1', '2026.1127.9'), isTrue);
    expect(isNewerVersion('2027.101.1', '2026.1231.5'), isTrue);
    expect(isNewerVersion('2026.1127.1', '2026.1127.1'), isFalse);
    expect(isNewerVersion('2026.1126.3', '2026.1127.1'), isFalse);
  });

  test('releases need a version tag and an APK asset', () {
    final release = parseRelease({
      'tag_name': 'v2026.1127.2',
      'assets': [
        {
          'name': 'prometnik-v2026.1127.2-play.aab',
          'browser_download_url': 'a',
        },
        {
          'name': 'prometnik-v2026.1127.2-android.apk',
          'browser_download_url': 'b',
        },
      ],
    });
    expect(release?.version, '2026.1127.2');
    expect(release?.downloadUrl, 'b');
    expect(parseRelease({'tag_name': 'v2026.1127.2', 'assets': []}), isNull);
    expect(parseRelease({'tag_name': 'latest'}), isNull);
  });
}
