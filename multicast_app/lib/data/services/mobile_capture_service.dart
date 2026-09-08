import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';

class MobileCaptureService {
  MediaStream? _currentStream;

  Future<MediaStream> startMobileScreenCapture({int fps = 60, int maxBitrate = 6000000}) async {
    // Stop any existing stream before starting a new one
    await stopCapture();
    
    final micStatus = await Permission.microphone.request();
    final bool hasAudio = micStatus.isGranted;

    final Map<String, dynamic> mediaConstraints = {
      'audio': hasAudio, // Android 10+ supports internal audio capture via MediaProjection
      'video': {
        'mandatory': {
          'minFrameRate': fps,
          'maxFrameRate': fps,
        },
        'optional': [
          {'googCpuOveruseDetection': true},
          {'googCpuOveruseEncodeUsage': true}
        ]
      }
    };

    try {
      _currentStream = await navigator.mediaDevices.getDisplayMedia(mediaConstraints);
      return _currentStream!;
    } catch (e) {
      debugPrint('Error starting mobile screen capture: $e');
      rethrow;
    }
  }

  Future<void> stopCapture() async {
    if (_currentStream != null) {
      for (var track in _currentStream!.getTracks()) {
        track.stop();
      }
      await _currentStream!.dispose();
      _currentStream = null;
    }
  }
}

final mobileCaptureServiceProvider = Provider<MobileCaptureService>((ref) {
  return MobileCaptureService();
});
