class Idea {
  const Idea({required this.id, required this.text, required this.votes, required this.createdAt, required this.hasVoted});

  final int id;
  final String text;
  final int votes;
  final DateTime createdAt;
  final bool hasVoted;

  Idea copyWith({int? votes, bool? hasVoted}) {
    return Idea(
      id: id,
      text: text,
      votes: votes ?? this.votes,
      createdAt: createdAt,
      hasVoted: hasVoted ?? this.hasVoted,
    );
  }

  factory Idea.fromJson(Map<String, dynamic> json) {
    return Idea(
      id: json['id'] as int,
      text: json['text'] as String,
      votes: json['votes'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
      hasVoted: json['has_voted'] as bool,
    );
  }
}

class IdeaComment {
  const IdeaComment({required this.id, required this.text, required this.createdAt});

  final int id;
  final String text;
  final DateTime createdAt;

  factory IdeaComment.fromJson(Map<String, dynamic> json) {
    return IdeaComment(
      id: json['id'] as int,
      text: json['text'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
