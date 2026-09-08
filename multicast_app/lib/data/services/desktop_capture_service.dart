import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../models/capture_source.dart';
import 'base_desktop_capturer.dart';
import 'package:flutter/foundation.dart';

class DesktopCaptureService implements BaseDesktopCapturer {
  @override
  Future<List<CaptureSource>> getAvailableSources({bool includeWindows = true}) async {
    final types = [SourceType.Screen];
    if (includeWindows) {
      types.add(SourceType.Window);
    }
    
    // Request desktop sources using flutter_webrtc's desktopCapturer
    final sources = await desktopCapturer.getSources(
      types: types,
    );
    
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
  Future<MediaStream> startCapture(CaptureSource source, {int fps = 60, int maxBitrate = 8000000}) async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': false, // Audio loopback usually requires separate handling on Windows
      'video': {
        'mandatory': {
          'chromeMediaSource': 'desktop',
          'chromeMediaSourceId': source.id,
          'minFrameRate': fps,
          'maxFrameRate': fps,
        }
      }
    };

    try {
      // NOTE: maxBitrate is usually applied on the RTCRtpSender after connection
      // For now, we return the stream as acquired.
      final stream = await navigator.mediaDevices.getDisplayMedia(mediaConstraints);
      return stream;
    } catch (e) {
      debugPrint('Error starting desktop capture: $e');
      rethrow;
    }
  }
}

final desktopCaptureServiceProvider = Provider<DesktopCaptureService>((ref) {
  return DesktopCaptureService();
});
