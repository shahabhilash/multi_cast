import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../models/capture_source.dart';
import 'package:flutter/services.dart';
import 'base_desktop_capturer.dart';
import 'package:flutter/foundation.dart';

class MacOsCaptureService implements BaseDesktopCapturer {
  static const MethodChannel _channel = MethodChannel('multicast/macos_permissions');

  /// Checks if the app has screen recording permissions on macOS
  Future<bool> checkScreenCapturePermission() async {
    try {
      // In a real app, this would use a platform channel to check CGPreflightScreenCaptureAccess
      // For now, we simulate this or rely on flutter_webrtc's internal handling
      // Let's assume we implement the native side later or it's handled by the OS prompt.
      final bool hasPermission = await _channel.invokeMethod('checkScreenCapturePermission') ?? true;
      return hasPermission;
    } on MissingPluginException {
      // Fallback if native side isn't implemented yet
      return true; 
    } catch (e) {
      debugPrint('Error checking screen capture permission: $e');
      return false;
    }
  }

  /// Requests screen recording permissions by prompting the user on macOS
  Future<void> requestScreenCapturePermission() async {
    try {
      // In a real app, this would use CGRequestScreenCaptureAccess
      await _channel.invokeMethod('requestScreenCapturePermission');
    } on MissingPluginException {
      // Fallback
    } catch (e) {
      debugPrint('Error requesting screen capture permission: $e');
    }
  }

  @override
  Future<List<CaptureSource>> getAvailableSources({bool includeWindows = true}) async {
    // macOS requires permissions before getting sources.
    final hasPermission = await checkScreenCapturePermission();
    if (!hasPermission) {
      await requestScreenCapturePermission();
    }

    final types = [SourceType.Screen];
    if (includeWindows) {
      types.add(SourceType.Window);
    }
    
    // Request desktop sources using flutter_webrtc's desktopCapturer
    final sources = await desktopCapturer.getSources(types: types);
    
    return sources.map((DesktopCapturerSource source) {
      return CaptureSource(
        id: source.id,
        name: source.name,
        type: source.id.startsWith('window:') 
            ? CaptureSourceType.window 
            : CaptureSourceType.screen,
        thumbnail: source.thumbnail,
      );
    }).toList();
  }

  @override
  Future<MediaStream> startCapture(CaptureSource source, {int fps = 60}) async {
    // macOS-specific media constraints
    final Map<String, dynamic> mediaConstraints = {
      'audio': {
        // Audio loopback on macOS usually requires a virtual audio driver (like BlackHole)
        // For standard WebRTC, we can capture microphone or system audio if properly configured
        'mandatory': {
           'echoCancellation': false,
           'noiseSuppression': false,
        }
      }, 
      'video': {
        'mandatory': {
          'chromeMediaSource': 'desktop',
          'chromeMediaSourceId': source.id,
          'minFrameRate': fps,
          'maxFrameRate': fps,
          // High resolution preference for macOS retina displays
          'minWidth': 1280,
          'minHeight': 720,
        }
      }
    };

    try {
      final stream = await navigator.mediaDevices.getDisplayMedia(mediaConstraints);
      return stream;
    } catch (e) {
      debugPrint('Error starting macOS desktop capture: $e');
      rethrow;
    }
  }
}

final macOsCaptureServiceProvider = Provider<MacOsCaptureService>((ref) {
  return MacOsCaptureService();
});
