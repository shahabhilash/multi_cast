import 'package:bonsoir/bonsoir.dart';
import '../../core/constants/network_constants.dart';
import 'package:flutter/foundation.dart';

class MdnsBroadcastService {
  BonsoirBroadcast? _broadcast;
  bool _isBroadcasting = false;

  bool get isBroadcasting => _isBroadcasting;

  /// Starts advertising the device over mDNS on the local network.
  Future<void> startBroadcasting({
    required String deviceName,
    required String deviceType,
    required int signalingPort,
  }) async {
    if (_isBroadcasting) {
      await stopBroadcasting();
    }

    try {
      // Define the mDNS service with custom TXT records
      final service = BonsoirService(
        name: deviceName,
        type: NetworkConstants.mdnsServiceName,
        port: signalingPort,
        attributes: {
          NetworkConstants.txtKeyDeviceName: deviceName,
          NetworkConstants.txtKeyDeviceType: deviceType,
          NetworkConstants.txtKeySignalingPort: signalingPort.toString(),
        },
      );

      _broadcast = BonsoirBroadcast(service: service);
      await _broadcast!.ready;
      await _broadcast!.start();
      _isBroadcasting = true;
      debugPrint('mDNS broadcast started for $deviceName');
    } catch (e) {
      debugPrint('Failed to start mDNS broadcast: $e');
      _isBroadcasting = false;
      rethrow;
    }
  }

  /// Stops advertising the mDNS service.
  Future<void> stopBroadcasting() async {
    if (_broadcast != null) {
      try {
        await _broadcast!.stop();
        debugPrint('mDNS broadcast stopped.');
      } catch (e) {
        debugPrint('Error stopping mDNS broadcast: $e');
      } finally {
        _broadcast = null;
        _isBroadcasting = false;
      }
    }
  }
}
