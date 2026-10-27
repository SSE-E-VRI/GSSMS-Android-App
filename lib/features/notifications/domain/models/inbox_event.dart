class InboxEvent {
  const InboxEvent({required this.id, required this.type, required this.createdAt, required this.title, required this.message, this.workOrderId, this.readAt});
  final String id;
  final String type;
  final DateTime createdAt;
  final String title;
  final String message;
  final int? workOrderId;
  final DateTime? readAt;
  bool get isRead => readAt != null;
}
