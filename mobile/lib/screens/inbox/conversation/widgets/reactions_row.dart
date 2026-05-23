// ABOUTME: Per-message row of reaction chips, beneath the bubble.
// ABOUTME: BlocSelector per row so adding a reaction on one message
// ABOUTME: doesn't rebuild the whole conversation.

import 'package:divine_ui/divine_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsService;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:models/models.dart';
import 'package:openvine/blocs/dm/reactions/conversation_reactions_cubit.dart';
import 'package:openvine/l10n/l10n.dart';

/// Aggregated chip data for one (emoji) across reactors on one message.
class _AggregatedReaction {
  _AggregatedReaction({
    required this.emoji,
    required this.count,
    required this.ownRumorId,
    required this.targetAuthor,
    required this.isOwn,
    required this.isPending,
    required this.isFailed,
  });

  final String emoji;
  int count;
  String? ownRumorId;
  final String targetAuthor;
  bool isOwn;
  bool isPending;
  bool isFailed;
}

/// Renders the reaction chips for one DM message. Reads from
/// [ConversationReactionsCubit] via `BlocSelector` so only this row
/// rebuilds when the message's reactions change.
class ReactionsRow extends StatelessWidget {
  /// Construct a reactions row.
  const ReactionsRow({
    required this.conversationId,
    required this.messageId,
    required this.messageAuthorPubkey,
    required this.ownerPubkey,
    required this.isSentByMe,
    this.otherParticipantName,
    this.blockedPubkeys = const <String>{},
    super.key,
  });

  /// Conversation containing the message.
  final String conversationId;

  /// Rumor id of the target message.
  final String messageId;

  /// Author of the target message.
  final String messageAuthorPubkey;

  /// Pubkey of the current account (own-reaction detection).
  final String ownerPubkey;

  /// True if the bubble was sent by the current account.
  final bool isSentByMe;

  /// Display name for the other participant in this 1:1 conversation.
  final String? otherParticipantName;

  /// Pubkeys whose reactions should be hidden.
  final Set<String> blockedPubkeys;

