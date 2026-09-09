import 'package:flutter/material.dart';

import '../../core/enums/device_type.dart';

class DeviceCard extends StatelessWidget {
  final String deviceName;
  final String ipAddress;
  final DeviceType deviceType;
  final VoidCallback onTap;

  const DeviceCard({
    super.key,
    required this.deviceName,
    required this.ipAddress,
    required this.deviceType,
    required this.onTap,
  });

  IconData _getDeviceIcon() {
    switch (deviceType) {
      case DeviceType.windows:
        return Icons.window;
      case DeviceType.macOS:
      case DeviceType.iOS:
        return Icons.apple; // Note: Cupertino icons might be better depending on preference
      case DeviceType.android:
        return Icons.android;
      case DeviceType.unknown:
        return Icons.devices;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _getDeviceIcon(),
                  color: Theme.of(context).colorScheme.primary,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      deviceName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ipAddress,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
