enum BridgeEventType {
  navigation,
  dataUpdate,
  error,
  ready,
  scroll,
  resize,
  custom,
}

class BridgeEvent {
  final BridgeEventType type;
  final String? action;
  final Map<String, dynamic> data;
  final DateTime timestamp;

  BridgeEvent({
    required this.type,
    this.action,
    this.data = const {},
  }) : timestamp = DateTime.now();

  factory BridgeEvent.fromJson(Map<String, dynamic> json) {
    return BridgeEvent(
      type: BridgeEventType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => BridgeEventType.custom,
      ),
      action: json['action'],
      data: json['data'] ?? {},
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'action': action,
        'data': data,
        'timestamp': timestamp.toIso8601String(),
      };
}