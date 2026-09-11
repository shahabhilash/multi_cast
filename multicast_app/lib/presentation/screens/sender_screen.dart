import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/telemetry_hud_overlay.dart';
import '../../presentation/controllers/session_controller.dart';
import '../../core/enums/connection_state.dart';
import '../../data/models/peer_device.dart';
import 'dart:math';
import '../../core/enums/stream_role.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/capture_source.dart';

class SenderScreen extends ConsumerStatefulWidget {
  final PeerDevice? targetPeer;
  final CaptureSource? captureSource;
  const SenderScreen({super.key, this.targetPeer, this.captureSource});

  @override
  ConsumerState<SenderScreen> createState() => _SenderScreenState();
}

class _SenderScreenState extends ConsumerState<SenderScreen> {
  bool _showHud = true;
  String? _roomCode;

  @override
  void initState() {
    super.initState();
    if (widget.targetPeer != null) {
      // Local network peer
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(sessionProvider.notifier).startCall(widget.targetPeer!, source: widget.captureSource);
      });
    } else {
      // Cloud Stream
      _roomCode = _generateRoomCode();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(sessionProvider.notifier).initializeSession(
          StreamRole.sender,
          serverUrl: AppConstants.defaultSignalingUrl,
          roomId: _roomCode,
          localPeerId: 'sender_${DateTime.now().millisecondsSinceEpoch}',
        );
      });
    }
  }

  String _generateRoomCode() {
    final random = Random();
    final p1 = random.nextInt(900) + 100; // 100-999
    final p2 = random.nextInt(900) + 100; // 100-999
    return '$p1-$p2';
  }

  @override
  Widget build(BuildContext context) {
    final sessionState = ref.watch(sessionProvider);
    final telemetry = sessionState.telemetry;
    final isBroadcasting = sessionState.connectionState == AppConnectionState.connected || 
                           sessionState.connectionState == AppConnectionState.connecting;

    ref.listen<SessionState>(sessionProvider, (previous, next) {
      if (previous?.errorLogs.length != next.errorLogs.length && next.errorLogs.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${next.errorLogs.last}'),
              backgroundColor: Colors.redAccent,
              action: SnackBarAction(
                label: 'Dismiss',
                textColor: Colors.white,
                onPressed: () {},
              ),
            ),
          );
        }
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Broadcast Control'),
      ),
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isBroadcasting
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
                        width: 2,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          isBroadcasting ? Icons.sensors : Icons.sensors_off,
                          size: 64,
                          color: isBroadcasting
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          isBroadcasting ? 'Stream Active' : 'Stream Inactive',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                color: isBroadcasting ? Theme.of(context).colorScheme.primary : null,
                              ),
                        ),
                        const SizedBox(height: 24),
                        if (isBroadcasting && telemetry != null) ...[
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            icon: Icon(_showHud ? Icons.visibility_off : Icons.visibility),
                            label: Text(_showHud ? 'Hide Telemetry' : 'Show Telemetry'),
                            onPressed: () {
                              setState(() {
                                _showHud = !_showHud;
                              });
                            },
                          ),
                        ] else if (!isBroadcasting) ...[
                          Text(
                            'Ready to start broadcasting your screen to connected peers.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                ),
                          ),
                        ],
                        if (_roomCode != null) ...[
                          const SizedBox(height: 24),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  'Your Room Code',
                                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _roomCode!,
                                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 4,
                                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Share this code so others can join your stream!',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                          ),
                        ]
                      ],
                    ),
                  ),
                  const SizedBox(height: 48),
                  ElevatedButton(
                    onPressed: () {
                      if (isBroadcasting) {
                        ref.read(sessionProvider.notifier).terminateSession();
                        if (Navigator.canPop(context)) Navigator.pop(context);
                      } else {
                        if (widget.targetPeer != null) {
                          ref.read(sessionProvider.notifier).startCall(widget.targetPeer!, source: widget.captureSource);
                        } else {
                          // Cloud stream relies on receivers joining. We don't start call here.
                          // It starts automatically when PEER_JOINED is received.
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Waiting for peers to join via Room Code...')),
                          );
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      backgroundColor: isBroadcasting
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.primary,
                      foregroundColor: isBroadcasting ? Colors.white : Colors.black,
                    ),
                    child: Text(
                      isBroadcasting ? 'Stop Broadcast' : 'Start Broadcast',
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Mount HUD overlay if broadcasting and enabled
          if (isBroadcasting && _showHud && telemetry != null)
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: TelemetryHudOverlay(
                  telemetry: telemetry,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
