import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:window_manager/window_manager.dart';

class StreamControlBar extends StatefulWidget {
  final RTCVideoViewObjectFit currentFit;
  final ValueChanged<RTCVideoViewObjectFit> onFitToggle;
  final VoidCallback onHudToggle;
  final VoidCallback onDisconnect;

  const StreamControlBar({
    super.key,
    required this.currentFit,
    required this.onFitToggle,
    required this.onHudToggle,
    required this.onDisconnect,
  });

  @override
  State<StreamControlBar> createState() => _StreamControlBarState();
}

class _StreamControlBarState extends State<StreamControlBar> {
  bool _isVisible = true;
  bool _isFullscreen = false;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _startHideTimer();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    setState(() => _isVisible = true);
    
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _isVisible = false);
      }
    });
  }

  Future<void> _toggleFullscreen() async {
    _isFullscreen = !_isFullscreen;

    if (kIsWeb) {
      // Basic web fullscreen relies on browser APIs which require JS interop,
      // skipping for this internal implementation layer.
      return;
    }

    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      await windowManager.setFullScreen(_isFullscreen);
    } else if (Platform.isAndroid || Platform.isIOS) {
      if (_isFullscreen) {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    // Ensure we restore UI mode when leaving the screen
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } else if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      windowManager.setFullScreen(false);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: (_) => _startHideTimer(),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _startHideTimer,
        child: AnimatedOpacity(
          opacity: _isVisible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 32.0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        widget.currentFit == RTCVideoViewObjectFit.RTCVideoViewObjectFitContain
                            ? Icons.aspect_ratio
                            : Icons.crop_free,
                        color: Colors.white,
                      ),
                      tooltip: 'Toggle Fit',
                      onPressed: () {
                        _startHideTimer();
                        widget.onFitToggle(
                          widget.currentFit == RTCVideoViewObjectFit.RTCVideoViewObjectFitContain
                              ? RTCVideoViewObjectFit.RTCVideoViewObjectFitCover
                              : RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                        );
                      },
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      icon: Icon(
                        _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                        color: Colors.white,
                      ),
                      tooltip: 'Toggle Fullscreen',
                      onPressed: () {
                        _startHideTimer();
                        _toggleFullscreen();
                      },
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      icon: const Icon(Icons.info_outline, color: Colors.white),
                      tooltip: 'Toggle HUD',
                      onPressed: () {
                        _startHideTimer();
                        widget.onHudToggle();
                      },
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      icon: const Icon(Icons.call_end, color: Colors.redAccent),
                      tooltip: 'Disconnect',
                      onPressed: widget.onDisconnect,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
