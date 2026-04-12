String formatRelativeTime(DateTime? dateTime) {
  if (dateTime == null) return '없음';
  final diff = DateTime.now().difference(dateTime);
  if (diff.inMinutes < 1) return '방금 전';
  if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
  if (diff.inHours < 24) return '${diff.inHours}시간 전';
  if (diff.inDays < 7) return '${diff.inDays}일 전';
  return '${dateTime.month}/${dateTime.day}';
}

String abbreviateSpreadsheetId(String id) {
  if (id.length <= 8) return id;
  return '${id.substring(0, 4)}....${id.substring(id.length - 4)}';
}
