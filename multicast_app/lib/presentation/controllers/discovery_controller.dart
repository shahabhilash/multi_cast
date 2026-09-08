import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/peer_device.dart';
import '../../data/services/network_info_service.dart';
import '../../data/services/mdns_broadcast_service.dart';
import '../../data/services/mdns_discovery_service.dart';
import '../../data/services/local_signaling_server.dart';
import 'package:flutter/foundation.dart';

final networkInfoServiceProvider = Provider((ref) => NetworkInfoService());
final mdnsBroadcastServiceProvider = Provider((ref) => MdnsBroadcastService());

class DiscoveryState {
  final String? localIp;
  final bool isDiscovering;
  final List<PeerDevice> discoveredPeers;
  final String? errorMessage;

  DiscoveryState({
    this.localIp,
    this.isDiscovering = false,
    this.discoveredPeers = const [],
    this.errorMessage,
  });

  DiscoveryState copyWith({
    String? localIp,
    bool? isDiscovering,
    List<PeerDevice>? discoveredPeers,
    String? errorMessage,
    bool clearError = false,
  }) {
    return DiscoveryState(
      localIp: localIp ?? this.localIp,
      isDiscovering: isDiscovering ?? this.isDiscovering,
      discoveredPeers: discoveredPeers ?? this.discoveredPeers,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class DiscoveryController extends StateNotifier<DiscoveryState> {
  final Ref _ref;
  MdnsDiscoveryService? _discoveryService;

  DiscoveryController(this._ref) : super(DiscoveryState()) {
    _initNetwork();
  }

  Future<void> _initNetwork() async {
    final ip = await _ref.read(networkInfoServiceProvider).getLocalIpAddress();
    if (ip != null) {
      setLocalIp(ip);
    }
  }

  @override
  void dispose() {
    stopDiscovery();
    super.dispose();
  }

  void setLocalIp(String ip) {
    state = state.copyWith(localIp: ip);
  }

  Future<void> startDiscovery() async {
    state = state.copyWith(isDiscovering: true, clearError: true);
    
    try {
      // Start the local signaling server to broker P2P connections directly
      await _ref.read(localSignalingServerProvider).start(port: 8080);
      
      // Typically, deviceName is fetched from preferences or device_info_plus.
      // We use a fallback name for now.
      await _ref.read(mdnsBroadcastServiceProvider).startBroadcasting(
        deviceName: 'MultiCast Device',
        deviceType: 'unknown',
        signalingPort: 8080,
      );
    } catch (e) {
      debugPrint('Broadcast or Signaling Server failed to start: $e');
    }

    _discoveryService ??= MdnsDiscoveryService(
      onPeerFound: addPeer,
      onPeerLost: removePeer,
      onError: setError,
    );

    await _discoveryService?.startDiscovery();
  }

  Future<void> stopDiscovery() async {
    await _ref.read(mdnsBroadcastServiceProvider).stopBroadcasting();
    await _discoveryService?.stopDiscovery();
    // Stop the local signaling server
    await _ref.read(localSignalingServerProvider).stop();
    state = state.copyWith(isDiscovering: false);
  }

  void addPeer(PeerDevice peer) {
    if (!state.discoveredPeers.any((p) => p.id == peer.id)) {
      state = state.copyWith(
        discoveredPeers: [...state.discoveredPeers, peer],
      );
    } else {
      updatePeer(peer);
    }
  }

  void updatePeer(PeerDevice peer) {
    final updatedPeers = state.discoveredPeers.map((p) {
      return p.id == peer.id ? peer : p;
    }).toList();
    state = state.copyWith(discoveredPeers: updatedPeers);
  }

  void removePeer(String peerId) {
    final updatedPeers = state.discoveredPeers.where((p) => p.id != peerId).toList();
    state = state.copyWith(discoveredPeers: updatedPeers);
  }

  void clearPeers() {
    state = state.copyWith(discoveredPeers: []);
  }

  void setError(String error) {
    state = state.copyWith(
      isDiscovering: false,
      errorMessage: error,
    );
  }
}

final discoveryProvider = StateNotifierProvider<DiscoveryController, DiscoveryState>((ref) {
  return DiscoveryController(ref);
});
