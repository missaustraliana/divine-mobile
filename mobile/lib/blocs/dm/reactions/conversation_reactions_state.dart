// ABOUTME: State for ConversationReactionsCubit.
// ABOUTME: Holds the per-message reaction lists and a per-(message,emoji)
// ABOUTME: publish-status map for optimistic / failed render.

part of 'conversation_reactions_cubit.dart';

/// Top-level lifecycle status of the cubit.
enum ConversationReactionsStatus { initial, loading, loaded, failure }

/// State of an outgoing reaction publish from this client's perspective.
/// Distinct from [DmReactionPublishStatus] which is the on-disk shape.
enum ReactionPublishLocalStatus { sending, succeeded, failed }

/// Identity for an outgoing publish, used as the key in [pending].
@immutable
class ReactionPublishKey extends Equatable {
  /// Construct a publish key.
  const ReactionPublishKey({required this.messageId, required this.emoji});

  /// Rumor id of the message being reacted to.
  final String messageId;

  /// Reaction emoji codepoint.
  final String emoji;

  @override
  List<Object?> get props => [messageId, emoji];
}

/// Snapshot of the cubit's reactive view.
@immutable
class ConversationReactionsState extends Equatable {
  /// Construct a state.
  const ConversationReactionsState({
    this.status = ConversationReactionsStatus.initial,
    this.reactionsByMessageId = const <String, List<DmReaction>>{},
    this.pending = const <ReactionPublishKey, ReactionPublishLocalStatus>{},
  });

  /// Lifecycle status of the cubit.
  final ConversationReactionsStatus status;

  /// Live (non-deleted) reactions grouped by `target_message_id`. Empty
  /// when no reactions exist for a message. The cubit uses an empty
  /// outer map between initialization and the first stream tick.
  final Map<String, List<DmReaction>> reactionsByMessageId;

  /// In-flight publish state per (messageId, emoji). Cleared on the
  /// next stream tick after the publish lands and the DAO row carries
  /// the real status.
  final Map<ReactionPublishKey, ReactionPublishLocalStatus> pending;

  /// Live reactions for [messageId]. Returns `const []` if none.
  List<DmReaction> reactionsFor(String messageId) =>
      reactionsByMessageId[messageId] ?? const <DmReaction>[];

  /// Did the current account author a live reaction with [emoji] on
  /// the message [messageId]?
  bool ownReactionMatches({
    required String messageId,
    required String emoji,
    required String ownerPubkey,
  }) {
    final list = reactionsByMessageId[messageId];
    if (list == null) return false;
    for (final r in list) {
      if (r.reactorPubkey == ownerPubkey && r.emoji == emoji) {
        return true;
      }
    }
    return false;
  }

  /// Copy with overrides. `null` is "no change" semantics; explicit
  /// empties are passed by the caller.
  ConversationReactionsState copyWith({
    ConversationReactionsStatus? status,
    Map<String, List<DmReaction>>? reactionsByMessageId,
    Map<ReactionPublishKey, ReactionPublishLocalStatus>? pending,
  }) {
    return ConversationReactionsState(
      status: status ?? this.status,
      reactionsByMessageId: reactionsByMessageId ?? this.reactionsByMessageId,
      pending: pending ?? this.pending,
    );
  }

  @override
  List<Object?> get props => [status, reactionsByMessageId, pending];
}
