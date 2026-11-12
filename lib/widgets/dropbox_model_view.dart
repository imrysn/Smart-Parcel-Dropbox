import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import 'dropbox_mobile_viewer.dart';
import 'dropbox_web_viewer_stub.dart'
    if (dart.library.js_interop) 'dropbox_web_viewer.dart';
import 'dropbox_windows_viewer.dart';

class DropboxModelView extends StatefulWidget {
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
  State<DropboxModelView> createState() => _DropboxModelViewState();
}

class _DropboxModelViewState extends State<DropboxModelView> {
  Map<String, Object>? _view;
  int _viewId = 0;

  void _showSide(String side) {
    setState(() => _view = {'side': side, 'id': ++_viewId});
  }

  @override
  Widget build(BuildContext context) {
    final windows = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    final mobile = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    final stateJson = jsonEncode({
      'doors': widget.openDoors,
      'parcels': widget.parcelCount,
      'view': _view,
    });
    final preview = Image.asset(
      'assets/dropbox/smart-parcel-dropbox.png',
      fit: BoxFit.contain,
      semanticLabel: 'Smart Parcel Dropbox cabinet',
    );
    final viewer = switch ((kIsWeb, windows, mobile)) {
      (true, _, _) => DropboxWebViewer(
          preview: preview,
          stateJson: stateJson,
          onDoorSelected: widget.onDoorSelected,
        ),
      (_, true, _) => DropboxWindowsViewer(
          preview: preview,
          stateJson: stateJson,
          onDoorSelected: widget.onDoorSelected,
        ),
      (_, _, true) => DropboxMobileViewer(
          preview: preview,
          stateJson: stateJson,
          onDoorSelected: widget.onDoorSelected,
        ),
      _ => preview,
    };

    return Stack(
      fit: StackFit.expand,
      children: [
        viewer,
        if (kIsWeb || windows || mobile)
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: PointerInterceptor(
                intercepting:
                    kIsWeb || defaultTargetPlatform == TargetPlatform.iOS,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () => _showSide('front'),
                      child: const Text('Front'),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: () => _showSide('rear'),
                      child: const Text('Rear'),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
