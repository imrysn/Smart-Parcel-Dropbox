import 'package:flutter/foundation.dart';

abstract final class DevMode {
  static const preferenceKey = 'dropbox_dev_mode';

  static bool get isSupported =>
      kIsWeb ||
      const {
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.windows,
      }.contains(defaultTargetPlatform);

  static bool isEnabled(String? savedPreference) {
    final enabledByDefault =
        kDebugMode && !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    return isSupported &&
        (savedPreference == null ? enabledByDefault : savedPreference == 'true');
  }
}
