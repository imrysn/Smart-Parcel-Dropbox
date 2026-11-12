import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'dropbox_mobile_viewer.dart';
import 'dropbox_web_viewer_stub.dart'
    if (dart.library.js_interop) 'dropbox_web_viewer.dart';
import 'dropbox_windows_viewer.dart';

class DropboxModelView extends StatelessWidget {
  const DropboxModelView({
    super.key,
    required this.onDoorSelected,
    required this.openDoors,
    required this.parcelCount,
  });

  final ValueChanged<String> onDoorSelected;
  final Map<String, bool> openDoors;
  final int parcelCount;

  @override
  Widget build(BuildContext context) {
    final windows = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    final mobile = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    final stateJson = jsonEncode({
      'doors': openDoors,
      'parcels': parcelCount,
    });
    final preview = Image.asset(
      'assets/dropbox/smart-parcel-dropbox.png',
      fit: BoxFit.contain,
      semanticLabel: 'Smart Parcel Dropbox cabinet',
    );
    return switch ((kIsWeb, windows, mobile)) {
      (true, _, _) => DropboxWebViewer(
          preview: preview,
          stateJson: stateJson,
          onDoorSelected: onDoorSelected,
        ),
      (_, true, _) => DropboxWindowsViewer(
          preview: preview,
          stateJson: stateJson,
          onDoorSelected: onDoorSelected,
        ),
      (_, _, true) => DropboxMobileViewer(
          preview: preview,
          stateJson: stateJson,
          onDoorSelected: onDoorSelected,
        ),
      _ => preview,
    };
  }
}
