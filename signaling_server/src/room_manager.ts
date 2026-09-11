import { WebSocket } from 'ws';
import { SignalingMessage, MessageType } from './types/protocol';

interface Client {
  socket: WebSocket;
  roomId?: string;
}

export class RoomManager {
  // Map of peerId -> Client
  private clients: Map<string, Client> = new Map();
  // Map of roomId -> Set of peerIds
  private rooms: Map<string, Set<string>> = new Map();

  /**
   * Register a new client connection. The peerId isn't known until they join a room.
   */
  public handleConnection(socket: WebSocket): void {
    let currentPeerId: string | null = null;

    socket.on('message', (data: string) => {
      try {
        const message = JSON.parse(data) as SignalingMessage;
        
        // When a client sends a JOIN_ROOM message, we register their peerId
        if (message.type === MessageType.JOIN_ROOM && !currentPeerId) {
          currentPeerId = message.peerId;
        }

        if (currentPeerId) {
          this.handleMessage(currentPeerId, socket, message);
        }
      } catch (error) {
        console.error('Invalid message received:', error);
      }
    });

    socket.on('close', () => {
      if (currentPeerId) {
        this.handleDisconnect(currentPeerId);
      }
    });
    
    socket.on('error', (error) => {
      console.error(`Socket error for peer ${currentPeerId || 'unknown'}:`, error);
      if (currentPeerId) {
        this.handleDisconnect(currentPeerId);
      }
    });
  }

  private handleMessage(peerId: string, socket: WebSocket, message: SignalingMessage): void {
    switch (message.type) {
      case MessageType.JOIN_ROOM:
        this.joinRoom(peerId, socket, message.roomId);
        break;
      
      case MessageType.OFFER:
      case MessageType.ANSWER:
      case MessageType.ICE_CANDIDATE:
        this.routeMessage(message.targetPeerId, message);
        break;

      default:
        console.warn('Unhandled message type:', message.type);
    }
  }

  private joinRoom(peerId: string, socket: WebSocket, roomId: string): void {
    // 1. Register client
    this.clients.set(peerId, { socket, roomId });

    // 2. Add to room
    if (!this.rooms.has(roomId)) {
      this.rooms.set(roomId, new Set());
    }
    this.rooms.get(roomId)!.add(peerId);

    console.log(`Peer ${peerId} joined room ${roomId}`);

    // 3. Acknowledge room join
    this.sendToClient(peerId, {
      type: MessageType.ROOM_JOINED,
      roomId,
      peerId,
    });

    // 4. Notify others in the room
    this.broadcastToRoom(roomId, {
      type: MessageType.PEER_JOINED,
      roomId,
      peerId,
    }, peerId);
  }

  private routeMessage(targetPeerId: string, message: SignalingMessage): void {
    this.sendToClient(targetPeerId, message);
  }

  private broadcastToRoom(roomId: string, message: SignalingMessage, excludePeerId?: string): void {
    const peers = this.rooms.get(roomId);
    if (!peers) return;

    for (const peerId of peers) {
      if (peerId !== excludePeerId) {
        this.sendToClient(peerId, message);
      }
    }
  }

  private sendToClient(peerId: string, message: SignalingMessage): void {
    const client = this.clients.get(peerId);
    if (client && client.socket.readyState === WebSocket.OPEN) {
      client.socket.send(JSON.stringify(message));
    } else {
      console.warn(`Cannot send message to peer ${peerId} - client not found or socket closed`);
    }
  }

  private handleDisconnect(peerId: string): void {
    const client = this.clients.get(peerId);
    if (!client) return;

    const { roomId } = client;
    this.clients.delete(peerId);

    if (roomId) {
      const room = this.rooms.get(roomId);
      if (room) {
        room.delete(peerId);
        
        // Notify others in the room that this peer left
        this.broadcastToRoom(roomId, {
          type: MessageType.PEER_LEFT,
          peerId,
        });

        // Clean up empty room
        if (room.size === 0) {
          this.rooms.delete(roomId);
        }
      }
      console.log(`Peer ${peerId} left room ${roomId} (disconnected)`);
    } else {
      console.log(`Peer ${peerId} disconnected`);
    }
  }
}
