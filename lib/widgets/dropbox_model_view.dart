import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../config/user_theme.dart';
import 'dropbox_mobile_viewer.dart';
import 'dropbox_web_viewer_stub.dart'
    if (dart.library.js_interop) 'dropbox_web_viewer.dart';
import 'dropbox_weather_scene.dart';
import 'dropbox_windows_viewer.dart';

class DropboxModelView extends StatelessWidget {
  const DropboxModelView({
    super.key,
    required this.onDoorSelected,
    required this.openDoors,
    required this.parcelCount,
    required this.hardwareOnline,
    required this.anyDoorUnlocked,
    required this.headerBuilder,
    this.latestDelivery,
    this.simulationEnabled = false,
  });

  final ValueChanged<String> onDoorSelected;
  final Map<String, bool> openDoors;
  final int parcelCount;
  final bool hardwareOnline;
  final bool? anyDoorUnlocked;
  final DateTime? latestDelivery;
  final Widget Function(Widget? weatherControl) headerBuilder;
  final bool simulationEnabled;

  @override
  Widget build(BuildContext context) => DropboxWeatherScene(
        simulationEnabled: simulationEnabled,
        builder: _buildScene,
      );

  Widget _buildScene(
    BuildContext context,
    Map<String, Object> environment,
    Widget? weatherControl,
    VoidCallback? onBackgroundTap,
  ) {
    final windows = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    final mobile = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    final stateJson = jsonEncode({
      'doors': openDoors,
      'parcels': parcelCount,
      'display': {
        'online': hardwareOnline,
        'unlocked': anyDoorUnlocked,
        'deliveredAt': latestDelivery?.millisecondsSinceEpoch,
      },
      'environment': environment,
      'backgroundTapEnabled': onBackgroundTap != null,
    });
    const loading = Center(
      child: SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: UserTheme.primaryOrange,
        ),
      ),
    );
    final viewer = switch ((kIsWeb, windows, mobile)) {
      (true, _, _) => DropboxWebViewer(
          placeholder: loading,
          stateJson: stateJson,
          onDoorSelected: onDoorSelected,
          onBackgroundTap: onBackgroundTap,
        ),
      (_, true, _) => DropboxWindowsViewer(
          placeholder: loading,
          stateJson: stateJson,
          onDoorSelected: onDoorSelected,
          onBackgroundTap: onBackgroundTap,
        ),
      (_, _, true) => DropboxMobileViewer(
          placeholder: loading,
          stateJson: stateJson,
          onDoorSelected: onDoorSelected,
          onBackgroundTap: onBackgroundTap,
        ),
      _ => loading,
    };

    return Stack(
      fit: StackFit.expand,
      children: [
        viewer,
        headerBuilder(kIsWeb || windows || mobile ? weatherControl : null),
      ],
    );
  }
}
