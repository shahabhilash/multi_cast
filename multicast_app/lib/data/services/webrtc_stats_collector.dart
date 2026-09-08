import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../models/stream_telemetry.dart';
import 'package:flutter/foundation.dart';

class WebrtcStatsCollector {
  final RTCPeerConnection _peerConnection;
  Timer? _pollingTimer;
  final StreamController<StreamTelemetry> _statsController = StreamController<StreamTelemetry>.broadcast();

  // Used for calculating bitrates and deltas
  int _lastBytesReceived = 0;
  int _lastBytesSent = 0;
  int _lastTimestamp = 0;
  int _lastPacketsLost = 0;

  WebrtcStatsCollector(this._peerConnection);

  Stream<StreamTelemetry> get onStatsUpdated => _statsController.stream;

  void startPolling({Duration interval = const Duration(seconds: 1)}) {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(interval, (timer) async {
      await _fetchAndParseStats();
    });
  }

  void stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  Future<void> _fetchAndParseStats() async {
    try {
      final List<StatsReport> stats = await _peerConnection.getStats();

      double fps = 0.0;
      double latencyMs = 0.0;
      double bitrateKbps = 0.0;
      int packetsLost = 0;
      double jitterMs = 0.0;
      int width = 0;
      int height = 0;

      int currentTimestamp = DateTime.now().millisecondsSinceEpoch;
      int bytesReceived = 0;
      int bytesSent = 0;
      
      bool isReceiving = false;

      for (var report in stats) {
        if (report.type == 'inbound-rtp' && report.values['mediaType'] == 'video') {
          isReceiving = true;
          fps = double.tryParse(report.values['framesPerSecond']?.toString() ?? '0') ?? 0.0;
          packetsLost = int.tryParse(report.values['packetsLost']?.toString() ?? '0') ?? 0;
          jitterMs = (double.tryParse(report.values['jitter']?.toString() ?? '0') ?? 0.0) * 1000;
          
          if (report.values.containsKey('frameWidth')) {
            width = int.tryParse(report.values['frameWidth']?.toString() ?? '0') ?? 0;
            height = int.tryParse(report.values['frameHeight']?.toString() ?? '0') ?? 0;
          }
          
          bytesReceived = int.tryParse(report.values['bytesReceived']?.toString() ?? '0') ?? 0;
        } 
        else if (report.type == 'outbound-rtp' && report.values['mediaType'] == 'video') {
          fps = double.tryParse(report.values['framesPerSecond']?.toString() ?? '0') ?? 0.0;
          packetsLost = int.tryParse(report.values['packetsLost']?.toString() ?? '0') ?? 0;
          
          if (report.values.containsKey('frameWidth')) {
            width = int.tryParse(report.values['frameWidth']?.toString() ?? '0') ?? 0;
            height = int.tryParse(report.values['frameHeight']?.toString() ?? '0') ?? 0;
          }
          
          bytesSent = int.tryParse(report.values['bytesSent']?.toString() ?? '0') ?? 0;
        }
        else if (report.type == 'candidate-pair' && report.values['state'] == 'succeeded') {
          latencyMs = (double.tryParse(report.values['currentRoundTripTime']?.toString() ?? '0') ?? 0.0) * 1000;
        }
      }

      // Calculate bitrate based on bytes delta
      if (_lastTimestamp > 0) {
        int timeDelta = currentTimestamp - _lastTimestamp;
        if (timeDelta > 0) {
          if (isReceiving) {
            int bytesDelta = bytesReceived - _lastBytesReceived;
            bitrateKbps = (bytesDelta * 8) / timeDelta;
          } else {
            int bytesDelta = bytesSent - _lastBytesSent;
            bitrateKbps = (bytesDelta * 8) / timeDelta;
          }
        }
      }

      _lastTimestamp = currentTimestamp;
      _lastBytesReceived = bytesReceived;
      _lastBytesSent = bytesSent;
      
      // Calculate packet loss delta to only report recent packet loss
      int packetLossDelta = packetsLost - _lastPacketsLost;
      _lastPacketsLost = packetsLost;

      if (packetLossDelta < 0) packetLossDelta = 0; // Prevent negative values

      final telemetry = StreamTelemetry(
        fps: fps,
        latencyMs: latencyMs,
        bitrateKbps: bitrateKbps,
        packetsLost: packetLossDelta,
        jitterMs: jitterMs,
        resolutionWidth: width,
        resolutionHeight: height,
      );

      _statsController.add(telemetry);

    } catch (e) {
      debugPrint('Failed to collect WebRTC stats: $e');
    }
  }

  void dispose() {
    stopPolling();
    _statsController.close();
  }
}
