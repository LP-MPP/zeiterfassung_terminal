import 'package:flutter_test/flutter_test.dart';
import 'package:zeiterfassung_terminal/update/app_update.dart';

void main() {
  test('parses a valid update manifest', () {
    final update = AppUpdate.fromJson({
      'versionCode': 4,
      'versionName': '1.3.0',
      'apkUrl': 'https://example.test/terminal.apk',
      'sha256': 'a' * 64,
      'releaseNotes': 'Neue Funktionen',
      'mandatory': false,
      'apkSize': 1234,
    });

    expect(update.versionCode, 4);
    expect(update.versionName, '1.3.0');
    expect(update.apkUri.scheme, 'https');
    expect(update.apkSize, 1234);
  });

  test('rejects insecure APK URLs', () {
    expect(
      () => AppUpdate.fromJson({
        'versionCode': 4,
        'versionName': '1.3.0',
        'apkUrl': 'http://example.test/terminal.apk',
        'sha256': 'a' * 64,
      }),
      throwsFormatException,
    );
  });

  test('rejects invalid checksums', () {
    expect(
      () => AppUpdate.fromJson({
        'versionCode': 4,
        'versionName': '1.3.0',
        'apkUrl': 'https://example.test/terminal.apk',
        'sha256': 'not-a-checksum',
      }),
      throwsFormatException,
    );
  });
}
