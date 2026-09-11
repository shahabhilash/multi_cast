import 'dart:convert';

class SignalingMessageType {
  static const String joinRoom = 'JOIN_ROOM';
  static const String roomJoined = 'ROOM_JOINED';
  static const String offer = 'OFFER';
  static const String answer = 'ANSWER';
  static const String iceCandidate = 'ICE_CANDIDATE';
  static const String peerLeft = 'PEER_LEFT';
  static const String peerJoined = 'PEER_JOINED';
  static const String disconnect = 'DISCONNECT';
  static const String error = 'ERROR';
  static const String ping = 'PING';
  static const String pong = 'PONG';
}

class SignalingMessage {
  final String type;
  final String? roomId;
  final String? peerId;
  final String? targetPeerId;
  final String? senderPeerId;
  final Map<String, dynamic>? sdp;
  final Map<String, dynamic>? candidate;
  final int? sdpMLineIndex;
  final String? sdpMid;
  final String? errorMessage;

  SignalingMessage({
    required this.type,
    this.roomId,
    this.peerId,
    this.targetPeerId,
    this.senderPeerId,
    this.sdp,
    this.candidate,
    this.sdpMLineIndex,
    this.sdpMid,
    this.errorMessage,
  });

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      if (roomId != null) 'roomId': roomId,
      if (peerId != null) 'peerId': peerId,
      if (targetPeerId != null) 'targetPeerId': targetPeerId,
      if (senderPeerId != null) 'senderPeerId': senderPeerId,
      if (sdp != null) 'sdp': sdp,
      if (candidate != null) ...{
        'candidate': candidate!['candidate'],
        'sdpMLineIndex': candidate!['sdpMLineIndex'] ?? sdpMLineIndex,
        'sdpMid': candidate!['sdpMid'] ?? sdpMid,
      } else ...{
        if (sdpMLineIndex != null) 'sdpMLineIndex': sdpMLineIndex,
        if (sdpMid != null) 'sdpMid': sdpMid,
      },
      if (errorMessage != null) 'errorMessage': errorMessage,
    };
  }

  factory SignalingMessage.fromMap(Map<String, dynamic> map) {
    return SignalingMessage(
      type: map['type'] ?? '',
      roomId: map['roomId'],
      peerId: map['peerId'],
      targetPeerId: map['targetPeerId'],
      senderPeerId: map['senderPeerId'],
      sdp: map['sdp'] != null ? Map<String, dynamic>.from(map['sdp']) : null,
      candidate: map['candidate'] != null 
          ? (map['candidate'] is Map ? Map<String, dynamic>.from(map['candidate']) : {'candidate': map['candidate']})
          : null,
      sdpMLineIndex: map['sdpMLineIndex'],
      sdpMid: map['sdpMid'],
      errorMessage: map['errorMessage'],
    );
  }

  String toJson() => json.encode(toMap());

  factory SignalingMessage.fromJson(String source) => SignalingMessage.fromMap(json.decode(source));
}
