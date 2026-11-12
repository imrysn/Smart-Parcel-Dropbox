import 'package:flutter/material.dart';

class DropboxWebViewer extends StatelessWidget {
  const DropboxWebViewer({
    super.key,
    required this.preview,
    required String stateJson,
    required ValueChanged<String> onDoorSelected,
  });

  final Widget preview;

  @override
  Widget build(BuildContext context) => preview;
}
