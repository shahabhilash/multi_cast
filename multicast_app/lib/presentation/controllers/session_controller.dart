import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/enums/stream_role.dart';
import '../../core/enums/connection_state.dart';
import '../../data/models/peer_device.dart';
import '../../data/models/capture_source.dart';
import '../../core/enums/device_type.dart';
import '../../data/models/signaling_message.dart';
import '../../data/services/signaling_client.dart';
import '../../data/services/webrtc_peer_connection_manager.dart';
import '../../data/services/screen_capture_service.dart';
import '../../data/services/webrtc_stats_collector.dart';
import '../../core/utils/adaptive_bitrate_controller.dart';
import '../../data/models/stream_telemetry.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

final signalingClientProvider = Provider((ref) {
  final client = SignalingClient();
  ref.onDispose(() => client.dispose());
  return client;
});

class SessionState {
  final StreamRole role;
  final AppConnectionState connectionState;
  final PeerDevice? remotePeer;
  final StreamTelemetry? telemetry;
  final List<String> errorLogs;
  final String? localPeerId;
  final String? roomId;

  SessionState({
    this.role = StreamRole.none,
    this.connectionState = AppConnectionState.idle,
    this.remotePeer,
    this.telemetry,
    this.errorLogs = const [],
    this.localPeerId,
    this.roomId,
  });

  SessionState copyWith({
    StreamRole? role,
    AppConnectionState? connectionState,
    PeerDevice? remotePeer,
    StreamTelemetry? telemetry,
    List<String>? errorLogs,
    String? localPeerId,
    String? roomId,
  }) {
    return SessionState(
      role: role ?? this.role,
      connectionState: connectionState ?? this.connectionState,
      remotePeer: remotePeer ?? this.remotePeer,
      telemetry: telemetry ?? this.telemetry,
      errorLogs: errorLogs ?? this.errorLogs,
      localPeerId: localPeerId ?? this.localPeerId,
      roomId: roomId ?? this.roomId,
    );
  }
}

class SessionController extends StateNotifier<SessionState> {
  final Ref _ref;
  StreamSubscription<SignalingMessage>? _signalingSubscription;
  StreamSubscription<RTCPeerConnectionState>? _webrtcStateSubscription;
  WebrtcStatsCollector? _statsCollector;
  StreamSubscription<StreamTelemetry>? _telemetrySubscription;
  CaptureSource? _selectedSource;

