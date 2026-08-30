import 'package:flutter/foundation.dart';

bool supportsInAppUpdates({
  required bool isWeb,
  required TargetPlatform platform,
}) {
  return !isWeb && platform == TargetPlatform.android;
}
