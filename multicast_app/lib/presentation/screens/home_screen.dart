import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme_provider.dart';
import '../widgets/network_status_bar.dart';
import '../widgets/device_card.dart';
import '../controllers/discovery_controller.dart';
import '../../core/enums/stream_role.dart';
import '../controllers/session_controller.dart';
import '../widgets/source_selector_dialog.dart';
import '../../data/services/screen_capture_service.dart';
import '../../data/models/peer_device.dart';
import '../../data/models/capture_source.dart';
import '../../core/constants/app_constants.dart';
import 'sender_screen.dart';
import 'receiver_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _roomCodeController = TextEditingController();

  @override
  void dispose() {
    _roomCodeController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Start discovery when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(discoveryProvider.notifier).startDiscovery();
    });
  }

  void _showConnectionDialog(BuildContext context, PeerDevice peer, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.screen_share),
                title: const Text('Cast to Peer'),
                onTap: () async {
                  Navigator.pop(context);
                  
                  final captureService = ref.read(screenCaptureServiceProvider);
                  CaptureSource? source;
                  if (captureService.isDesktop) {
                    source = await showSourceSelectorDialog(context);
                    if (source == null) return; // User cancelled
                  }

                  if (!context.mounted) return;

                  final signalingUrl = 'ws://${peer.ipAddress}:8080';
                  final localIp = ref.read(discoveryProvider).localIp ?? 'sender_${DateTime.now().millisecondsSinceEpoch}';
                  
                  ref.read(sessionProvider.notifier).initializeSession(
                    StreamRole.sender,
                    serverUrl: signalingUrl,
                    roomId: 'room_1', // Default room
                    localPeerId: localIp,
                  );

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SenderScreen(
                        targetPeer: peer,
                        captureSource: source,
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.connected_tv),
                title: const Text('Receive Stream'),
                onTap: () {
                  Navigator.pop(context);
                  
                  final signalingUrl = 'ws://${peer.ipAddress}:8080';
                  final localIp = ref.read(discoveryProvider).localIp ?? 'receiver_${DateTime.now().millisecondsSinceEpoch}';
                  
                  ref.read(sessionProvider.notifier).initializeSession(
                    StreamRole.receiver,
                    serverUrl: signalingUrl,
                    roomId: 'room_1',
                    localPeerId: localIp,
                  );

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ReceiverScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final discoveryState = ref.watch(discoveryProvider);
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('MultiCast'),
        actions: [
          IconButton(
            icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
            onPressed: () {
              ref.read(themeModeProvider.notifier).state =
                  isDark ? ThemeMode.light : ThemeMode.dark;
            },
            tooltip: 'Toggle Theme',
          ),
          if (discoveryState.isDiscovering)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                ref.read(discoveryProvider.notifier).startDiscovery();
              },
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const NetworkStatusBar(),
              const SizedBox(height: 24),
              Text(
                'Quick Actions',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please select a peer from the list below to cast.')),
                        );
                      },
                      icon: const Icon(Icons.screen_share),
                      label: const Text('Share My Screen'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please select a peer from the list below to receive a stream.')),
                        );
                      },
                      icon: const Icon(Icons.connected_tv),
                      label: const Text('Join a Screen'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Discovered Peers',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    '${discoveryState.discoveredPeers.length} found',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (discoveryState.discoveredPeers.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Text(
                      'Searching for peers on your local network...',
                      style: TextStyle(color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: discoveryState.discoveredPeers.length,
                  itemBuilder: (context, index) {
                    final peer = discoveryState.discoveredPeers[index];
                    return DeviceCard(
                      deviceName: peer.name,
                      ipAddress: peer.ipAddress,
                      deviceType: peer.deviceType,
                      onTap: () {
                        _showConnectionDialog(context, peer, ref);
                      },
                    );
                  },
                ),
                
              const SizedBox(height: 32),
              Text(
                'Join Cloud Stream',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _roomCodeController,
                      decoration: const InputDecoration(
                        labelText: 'Room Code',
                        hintText: 'e.g. 123-456',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.meeting_room),
                      ),
                      keyboardType: TextInputType.text,
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    onPressed: () {
                      final roomCode = _roomCodeController.text.trim();
                      if (roomCode.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please enter a valid room code.')),
                        );
                        return;
                      }

                      final localIp = ref.read(discoveryProvider).localIp ?? 'receiver_${DateTime.now().millisecondsSinceEpoch}';
                      
                      ref.read(sessionProvider.notifier).initializeSession(
                        StreamRole.receiver,
                        serverUrl: AppConstants.defaultSignalingUrl,
                        roomId: roomCode,
                        localPeerId: localIp,
                      );

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ReceiverScreen(),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                    ),
                    child: const Text('Join'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
