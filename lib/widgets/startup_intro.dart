import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class StartupIntro extends StatefulWidget {
  const StartupIntro({
    super.key,
    required this.onFinished,
    this.showEndCard = false,
  });

  static const asset = 'assets/dropbox/cabinet-startup.webp';
  static const background = Color(0xFFF6F5F3);
  static const frameCount = 123;
  static const finalFrameHold = Duration(milliseconds: 100);
  static const title = 'Smart Parcel Dropbox';

  /// Passes true after playback or false if the clip fails to load.
  final ValueChanged<bool> onFinished;
  final bool showEndCard;

  @override
  State<StartupIntro> createState() => _StartupIntroState();
}

class _StartupIntroState extends State<StartupIntro> {
  // A separate bundle gives each replay a fresh animated image cache key.
  final _bundle = PlatformAssetBundle();
  late final _image = AssetImage(StartupIntro.asset, bundle: _bundle);
  late final Timer _loadTimeout;
  Timer? _finalFrameTimer;
  bool _finished = false;
  bool _showTitle = false;

  @override
  void initState() {
    super.initState();
    _loadTimeout =
        Timer(const Duration(seconds: 4), () => _complete(played: false));
  }

  void _finishPlayback() {
    if (_finished || !mounted) return;
    if (widget.showEndCard) {
      setState(() => _showTitle = true);
    } else {
      _complete(played: true);
    }
  }

  void _complete({required bool played}) {
    if (_finished || !mounted) return;
    _finished = true;
    _loadTimeout.cancel();
    _finalFrameTimer?.cancel();
    widget.onFinished(played);
  }

  @override
  void dispose() {
    _loadTimeout.cancel();
    _finalFrameTimer?.cancel();
    unawaited(_image.evict());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fillScreen = MediaQuery.sizeOf(context).aspectRatio <= 0.74;
    return Scaffold(
      backgroundColor: StartupIntro.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_showTitle)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  StartupIntro.title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF211C17),
                    fontWeight: FontWeight.w800,
                    fontSize: 27,
                  ),
                ),
              ),
            )
          else
            Image(
              image: _image,
              fit: fillScreen ? BoxFit.cover : BoxFit.contain,
              excludeFromSemantics: true,
              frameBuilder: (context, child, frame, _) {
                if (frame == null || _finished) return child;
                _loadTimeout.cancel();
                // Flutter's image scheduler can take longer than the clip's
                // nominal duration. Wait until the last frame is painted.
                if (frame == StartupIntro.frameCount - 1 &&
                    _finalFrameTimer == null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted || _finished) return;
                    _finalFrameTimer ??=
                        Timer(StartupIntro.finalFrameHold, _finishPlayback);
                  });
                }
                return child;
              },
              errorBuilder: (context, error, stackTrace) {
                WidgetsBinding.instance
                    .addPostFrameCallback((_) => _complete(played: false));
                return const SizedBox.shrink();
              },
            ),
          if (_showTitle)
            SafeArea(
              minimum: const EdgeInsets.all(16),
              child: Align(
                alignment: AlignmentDirectional.bottomEnd,
                child: TextButton(
                  onPressed: () => _complete(played: true),
                  style: TextButton.styleFrom(
                    backgroundColor:
                        StartupIntro.background.withValues(alpha: 0.92),
                    foregroundColor: const Color(0xFF342C24),
                    minimumSize: const Size(56, 44),
                  ),
                  child: const Text('Done'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
