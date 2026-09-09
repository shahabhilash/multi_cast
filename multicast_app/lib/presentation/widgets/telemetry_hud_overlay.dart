import 'package:flutter/material.dart';
import '../../data/models/stream_telemetry.dart';

class TelemetryHudOverlay extends StatelessWidget {
  final StreamTelemetry telemetry;
  final bool isVisible;

  const TelemetryHudOverlay({
    super.key,
    required this.telemetry,
    this.isVisible = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!isVisible) return const SizedBox.shrink();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Container(
          width: 250,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withOpacity(0.1),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'TELEMETRY',
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 1.2,
                    ),
                  ),
                  _buildFpsBadge(),
                ],
              ),
              const Divider(color: Colors.white24, height: 16),
              _buildStatRow('Resolution', '${telemetry.resolutionWidth}x${telemetry.resolutionHeight}'),
              _buildStatRow('Bitrate', _formatBitrate(telemetry.bitrateKbps)),
              _buildStatRow('Latency', '${telemetry.latencyMs.toStringAsFixed(1)} ms'),
              _buildStatRow('Jitter', '${telemetry.jitterMs.toStringAsFixed(1)} ms'),
              _buildStatRow('Packet Loss', '${telemetry.packetsLost}', 
                  isWarning: telemetry.packetsLost > 0),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFpsBadge() {
    Color badgeColor;
    if (telemetry.fps >= 50) {
      badgeColor = Colors.green;
    } else if (telemetry.fps >= 30) {
      badgeColor = Colors.orange;
    } else {
      badgeColor = Colors.red;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.2),
        border: Border.all(color: badgeColor, width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '${telemetry.fps.toStringAsFixed(1)} FPS',
        style: TextStyle(
          color: badgeColor,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value, {bool isWarning = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: isWarning ? Colors.redAccent : Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  String _formatBitrate(double kbps) {
    if (kbps > 1000) {
      return '${(kbps / 1000).toStringAsFixed(2)} Mbps';
    }
    return '${kbps.toStringAsFixed(0)} Kbps';
  }
}
