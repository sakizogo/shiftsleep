class EventType {
  final String id;
  final String name;
  final String emoji;

  EventType({
    required this.id,
    required this.name,
    required this.emoji,
  });
}

// ✅ アプリ全体で使用できる定数リスト
final List<EventType> eventTypes = [
  EventType(id: 'salary', name: '給料日', emoji: '💰'),
  EventType(id: 'bonus', name: 'ボーナス', emoji: '🎁'),
  EventType(id: 'trip', name: '慰安旅行', emoji: '✈️'),
  EventType(id: 'holiday', name: '祝日', emoji: '🎉'),
  EventType(id: 'meeting', name: '重要会議', emoji: '📅'),
  EventType(id: 'deadline', name: '締切', emoji: '⏰'),
];