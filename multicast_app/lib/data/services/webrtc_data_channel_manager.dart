import 'dart:async';
import 'dart:convert';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';

class WebrtcDataChannelManager {
  RTCDataChannel? _dataChannel;

  /// Stream controller for incoming DataChannel messages
  final StreamController<Map<String, dynamic>> _messageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onMessage => _messageController.stream;

  /// Initializes the DataChannel as a sender
  Future<void> createDataChannel(RTCPeerConnection peerConnection) async {
    final RTCDataChannelInit dataChannelDict = RTCDataChannelInit()
      ..ordered = true
      ..maxRetransmits = 0;

    _dataChannel = await peerConnection.createDataChannel('multicast_control_channel', dataChannelDict);
    _setupDataChannelListeners();
  }

  /// Called when a remote DataChannel is received (Receiver flow)
  void handleRemoteDataChannel(RTCDataChannel channel) {
    if (channel.label == 'multicast_control_channel') {
      _dataChannel = channel;
      _setupDataChannelListeners();
    }
  }

  void _setupDataChannelListeners() {
    if (_dataChannel == null) return;

    _dataChannel!.onMessage = (RTCDataChannelMessage message) {
      if (message.isBinary) return;
      
      try {
        final decoded = jsonDecode(message.text);
        _handleIncomingMessage(decoded);
      } catch (e) {
        debugPrint('Error decoding DataChannel message: $e');
      }
    };

    _dataChannel!.onDataChannelState = (RTCDataChannelState state) {
      debugPrint('DataChannel State: ${state.name}');
    };
  }

  void _handleIncomingMessage(Map<String, dynamic> message) {
    // We emit the raw message so other components can react
    _messageController.add(message);

    final type = message['type'];
    switch (type) {
      case 'PING':
        _sendPong(message['timestamp']);
        break;
      case 'PONG':
        // RTT handling will be caught by the LatencyMonitor observing onMessage
        break;
      case 'RESOLUTION_CHANGE_REQUEST':
        debugPrint('Received resolution change request: ${message['resolution']}');
        break;
      case 'REMOTE_INPUT_EVENT':
        debugPrint('Received remote input event: ${message['action']}');
        break;
      default:
        debugPrint('Unknown DataChannel message type: $type');
    }
  }

  /// Dispatches a JSON message over the DataChannel
  void sendMessage(Map<String, dynamic> message) {
    if (_dataChannel != null && _dataChannel!.state == RTCDataChannelState.RTCDataChannelOpen) {
      final jsonStr = jsonEncode(message);
      _dataChannel!.send(RTCDataChannelMessage(jsonStr));
    }
  }

  void _sendPong(int originalTimestamp) {
    sendMessage({
      'type': 'PONG',
      'timestamp': originalTimestamp,
    });
  }

  Future<void> dispose() async {
    await _messageController.close();
    if (_dataChannel != null) {
      await _dataChannel!.close();
      _dataChannel = null;
    }
  }
}

final webrtcDataChannelManagerProvider = Provider<WebrtcDataChannelManager>((ref) {
  final manager = WebrtcDataChannelManager();
  ref.onDispose(() => manager.dispose());
  return manager;
});
