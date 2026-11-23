import 'package:flutter/material.dart';

class DropboxWebViewer extends StatelessWidget {
  const DropboxWebViewer({
    super.key,
    required this.placeholder,
    required String stateJson,
    required ValueChanged<String> onDoorSelected,
    VoidCallback? onBackgroundTap,
  });

  final Widget placeholder;

  @override
  Widget build(BuildContext context) => placeholder;
}
