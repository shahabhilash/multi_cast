import 'dart:io';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/signaling_message.dart';
import 'package:flutter/foundation.dart';

class LocalSignalingServer {
  HttpServer? _server;
  final Map<String, _Client> _clients = {};
  final Map<String, Set<String>> _rooms = {};
  bool _isRunning = false;

  bool get isRunning => _isRunning;

  Future<void> start({int port = 8080}) async {
    if (_isRunning) return;

    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      _isRunning = true;
      debugPrint('Local Signaling Server running on port $port');

      _server!.listen((HttpRequest request) {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          WebSocketTransformer.upgrade(request).then((WebSocket socket) {
            _handleConnection(socket, request.connectionInfo?.remoteAddress.address ?? 'unknown');
          }).catchError((e) {
            debugPrint('Failed to upgrade to WebSocket: $e');
          });
        } else {
          request.response
            ..statusCode = HttpStatus.forbidden
            ..close();
        }
      });
    } catch (e) {
      debugPrint('Failed to start local signaling server: $e');
      _isRunning = false;
      rethrow;
    }
  }

  Future<void> stop() async {
    if (!_isRunning) return;

    for (var client in _clients.values) {
      await client.socket.close();
    }
    _clients.clear();
    _rooms.clear();
    
    await _server?.close(force: true);
    _server = null;
    _isRunning = false;
    debugPrint('Local Signaling Server stopped.');
  }

  void _handleConnection(WebSocket socket, String clientIp) {
    debugPrint('[Connection] New client connected from $clientIp');
    String? currentPeerId;

    socket.listen(
      (data) {
        try {
          final String jsonData = data is String ? data : utf8.decode(data);
          final message = SignalingMessage.fromJson(jsonData);

          if (message.type == SignalingMessageType.ping) {
            socket.add(SignalingMessage(type: SignalingMessageType.pong).toJson());
            return;
          }

          if (message.type == SignalingMessageType.joinRoom && currentPeerId == null) {
            currentPeerId = message.peerId;
          }

          if (currentPeerId != null) {
            _handleMessage(currentPeerId!, socket, message);
          }
        } catch (e) {
          debugPrint('Invalid message received: $e');
        }
      },
      onDone: () {
        if (currentPeerId != null) {
          _handleDisconnect(currentPeerId!);
        }
      },
      onError: (error) {
        debugPrint('Socket error for peer ${currentPeerId ?? 'unknown'}: $error');
        if (currentPeerId != null) {
          _handleDisconnect(currentPeerId!);
        }
      },
    );
  }

  void _handleMessage(String peerId, WebSocket socket, SignalingMessage message) {
    switch (message.type) {
      case SignalingMessageType.joinRoom:
        _joinRoom(peerId, socket, message.roomId ?? 'default');
        break;
      case SignalingMessageType.offer:
      case SignalingMessageType.answer:
      case SignalingMessageType.iceCandidate:
        if (message.targetPeerId != null) {
          _routeMessage(message.targetPeerId!, message);
        }
        break;
      default:
        debugPrint('Unhandled message type: ${message.type}');
    }
  }

  void _joinRoom(String peerId, WebSocket socket, String roomId) {
    _clients[peerId] = _Client(socket: socket, roomId: roomId);

    if (!_rooms.containsKey(roomId)) {
      _rooms[roomId] = {};
    }
    _rooms[roomId]!.add(peerId);

    debugPrint('Peer $peerId joined room $roomId');

    _sendToClient(peerId, SignalingMessage(
      type: SignalingMessageType.roomJoined,
      roomId: roomId,
      peerId: peerId,
    ));
  }

  void _routeMessage(String targetPeerId, SignalingMessage message) {
    _sendToClient(targetPeerId, message);
  }

  void _broadcastToRoom(String roomId, SignalingMessage message, {String? excludePeerId}) {
    final peers = _rooms[roomId];
    if (peers == null) return;

    for (final peerId in peers) {
      if (peerId != excludePeerId) {
        _sendToClient(peerId, message);
      }
    }
  }

  void _sendToClient(String peerId, SignalingMessage message) {
    final client = _clients[peerId];
    if (client != null && client.socket.readyState == WebSocket.open) {
      client.socket.add(message.toJson());
    } else {
      debugPrint('Cannot send message to peer $peerId - client not found or socket closed');
    }
  }

  void _handleDisconnect(String peerId) {
    final client = _clients[peerId];
    if (client == null) return;

    final roomId = client.roomId;
    _clients.remove(peerId);

    if (roomId != null) {
      final room = _rooms[roomId];
      if (room != null) {
        room.remove(peerId);

        _broadcastToRoom(roomId, SignalingMessage(
          type: SignalingMessageType.peerLeft,
          peerId: peerId,
        ));

        if (room.isEmpty) {
          _rooms.remove(roomId);
        }
      }
      debugPrint('Peer $peerId left room $roomId (disconnected)');
    } else {
      debugPrint('Peer $peerId disconnected');
    }
  }
}

class _Client {
  final WebSocket socket;
  final String? roomId;

  _Client({required this.socket, this.roomId});
}

final localSignalingServerProvider = Provider<LocalSignalingServer>((ref) {
  final server = LocalSignalingServer();
  ref.onDispose(() {
    server.stop();
  });
  return server;
});
