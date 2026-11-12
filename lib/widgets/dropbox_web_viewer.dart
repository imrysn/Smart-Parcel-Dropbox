import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

class DropboxWebViewer extends StatefulWidget {
  const DropboxWebViewer({
    super.key,
    required this.preview,
    required this.stateJson,
    required this.onDoorSelected,
  });

  final Widget preview;
  final String stateJson;
  final ValueChanged<String> onDoorSelected;

  @override
  State<DropboxWebViewer> createState() => _DropboxWebViewerState();
}

class _DropboxWebViewerState extends State<DropboxWebViewer> {
  web.HTMLIFrameElement? _frame;
  late final JSFunction _listener;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _listener = ((web.MessageEvent event) {
      final source = _frame?.contentWindow;
      if (!mounted ||
          source == null ||
          event.origin != web.window.location.origin ||
          event.source?.strictEquals(source).toDart != true) return;
      switch (event.data.dartify()) {
        case 'viewer-ready':
          _ready = true;
          _sendState();
        case 'viewer-error':
          setState(() => _failed = true);
        case final String door
            when const {'top', 'pickup', 'received'}.contains(door):
          widget.onDoorSelected(door);
      }
    }).toJS;
    web.window.addEventListener('message', _listener);
  }

  @override
  void didUpdateWidget(covariant DropboxWebViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stateJson != widget.stateJson) _sendState();
  }

  void _sendState() {
    if (!_ready) return;
    final Object? state = jsonDecode(widget.stateJson);
    _frame?.contentWindow?.postMessage(
      state.jsify(),
      web.window.location.origin.toJS,
    );
  }

  @override
  void dispose() {
    web.window.removeEventListener('message', _listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return widget.preview;
    return HtmlElementView.fromTagName(
      tagName: 'iframe',
      onElementCreated: (element) {
        final frame = element as web.HTMLIFrameElement;
        _frame = frame;
        frame
          ..title = 'Interactive 3D Dropbox cabinet'
          ..src = 'assets/assets/dropbox/cabinet-viewer.html';
        frame.style.border = '0';
        frame.style.width = '100%';
        frame.style.height = '100%';
      },
    );
  }
}
