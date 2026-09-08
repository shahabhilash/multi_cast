import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../data/models/stream_telemetry.dart';
import '../../data/services/webrtc_data_channel_manager.dart';
import '../../data/services/webrtc_peer_connection_manager.dart';
import 'package:flutter/foundation.dart';

class AdaptiveBitrateController {
  final Ref _ref;
  
  // Track last adaptation to prevent thrashing (e.g. max 1 change per 5 seconds)
  DateTime _lastAdaptationTime = DateTime.fromMillisecondsSinceEpoch(0);
  
  // Current active degradation tier (0 = best, 1 = medium, 2 = lowest)
  int _currentTier = 0;

  AdaptiveBitrateController(this._ref) {
    _listenToDataChannel();
  }

  void _listenToDataChannel() {
    final dataChannel = _ref.read(webrtcDataChannelManagerProvider);
    dataChannel.onMessage.listen((message) {
      if (message['type'] == 'RESOLUTION_CHANGE_REQUEST') {
        int requestedTier = message['tier'] ?? 0;
        _applySenderConstraints(requestedTier);
      }
    });
  }

  /// Called on the Receiver side when new telemetry arrives.
  /// If congestion is detected, it requests the Sender to lower quality.
  void evaluateReceiverTelemetry(StreamTelemetry telemetry) {
    // Only evaluate every 5 seconds to prevent ping-ponging
    if (DateTime.now().difference(_lastAdaptationTime).inSeconds < 5) return;

    bool needsDownscale = false;
    bool needsUpscale = false;

    // Detect Congestion: Packet loss > 5% or Latency > 100ms
    if (telemetry.packetsLost > 5 || telemetry.latencyMs > 100) {
      needsDownscale = true;
    } else if (telemetry.packetsLost == 0 && telemetry.latencyMs < 40) {
      needsUpscale = true;
    }

    if (needsDownscale && _currentTier < 2) {
      _currentTier++;
      _requestSenderAdaptation(_currentTier);
      _lastAdaptationTime = DateTime.now();
    } else if (needsUpscale && _currentTier > 0) {
      _currentTier--;
      _requestSenderAdaptation(_currentTier);
      _lastAdaptationTime = DateTime.now();
    }
  }

  void _requestSenderAdaptation(int tier) {
    final dataChannel = _ref.read(webrtcDataChannelManagerProvider);
    dataChannel.sendMessage({
      'type': 'RESOLUTION_CHANGE_REQUEST',
      'tier': tier,
      'resolution': tier == 0 ? '1080p' : (tier == 1 ? '720p' : '480p'),
    });
  }

  /// Called on the Sender side when a RESOLUTION_CHANGE_REQUEST is received.
  Future<void> _applySenderConstraints(int tier) async {
    final webrtcManager = _ref.read(webrtcPeerConnectionManagerProvider);
    final pc = webrtcManager.peerConnection;
    if (pc == null) return;

    final senders = await pc.getSenders();
    for (var sender in senders) {
      if (sender.track?.kind == 'video') {
        final parameters = sender.parameters;
        
        // Ensure encodings array exists
        if (parameters.encodings == null || parameters.encodings!.isEmpty) {
          parameters.encodings = [RTCRtpEncoding()];
        }

        switch (tier) {
          case 0:
            // High Quality
            parameters.encodings![0].maxBitrate = 8000000; // 8 Mbps
            parameters.encodings![0].scaleResolutionDownBy = 1.0;
            break;
          case 1:
            // Medium Quality (720p equivalent scale)
            parameters.encodings![0].maxBitrate = 2500000; // 2.5 Mbps
            parameters.encodings![0].scaleResolutionDownBy = 1.5;
            break;
          case 2:
            // Low Quality (480p equivalent scale)
            parameters.encodings![0].maxBitrate = 800000; // 800 Kbps
            parameters.encodings![0].scaleResolutionDownBy = 2.0;
            break;
        }

        try {
          await sender.setParameters(parameters);
          debugPrint('Sender applied adaptive constraints for tier $tier');
        } catch (e) {
          debugPrint('Failed to set sender parameters: $e');
        }
      }
    }
  }
}

final adaptiveBitrateControllerProvider = Provider<AdaptiveBitrateController>((ref) {
  return AdaptiveBitrateController(ref);
});
