import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

class DropboxWindowsViewer extends StatefulWidget {
  const DropboxWindowsViewer({
    super.key,
    required this.preview,
    required this.onDoorSelected,
    required this.stateJson,
  });

  final Widget preview;
  final ValueChanged<String> onDoorSelected;
  final String stateJson;

  @override
  State<DropboxWindowsViewer> createState() => _DropboxWindowsViewerState();
}

class _DropboxWindowsViewerState extends State<DropboxWindowsViewer> {
  static const _host = 'spd-model.example';
  final _controller = WebviewController();
  StreamSubscription<dynamic>? _messages;
  StreamSubscription<WebErrorStatus>? _navigationErrors;
  Timer? _loadTimeout;
  bool _initialized = false;
  bool _failed = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleModifier);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize();
      if (!mounted) return;
      final executable = Uri.file(Platform.resolvedExecutable);
      final assets =
          Directory.fromUri(executable.resolve('data/flutter_assets/'));
      await _controller.addVirtualHostNameMapping(
        _host,
        assets.path,
        WebviewHostResourceAccessKind.deny,
      );
      await _controller.setBackgroundColor(Colors.transparent);
      await _controller.setDefaultContextMenusEnabled(false);
      await _controller.setZoomControlEnabled(false);
      if (!mounted) return;
      _messages = _controller.webMessage.listen(_receiveMessage);
      _navigationErrors = _controller.onLoadError.listen(_showFallback);
      _loadTimeout = Timer(
        const Duration(seconds: 20),
        () => _showFallback('The model did not finish loading'),
      );
      setState(() => _initialized = true);
      await _controller
          .loadUrl('https://$_host/assets/dropbox/cabinet-viewer.html');
    } catch (error) {
      _showFallback(error);
    }
  }

  void _receiveMessage(dynamic message) {
    if (!mounted || _failed) return;
    switch (message) {
      case 'viewer-ready':
        _loadTimeout?.cancel();
        _ready = true;
        unawaited(_updateScene());
        unawaited(_updateModifiers());
      case 'viewer-error':
        _showFallback('The model could not be rendered');
      case 'top' || 'pickup' || 'received':
        widget.onDoorSelected(message as String);
    }
  }

  @override
  void didUpdateWidget(covariant DropboxWindowsViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stateJson != widget.stateJson) unawaited(_updateScene());
  }

  Future<void> _updateScene() async {
    if (!_ready || _failed) return;
    try {
      await _controller
          .executeScript('window.setCabinetState(${widget.stateJson})');
    } catch (error) {
      _showFallback(error);
    }
  }

  bool _handleModifier(KeyEvent event) {
    if (LogicalKeyboardKey.collapseSynonyms({event.logicalKey}).any((key) =>
        key == LogicalKeyboardKey.control || key == LogicalKeyboardKey.shift)) {
      unawaited(_updateModifiers());
    }
    return false;
  }

  Future<void> _updateModifiers() async {
    if (!_ready || _failed) return;
    final keyboard = HardwareKeyboard.instance;
    try {
      await _controller.executeScript('window.setCabinetWheelModifiers('
          '${keyboard.isControlPressed}, ${keyboard.isShiftPressed})');
    } catch (error) {
      debugPrint('Dropbox Windows camera input: $error');
    }
  }

  void _showFallback(Object error) {
    _loadTimeout?.cancel();
    if (!mounted || _failed) return;
    debugPrint('Dropbox Windows 3D viewer: $error');
    setState(() => _failed = true);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleModifier);
    _loadTimeout?.cancel();
    unawaited(_messages?.cancel());
    unawaited(_navigationErrors?.cancel());
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_initialized && !_failed) {
      return Webview(_controller);
    }
    if (!_failed) return widget.preview;
    return Column(
      children: [
        Expanded(child: widget.preview),
        Text('3D viewer unavailable',
            style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
