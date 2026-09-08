import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/webrtc_config.dart';
import '../../core/utils/sdp_utils.dart';
import 'package:flutter/foundation.dart';

class WebrtcPeerConnectionManager {
  RTCPeerConnection? _peerConnection;
  
  /// Queue for early ICE candidates received before remote description is set
  final List<RTCIceCandidate> _remoteIceCandidateQueue = [];
  bool _isRemoteDescriptionSet = false;
  
  /// Stream controller for local ICE candidates to be sent to signaling server
  final StreamController<RTCIceCandidate> _localIceCandidateController = StreamController<RTCIceCandidate>.broadcast();
  Stream<RTCIceCandidate> get onLocalIceCandidate => _localIceCandidateController.stream;

  /// Stream controller for connection state changes
  final StreamController<RTCPeerConnectionState> _connectionStateController = StreamController<RTCPeerConnectionState>.broadcast();
  Stream<RTCPeerConnectionState> get onConnectionState => _connectionStateController.stream;

  /// Stream controller for remote MediaStream (incoming video/audio)
  final StreamController<MediaStream> _remoteStreamController = StreamController<MediaStream>.broadcast();
  Stream<MediaStream> get onRemoteStream => _remoteStreamController.stream;

  MediaStream? _localStream;
  MediaStream? _remoteStream;

  Future<void> initializePeerConnection() async {
    _peerConnection = await createPeerConnection(WebRTCConfig.defaultConfiguration);

    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      _localIceCandidateController.add(candidate);
    };

    _peerConnection!.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
        _remoteStreamController.add(_remoteStream!);
      }
    };

    _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
      _connectionStateController.add(state);
      
      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateNew:
        case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
          debugPrint('WebRTC Connection State: ${state.name}');
          break;
      }
    };
  }
  
  RTCPeerConnection? get peerConnection => _peerConnection;

  /// Sets the remote description and processes any queued ICE candidates
  Future<void> setRemoteDescription(RTCSessionDescription description) async {
    if (_peerConnection == null) return;
    
    await _peerConnection!.setRemoteDescription(description);
    _isRemoteDescriptionSet = true;
    
    // Flush queued ICE candidates
    for (var candidate in _remoteIceCandidateQueue) {
      await _peerConnection!.addCandidate(candidate);
    }
    _remoteIceCandidateQueue.clear();
  }

  /// Creates an offer to start the session (Sender Flow)
  Future<RTCSessionDescription?> createOffer() async {
    if (_peerConnection == null) return null;

    final constraints = {
      'mandatory': {
        'OfferToReceiveAudio': false, // Senders cast, they don't receive
        'OfferToReceiveVideo': false,
      },
    };

    RTCSessionDescription offer = await _peerConnection!.createOffer(constraints);
    
    // Apply SDP munging for H.264 prioritization and bitrate control
    String optimizedSdp = SdpUtils.optimizeSdp(offer.sdp!);
    RTCSessionDescription optimizedOffer = RTCSessionDescription(optimizedSdp, offer.type);

    await _peerConnection!.setLocalDescription(optimizedOffer);
    
    return optimizedOffer;
  }

  /// Handles the remote answer from the receiver to complete handshake
  Future<void> handleRemoteAnswer(Map<String, dynamic> answerSdp) async {
    if (_peerConnection == null) return;
    
    RTCSessionDescription answer = RTCSessionDescription(
      answerSdp['sdp'],
      answerSdp['type'],
    );
    
    await setRemoteDescription(answer);
  }

  /// Handles the remote offer from the sender and prepares the receiver (Receiver Flow)
  Future<void> handleRemoteOffer(Map<String, dynamic> offerSdp) async {
    if (_peerConnection == null) return;

    RTCSessionDescription offer = RTCSessionDescription(
      offerSdp['sdp'],
      offerSdp['type'],
    );

    // This also flushes any queued ICE candidates automatically
    await setRemoteDescription(offer);
  }

  /// Creates an answer to accept the session (Receiver Flow)
  Future<RTCSessionDescription?> createAnswer() async {
    if (_peerConnection == null) return null;

    final constraints = {
      'mandatory': {
        'OfferToReceiveAudio': true, // Receivers must accept audio and video
        'OfferToReceiveVideo': true,
      },
    };

    RTCSessionDescription answer = await _peerConnection!.createAnswer(constraints);
    await _peerConnection!.setLocalDescription(answer);
    
    return answer;
  }

  /// Adds a remote ICE candidate. Queues it if remote description is not yet set.
  Future<void> addRemoteIceCandidate(RTCIceCandidate candidate) async {
    if (_isRemoteDescriptionSet && _peerConnection != null) {
      await _peerConnection!.addCandidate(candidate);
    } else {
      _remoteIceCandidateQueue.add(candidate);
    }
  }

  /// Triggers an ICE restart to recover from connection drops
  Future<RTCSessionDescription?> restartIce(bool isOffer) async {
    if (_peerConnection == null) return null;
    
    // According to flutter_webrtc docs, we pass iceRestart in constraints
    final constraints = {
      'mandatory': {
        'OfferToReceiveAudio': isOffer ? false : true,
        'OfferToReceiveVideo': isOffer ? false : true,
        'IceRestart': true,
      },
    };

    RTCSessionDescription newDesc;
    if (isOffer) {
      newDesc = await _peerConnection!.createOffer(constraints);
      // Re-apply SDP munging if sender
      String optimizedSdp = SdpUtils.optimizeSdp(newDesc.sdp!);
      newDesc = RTCSessionDescription(optimizedSdp, newDesc.type);
    } else {
      newDesc = await _peerConnection!.createAnswer(constraints);
    }

    await _peerConnection!.setLocalDescription(newDesc);
    return newDesc;
  }

  /// Adds local video and audio tracks from a MediaStream to the RTCPeerConnection
  Future<void> addLocalStream(MediaStream stream) async {
    if (_peerConnection == null) return;
    _localStream = stream;
    
    // Add all tracks from the local stream to the peer connection
    for (var track in stream.getTracks()) {
      await _peerConnection!.addTrack(track, stream);
    }
  }

  Future<void> dispose() async {
    await _localIceCandidateController.close();
    await _connectionStateController.close();
    await _remoteStreamController.close();
    
    if (_localStream != null) {
      for (var track in _localStream!.getTracks()) {
        await track.stop();
      }
      await _localStream!.dispose();
      _localStream = null;
    }
    
    if (_remoteStream != null) {
      for (var track in _remoteStream!.getTracks()) {
        await track.stop();
      }
      await _remoteStream!.dispose();
      _remoteStream = null;
    }
    
    if (_peerConnection != null) {
      final senders = await _peerConnection!.getSenders();
      for (var sender in senders) {
        await sender.track?.stop();
        await _peerConnection!.removeTrack(sender);
      }
      
      await _peerConnection!.close();
      _peerConnection = null;
    }
  }
}

final webrtcPeerConnectionManagerProvider = Provider<WebrtcPeerConnectionManager>((ref) {
  final manager = WebrtcPeerConnectionManager();
  ref.onDispose(() => manager.dispose());
  return manager;
});

