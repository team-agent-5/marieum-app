import 'package:equatable/equatable.dart';

class HistoryEntry extends Equatable {
  const HistoryEntry({
    required this.logId,
    required this.text,
    required this.source,
    required this.createdAt,
    this.selectedRank,
  });
  final String logId;
  final String text;
  final String source;
  final DateTime createdAt;
  final int? selectedRank;
  @override
  List<Object?> get props => [logId, text, source, createdAt, selectedRank];
}
