export enum MessageType {
  JOIN_ROOM = 'JOIN_ROOM',
  ROOM_JOINED = 'ROOM_JOINED',
  OFFER = 'OFFER',
  ANSWER = 'ANSWER',
  ICE_CANDIDATE = 'ICE_CANDIDATE',
  PEER_LEFT = 'PEER_LEFT',
  PEER_JOINED = 'PEER_JOINED',
  DISCONNECT = 'DISCONNECT',
}

export interface BaseMessage {
  type: MessageType;
}

export interface JoinRoomMessage extends BaseMessage {
  type: MessageType.JOIN_ROOM;
  roomId: string;
  peerId: string;
}

export interface RoomJoinedMessage extends BaseMessage {
  type: MessageType.ROOM_JOINED;
  roomId: string;
  peerId: string;
}

export interface OfferMessage extends BaseMessage {
  type: MessageType.OFFER;
  sdp: string;
  targetPeerId: string;
  senderPeerId: string;
}

export interface AnswerMessage extends BaseMessage {
  type: MessageType.ANSWER;
  sdp: string;
  targetPeerId: string;
  senderPeerId: string;
}

export interface IceCandidateMessage extends BaseMessage {
  type: MessageType.ICE_CANDIDATE;
  candidate: string;
  sdpMid: string | null;
  sdpMLineIndex: number | null;
  targetPeerId: string;
  senderPeerId: string;
}

export interface PeerLeftMessage extends BaseMessage {
  type: MessageType.PEER_LEFT;
  peerId: string;
}

export type SignalingMessage =
  | JoinRoomMessage
  | RoomJoinedMessage
  | OfferMessage
  | AnswerMessage
  | IceCandidateMessage
  | PeerLeftMessage;
