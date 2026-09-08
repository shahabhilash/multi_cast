import 'dart:async';
import 'package:bonsoir/bonsoir.dart';
import '../../core/constants/network_constants.dart';
import '../../core/enums/device_type.dart';
import '../models/peer_device.dart';
import 'package:flutter/foundation.dart';

class MdnsDiscoveryService {
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _subscription;
  bool _isDiscovering = false;

  bool get isDiscovering => _isDiscovering;

  // Callbacks for the controller to handle discovery events
  final void Function(PeerDevice peer) onPeerFound;
  final void Function(String peerId) onPeerLost;
  final void Function(String error)? onError;

  MdnsDiscoveryService({
    required this.onPeerFound,
    required this.onPeerLost,
    this.onError,
  });

  /// Starts scanning for mDNS services on the local network.
  Future<void> startDiscovery() async {
    if (_isDiscovering) {
      await stopDiscovery();
    }

    try {
      _discovery = BonsoirDiscovery(type: NetworkConstants.mdnsServiceName);
      await _discovery!.ready;
      
      _subscription = _discovery!.eventStream!.listen(_handleDiscoveryEvent);
      
      await _discovery!.start();
      _isDiscovering = true;
      debugPrint('mDNS discovery started.');
    } catch (e) {
      debugPrint('Failed to start mDNS discovery: $e');
      _isDiscovering = false;
      onError?.call(e.toString());
    }
  }

  /// Stops scanning for mDNS services.
  Future<void> stopDiscovery() async {
    if (_discovery != null) {
      try {
        await _subscription?.cancel();
        await _discovery!.stop();
        debugPrint('mDNS discovery stopped.');
      } catch (e) {
        debugPrint('Error stopping mDNS discovery: $e');
      } finally {
        _subscription = null;
        _discovery = null;
        _isDiscovering = false;
      }
    }
  }

  void _handleDiscoveryEvent(BonsoirDiscoveryEvent event) {
    if (event.type == BonsoirDiscoveryEventType.discoveryServiceResolved) {
      final service = event.service;
      if (service == null || service.attributes == null) return;
      
      // We know it's resolved if we get this event type
      final peer = _parseServiceToPeer(service as ResolvedBonsoirService);
      if (peer != null) {
        onPeerFound(peer);
      }
    } else if (event.type == BonsoirDiscoveryEventType.discoveryServiceLost) {
      final service = event.service;
      if (service != null) {
        // Use the service name as the unique ID
        onPeerLost(service.name);
      }
    }
  }

  PeerDevice? _parseServiceToPeer(ResolvedBonsoirService service) {
    final attributes = service.attributes;
    if (attributes == null) return null;

    final deviceName = attributes[NetworkConstants.txtKeyDeviceName] ?? service.name;
    final deviceTypeStr = attributes[NetworkConstants.txtKeyDeviceType] ?? '';
    final portStr = attributes[NetworkConstants.txtKeySignalingPort];
    
    int port = service.port;
    if (portStr != null) {
      port = int.tryParse(portStr) ?? service.port;
    }

    // IP resolution: Bonsoir resolved services typically contain the host IP.
    // In bonsoir 3.0.0, the property is 'ip' instead of 'host'.
    String ipAddress = service.ip ?? 'unknown';

    // Map the string type back to our enum
    DeviceType type = DeviceType.unknown;
    for (var value in DeviceType.values) {
      if (value.name.toLowerCase() == deviceTypeStr.toLowerCase()) {
        type = value;
        break;
      }
    }

    return PeerDevice(
      id: service.name, // Use service name as unique identifier
      name: deviceName,
      ipAddress: ipAddress,
      port: port,
      deviceType: type,
    );
  }
}
