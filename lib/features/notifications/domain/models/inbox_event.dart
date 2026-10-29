/// An immutable, server-authoritative inbox event.
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

  factory InboxEvent.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final type = json['type'];
    final title = json['title'];
    final message = json['message'];
    final rawCreatedAt = json['created_at'];
    if (id is! String || id.isEmpty || type is! String || type.isEmpty ||
        title is! String || message is! String || rawCreatedAt is! String) {
      throw const FormatException('Invalid inbox event');
    }
    final createdAt = DateTime.tryParse(rawCreatedAt);
    if (createdAt == null) throw const FormatException('Invalid created_at');
    final rawReadAt = json['read_at'];
    final readAt = rawReadAt is String ? DateTime.tryParse(rawReadAt) : null;
    if (rawReadAt != null && readAt == null) {
      throw const FormatException('Invalid read_at');
    }
    final rawWorkOrderId = json['work_order_id'];
    if (rawWorkOrderId != null && (rawWorkOrderId is! int || rawWorkOrderId <= 0)) {
      throw const FormatException('Invalid work_order_id');
    }
    return InboxEvent(id: id, type: type, createdAt: createdAt,
      title: title, message: message, workOrderId: rawWorkOrderId as int?, readAt: readAt);
  }
}

/// A server page with an opaque continuation cursor.
class InboxPage {
  const InboxPage({required this.events, this.nextCursor});
  final List<InboxEvent> events;
  final String? nextCursor;

  factory InboxPage.fromJson(Map<String, dynamic> json) {
    final raw = json['results'];
    final cursor = json['next_cursor'];
    if (raw is! List || (cursor != null && cursor is! String)) {
      throw const FormatException('Invalid inbox page');
    }
    return InboxPage(
      events: raw.map((entry) {
        if (entry is! Map<String, dynamic>) {
          throw const FormatException('Invalid inbox entry');
        }
        return InboxEvent.fromJson(entry);
      }).toList(growable: false),
      nextCursor: cursor as String?,
    );
  }
}