  SessionController(this._ref) : super(SessionState()) {
    final webrtcManager = _ref.read(webrtcPeerConnectionManagerProvider);
    _webrtcStateSubscription = webrtcManager.onConnectionState.listen((rtcState) {
      _handleWebRTCConnectionState(rtcState);
    });

    // Listen to local ICE candidates and route them to signaling server
    webrtcManager.onLocalIceCandidate.listen((candidate) {
      final client = _ref.read(signalingClientProvider);
      if (state.remotePeer != null && state.localPeerId != null) {
        client.sendCandidate(
          state.remotePeer!.id, 
          {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
          state.localPeerId!,
        );
      }
    });
  }

  void _handleWebRTCConnectionState(RTCPeerConnectionState rtcState) {
    AppConnectionState newState = state.connectionState;
    switch (rtcState) {
      case RTCPeerConnectionState.RTCPeerConnectionStateNew:
      case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
        newState = AppConnectionState.connecting;
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        newState = AppConnectionState.connected;
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        newState = AppConnectionState.disconnected;
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        newState = AppConnectionState.error;
        break;
    }
    
    if (state.connectionState != newState) {
      state = state.copyWith(connectionState: newState);
      
      if (newState == AppConnectionState.connected) {
        _startTelemetry();
      } else if (newState == AppConnectionState.disconnected || newState == AppConnectionState.error) {
        _stopTelemetry();
      }
    }
  }

  void _startTelemetry() {
    final webrtcManager = _ref.read(webrtcPeerConnectionManagerProvider);
    if (webrtcManager.peerConnection == null) return;
    
    _statsCollector = WebrtcStatsCollector(webrtcManager.peerConnection!);
    _telemetrySubscription = _statsCollector!.onStatsUpdated.listen((telemetry) {
      state = state.copyWith(telemetry: telemetry);
      
      if (state.role == StreamRole.receiver) {
        _ref.read(adaptiveBitrateControllerProvider).evaluateReceiverTelemetry(telemetry);
      }
    });
    _statsCollector!.startPolling();

  }

  void _stopTelemetry() {
    _telemetrySubscription?.cancel();
    _statsCollector?.dispose();
    _statsCollector = null;
  }

  void setCaptureSource(CaptureSource? source) {
    _selectedSource = source;
  }

  void initializeSession(StreamRole role, {String? serverUrl, String? roomId, String? localPeerId}) {
    state = state.copyWith(
      role: role,
      connectionState: AppConnectionState.connecting,
      errorLogs: [],
      localPeerId: localPeerId,
      roomId: roomId,
    );

    if (serverUrl != null && roomId != null && localPeerId != null) {
      _connectSignaling(serverUrl, roomId, localPeerId);
    }
  }

  void _connectSignaling(String serverUrl, String roomId, String localPeerId) {
    final client = _ref.read(signalingClientProvider);
    
    try {
      client.connect(serverUrl);
      client.joinRoom(roomId, localPeerId);
      
      _signalingSubscription?.cancel();
      _signalingSubscription = client.messageStream.listen((message) {
        _handleSignalingMessage(message);
      });
      
      state = state.copyWith(connectionState: AppConnectionState.connected);
    } catch (e) {
      logError('Failed to connect to signaling: $e');
    }
  }

  Future<bool> preCaptureScreen({CaptureSource? source}) async {
    final webrtcManager = _ref.read(webrtcPeerConnectionManagerProvider);
    final effectiveSource = source ?? _selectedSource;
    
    try {
      final captureService = _ref.read(screenCaptureServiceProvider);
      if (!webrtcManager.hasLocalStream) {
        final localStream = await captureService.startCapture(source: effectiveSource);
        await webrtcManager.addLocalStream(localStream);
      }
      return true;
    } catch (e) {
      logError('Failed to capture screen stream: $e');
      return false;
    }
  }

  /// Starts the call (Sender Flow) by creating and sending an SDP offer
  Future<void> startCall(PeerDevice targetPeer, {CaptureSource? source}) async {
    bindRemotePeer(targetPeer);
    
    final webrtcManager = _ref.read(webrtcPeerConnectionManagerProvider);
    final effectiveSource = source ?? _selectedSource;
    
    // If a source is provided, start capture and add it to the WebRTC connection
    // For desktop we need a source, for mobile/web we just start capture
    try {
      final captureService = _ref.read(screenCaptureServiceProvider);
      if (!webrtcManager.hasLocalStream) {
        final localStream = await captureService.startCapture(source: effectiveSource);
        await webrtcManager.addLocalStream(localStream);
      }
    } catch (e) {
      logError('Failed to capture screen stream: $e');
      return;
    }

    final offer = await webrtcManager.createOffer();
    
    if (offer != null && state.localPeerId != null) {
      _ref.read(signalingClientProvider).sendOffer(targetPeer.id, {'sdp': offer.sdp, 'type': offer.type}, state.localPeerId!);
    } else {
      logError('Failed to create offer or localPeerId is null.');
    }
  }

  void _handleSignalingMessage(SignalingMessage message) async {
    final webrtcManager = _ref.read(webrtcPeerConnectionManagerProvider);

    switch (message.type) {
      case SignalingMessageType.error:
        logError(message.errorMessage ?? 'Unknown signaling error');
        break;
      case SignalingMessageType.disconnect:
      case SignalingMessageType.peerLeft:
        logError('Peer disconnected.');
        terminateSession();
        break;
      case SignalingMessageType.peerJoined:
        if (state.role == StreamRole.sender && message.peerId != null) {
          final newPeer = PeerDevice(
            id: message.peerId!,
            name: 'Receiver',
            ipAddress: 'Unknown',
            port: 0,
            deviceType: DeviceType.unknown,
          );
          bindRemotePeer(newPeer);
          
          if (webrtcManager.hasLocalStream) {
            startCall(newPeer); // Sender initiates WebRTC offer
          }
        }
        break;
      case SignalingMessageType.offer:
        if (message.sdp != null && message.senderPeerId != null) {
          // Bind the remote peer if not bound
          if (state.remotePeer == null) {
             bindRemotePeer(PeerDevice(
               id: message.senderPeerId!,
               name: 'Unknown Sender',
               ipAddress: 'Unknown',
               port: 0,
               deviceType: DeviceType.unknown,
             ));
          }

          await webrtcManager.handleRemoteOffer(message.sdp!);
          final answer = await webrtcManager.createAnswer();
          
          if (answer != null && state.localPeerId != null) {
            _ref.read(signalingClientProvider).sendAnswer(
              message.senderPeerId!, 
              {'sdp': answer.sdp, 'type': answer.type}, 
              state.localPeerId!
            );
          }
        }
        break;
      case SignalingMessageType.answer:
        if (message.sdp != null) {
          await webrtcManager.handleRemoteAnswer(message.sdp!);
        }
        break;
      case SignalingMessageType.iceCandidate:
        if (message.candidate != null) {
          final rtcCandidate = RTCIceCandidate(
            message.candidate!['candidate'],
            message.candidate!['sdpMid'],
            message.candidate!['sdpMLineIndex'],
          );
          await webrtcManager.addRemoteIceCandidate(rtcCandidate);
        }
        break;
      default:
        break;
    }
  }

  void bindRemotePeer(PeerDevice peer) {
    state = state.copyWith(
      remotePeer: peer,
      connectionState: AppConnectionState.connected,
    );
  }

  void updateMetrics({double? fps, double? bitrate, double? packetLoss, double? latency}) {
    final current = state.telemetry ?? const StreamTelemetry();
    state = state.copyWith(
      telemetry: current.copyWith(
        fps: fps,
        bitrateKbps: bitrate,
        packetsLost: packetLoss?.toInt(),
        latencyMs: latency,
      ),
    );
  }

  void logError(String error) {
    state = state.copyWith(
      errorLogs: [...state.errorLogs, error],
      connectionState: AppConnectionState.error,
    );
  }

  void terminateSession() {
    _stopTelemetry();
    _signalingSubscription?.cancel();
    _ref.read(signalingClientProvider).disconnect();
    _ref.read(screenCaptureServiceProvider).stopCapture();
    state = SessionState(role: StreamRole.none, connectionState: AppConnectionState.disconnected);
  }

  @override
  void dispose() {
    _stopTelemetry();
    _signalingSubscription?.cancel();
    _webrtcStateSubscription?.cancel();
    super.dispose();
  }
}

final sessionProvider = StateNotifierProvider<SessionController, SessionState>((ref) {
  return SessionController(ref);
});

