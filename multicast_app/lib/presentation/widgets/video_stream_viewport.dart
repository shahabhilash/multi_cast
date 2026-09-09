import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class VideoStreamViewport extends StatelessWidget {
  final RTCVideoRenderer? renderer;
  final RTCVideoViewObjectFit objectFit;
  final bool isConnected;

  const VideoStreamViewport({
    super.key,
    required this.renderer,
    this.objectFit = RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
    this.isConnected = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!isConnected || renderer == null || renderer!.srcObject == null) {
      return _buildWaitingState(context);
    }

    return Container(
      color: Colors.black, // Typical background for video players
      child: RTCVideoView(
        renderer!,
        objectFit: objectFit,
        mirror: false,
      ),
    );
  }

  Widget _buildWaitingState(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 60,
              height: 60,
              child: CircularProgressIndicator(
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Waiting for stream...',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'The sender has not started broadcasting yet.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
