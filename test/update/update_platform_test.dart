import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeiterfassung_terminal/update/update_platform.dart';

void main() {
  test('in-app APK updates are enabled only for native Android', () {
    expect(
      supportsInAppUpdates(isWeb: false, platform: TargetPlatform.android),
      isTrue,
    );
    expect(
      supportsInAppUpdates(isWeb: true, platform: TargetPlatform.android),
      isFalse,
    );
    expect(
      supportsInAppUpdates(isWeb: false, platform: TargetPlatform.iOS),
      isFalse,
    );
  });
}