  @override
  Widget build(BuildContext context) {
    // `BlocBuilder` + per-message `buildWhen` instead of `BlocSelector`:
    // the row must rebuild when EITHER the persisted reactions for this
    // message change OR the in-flight pending entries for this message
    // change. A selector keyed only on `reactionsFor` misses the
    // pending-map updates and leaves the chip showing stale state
    // through a retry's sending → succeeded/failed transition.
    return BlocBuilder<ConversationReactionsCubit, ConversationReactionsState>(
      buildWhen: (prev, curr) {
        if (!_listEquals(
          prev.reactionsFor(messageId),
          curr.reactionsFor(messageId),
        )) {
          return true;
        }
        return !_pendingForMessageEquals(prev.pending, curr.pending, messageId);
      },
      builder: (context, state) {
        final reactions = state.reactionsFor(messageId);
        final visible = reactions
            .where((r) => !blockedPubkeys.contains(r.reactorPubkey))
            .toList(growable: false);
        if (visible.isEmpty) return const SizedBox.shrink();
        final aggregated = _aggregate(context: context, reactions: visible);
        if (aggregated.isEmpty) return const SizedBox.shrink();
        // Anchor the chip(s) to the bubble's corner using an explicit
        // Align — the parent ListView gives a full-width slot, and
        // Align with FractionalOffset places the chip on the correct
        // side regardless of the chip's intrinsic width. The previous
        // Wrap-based layout had ambiguous behaviour when the wrap took
        // the full width (children appeared centered).
        //
        // Transform.translate pulls the chip up ~10 px so it overlaps
        // the bubble's bottom edge the way iMessage / WhatsApp / Signal
        // present reactions.
        final chips = aggregated.map((agg) {
          final variant = _variantFor(agg);
          return MergeSemantics(
            child: ReactionChip(
              emoji: agg.emoji,
              count: agg.count,
              variant: variant,
              semanticLabel: _semanticLabelFor(context, agg, variant),
              onTap: () => _onTap(context, agg),
              onLongPress: agg.isFailed
                  ? () => _onLongPressFailed(context, agg)
                  : null,
            ),
          );
        }).toList();

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          child: Align(
            alignment: isSentByMe
                ? Alignment.centerRight
                : Alignment.centerLeft,
            child: Transform.translate(
              offset: const Offset(0, -14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: isSentByMe
                    ? MainAxisAlignment.end
                    : MainAxisAlignment.start,
                children: [
                  for (var i = 0; i < chips.length; i++) ...[
                    if (i > 0) const SizedBox(width: 3),
                    chips[i],
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<_AggregatedReaction> _aggregate({
    required BuildContext context,
    required List<DmReaction> reactions,
  }) {
    final cubit = context.read<ConversationReactionsCubit>();
    final pending = cubit.state.pending;
    final byEmoji = <String, _AggregatedReaction>{};
    for (final r in reactions) {
      final existing = byEmoji[r.emoji];
      if (existing == null) {
        final isOwn = r.reactorPubkey == ownerPubkey;
        final localKey = ReactionPublishKey(
          messageId: messageId,
          emoji: r.emoji,
        );
        final localStatus = pending[localKey];
        byEmoji[r.emoji] = _AggregatedReaction(
          emoji: r.emoji,
          count: 1,
          ownRumorId: isOwn ? r.id : null,
          targetAuthor: messageAuthorPubkey,
          isOwn: isOwn,
          isPending:
              localStatus == ReactionPublishLocalStatus.sending ||
              r.publishStatus == DmReactionPublishStatus.pending,
          isFailed:
              localStatus == ReactionPublishLocalStatus.failed ||
              r.publishStatus == DmReactionPublishStatus.failed,
        );
      } else {
        existing.count += 1;
        if (r.reactorPubkey == ownerPubkey) {
          existing.isOwn = true;
          existing.ownRumorId = r.id;
        }
      }
    }
    return byEmoji.values.toList(growable: false);
  }

  ReactionChipVariant _variantFor(_AggregatedReaction agg) {
    if (agg.isFailed) return ReactionChipVariant.failed;
    if (agg.isPending) return ReactionChipVariant.pending;
    if (agg.isOwn) return ReactionChipVariant.own;
    return ReactionChipVariant.theirs;
  }

  void _onTap(BuildContext context, _AggregatedReaction agg) {
    // Ignore taps on pending chips. Without this guard, a tap while a
    // retry is in flight would fall through to the toggle branch and
    // call `removeOwn` — silently deleting the very reaction the user
    // is trying to retry.
    if (agg.isPending) return;

    final cubit = context.read<ConversationReactionsCubit>();
    if (agg.isFailed && agg.ownRumorId != null) {
      SemanticsService.sendAnnouncement(
        View.of(context),
        context.l10n.dmReactionChipRetryAnnouncement,
        Directionality.of(context),
      );
      cubit.add(
        ConversationReactionRetryRequested(
          rumorId: agg.ownRumorId!,
          messageId: messageId,
          messageAuthorPubkey: agg.targetAuthor,
          emoji: agg.emoji,
        ),
      );
      return;
    }
    // Toggle — adds new reaction if none, removes own if present.
    cubit.add(
      ConversationReactionToggled(
        conversationId: conversationId,
        messageId: messageId,
        messageAuthorPubkey: agg.targetAuthor,
        emoji: agg.emoji,
      ),
    );
  }

  void _onLongPressFailed(BuildContext context, _AggregatedReaction agg) {
    // For v1 we treat long-press on a failed own chip as "remove
    // locally"; the cubit just calls removeOwn which soft-deletes and
    // emits a NIP-09 deletion if it was published, or simply collapses
    // the row otherwise.
    final ownRumorId = agg.ownRumorId;
    if (ownRumorId == null) return;
    context.read<ConversationReactionsCubit>().add(
      ConversationReactionToggled(
        conversationId: conversationId,
        messageId: messageId,
        messageAuthorPubkey: agg.targetAuthor,
        emoji: agg.emoji,
      ),
    );
  }

  String _semanticLabelFor(
    BuildContext context,
    _AggregatedReaction agg,
    ReactionChipVariant variant,
  ) {
    final l10n = context.l10n;
    return switch (variant) {
      ReactionChipVariant.pending => l10n.dmReactionChipPendingA11yLabel(
        agg.emoji,
      ),
      ReactionChipVariant.failed => l10n.dmReactionChipFailedA11yLabel,
      ReactionChipVariant.own => l10n.dmReactionChipOwnA11yLabel(agg.emoji),
      ReactionChipVariant.theirs => l10n.dmReactionChipOtherA11yLabel(
        otherParticipantName ?? agg.targetAuthor,
        agg.emoji,
      ),
    };
  }
}

bool _listEquals(List<DmReaction> a, List<DmReaction> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _pendingForMessageEquals(
  Map<ReactionPublishKey, ReactionPublishLocalStatus> a,
  Map<ReactionPublishKey, ReactionPublishLocalStatus> b,
  String messageId,
) {
  if (identical(a, b)) return true;
  var aCount = 0;
  var bCount = 0;
  for (final entry in a.entries) {
    if (entry.key.messageId != messageId) continue;
    aCount++;
    if (b[entry.key] != entry.value) return false;
  }
  for (final entry in b.entries) {
    if (entry.key.messageId == messageId) bCount++;
  }
  return aCount == bCount;
}
