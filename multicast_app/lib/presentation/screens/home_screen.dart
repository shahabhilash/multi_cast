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
import '../../data/services/supabase_room_service.dart';
import '../../core/constants/app_constants.dart';
import 'sender_screen.dart';
import 'receiver_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _supabaseRoomService = SupabaseRoomService();

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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Active Cloud Streams',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              StreamBuilder<List<Map<String, dynamic>>>(
                stream: _supabaseRoomService.getActiveRoomsStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('Error loading streams: ${snapshot.error}'));
                  }
                  
                  final rooms = snapshot.data ?? [];
                  if (rooms.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32.0),
                        child: Text(
                          'No active cloud streams right now.',
                          style: TextStyle(color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  
                  return ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: rooms.length,
                    itemBuilder: (context, index) {
                      final room = rooms[index];
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.cloud_circle, color: Colors.blue),
                          title: Text(room['title'] ?? 'MultiCast Live Screen'),
                          subtitle: Text('Host: ${room['host_name'] ?? 'Unknown'} • Room: ${room['room_code']}'),
                          trailing: ElevatedButton(
                            onPressed: () {
                              final localIp = ref.read(discoveryProvider).localIp ?? 'receiver_${DateTime.now().millisecondsSinceEpoch}';
                              
                              ref.read(sessionProvider.notifier).initializeSession(
                                StreamRole.receiver,
                                serverUrl: AppConstants.defaultSignalingUrl,
                                roomId: room['room_code'],
                                localPeerId: localIp,
                              );

                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const ReceiverScreen(),
                                ),
                              );
                            },
                            child: const Text('Join'),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
