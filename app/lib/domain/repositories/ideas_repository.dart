import '../models/idea.dart';

abstract class IdeasRepository {
  Future<List<Idea>> list();
  Future<Idea> submit(String text);
  Future<({int votes, bool hasVoted})> toggleVote(int ideaId);
  Future<List<IdeaComment>> listComments(int ideaId);
  Future<IdeaComment> addComment(int ideaId, String text);
}
