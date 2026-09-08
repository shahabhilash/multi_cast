import 'dart:io';
import 'package:flutter/foundation.dart';

class NetworkInfoService {
  /// Fetches the local IPv4 address of the device on the Wi-Fi or local network.
  Future<String?> getLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      // Prioritize common Wi-Fi / Ethernet interface names
      for (var interface in interfaces) {
        if (interface.name.contains('wlan') ||
            interface.name.contains('en') ||
            interface.name.contains('eth') || 
            interface.name.contains('Wi-Fi')) {
          for (var address in interface.addresses) {
            if (!address.isLoopback) {
              return address.address;
            }
          }
        }
      }
      
      // Fallback: return the first non-loopback IPv4 address
      for (var interface in interfaces) {
        for (var address in interface.addresses) {
          if (!address.isLoopback) {
            return address.address;
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching local IP address: $e');
    }
    return null;
  }
}
