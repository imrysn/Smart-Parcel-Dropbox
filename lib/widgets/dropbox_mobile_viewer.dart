import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

class DropboxMobileViewer extends StatefulWidget {
  const DropboxMobileViewer({
    super.key,
    required this.preview,
    required this.stateJson,
    required this.onDoorSelected,
  });

  final Widget preview;
  final String stateJson;
  final ValueChanged<String> onDoorSelected;

  @override
  State<DropboxMobileViewer> createState() => _DropboxMobileViewerState();
}

class _DropboxMobileViewerState extends State<DropboxMobileViewer> {
  static const _files = {
    'cabinet-viewer.html': 'text/html',
    'cabinet-viewer.js': 'text/javascript',
    'cabinet-viewer.css': 'text/css',
    'three-viewer-engine.js': 'text/javascript',
    'parcel-physics.js': 'text/javascript',
    'cannon-es.min.js': 'text/javascript',
    'smart-parcel-dropbox.glb': 'model/gltf-binary',
    'smart-parcel-dropbox.png': 'image/png',
  };
  HttpServer? _server;
  WebViewController? _controller;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      final controller = WebViewController();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      if (!mounted) {
        await server.close(force: true);
        return;
      }
      _server = server;
      server.listen(_serveAsset);
      final page = Uri.http('127.0.0.1:${server.port}', 'cabinet-viewer.html');
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setBackgroundColor(Colors.transparent);
      await controller.addJavaScriptChannel(
        'SpdDoorSelection',
        onMessageReceived: (message) => _receiveMessage(message.message),
      );
      await controller.setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) => request.url == page.toString()
            ? NavigationDecision.navigate
            : NavigationDecision.prevent,
        onWebResourceError: (error) {
          if (error.isForMainFrame == true) _showFallback();
        },
      ));
      if (!mounted) return;
      setState(() => _controller = controller);
      await controller.loadRequest(page);
    } catch (error) {
      debugPrint('Dropbox mobile viewer: $error');
      _showFallback();
    }
  }

  Future<void> _serveAsset(HttpRequest request) async {
    final response = request.response;
    try {
      final segments = request.uri.pathSegments;
      final name = segments.length == 1 ? segments.single : '';
      final type = _files[name];
      if (request.method != 'GET' || type == null) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      final data = await rootBundle.load('assets/dropbox/$name');
      response.headers.contentType = ContentType.parse(type);
      response
          .add(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    } catch (_) {
      response.statusCode = HttpStatus.internalServerError;
    } finally {
      await response.close();
    }
  }

  void _receiveMessage(String message) {
    if (!mounted || _failed) return;
    switch (message) {
      case 'viewer-ready':
        _ready = true;
        unawaited(_updateScene());
      case 'viewer-error':
        _showFallback();
      case 'top' || 'pickup' || 'received':
        widget.onDoorSelected(message);
    }
  }

  void _showFallback() {
    if (mounted && !_failed) setState(() => _failed = true);
  }

  @override
  void didUpdateWidget(covariant DropboxMobileViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stateJson != widget.stateJson) unawaited(_updateScene());
  }

  Future<void> _updateScene() async {
    if (!_ready || _failed) return;
    try {
      await _controller
          ?.runJavaScript('window.setCabinetState(${widget.stateJson})');
    } catch (error) {
      debugPrint('Dropbox mobile viewer: $error');
      _showFallback();
    }
  }

  @override
  void dispose() {
    unawaited(_server?.close(force: true));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_failed || controller == null) return widget.preview;
    return WebViewWidget(controller: controller);
  }
}
