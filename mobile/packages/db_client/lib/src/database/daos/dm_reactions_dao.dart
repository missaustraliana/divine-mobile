// ABOUTME: DAO for NIP-25 emoji reactions on NIP-17 direct messages.
// ABOUTME: Handles optimistic insert + placeholder swap, soft-delete on
// ABOUTME: supersede or NIP-09, and reactive watch for chip rendering.

import 'package:db_client/db_client.dart';
import 'package:drift/drift.dart';

part 'dm_reactions_dao.g.dart';

/// DAO for the `dm_message_reactions` table.
///
/// Two write paths:
/// - **Outgoing**: [insertOptimistic] writes a row with a placeholder id
///   plus `publishStatus = 'pending'` and the serialized rumor JSON.
///   Once the publish lands, [swapPlaceholderId] replaces the placeholder
///   id with the real rumor id, clears the JSON, and marks `'sent'`.
/// - **Incoming**: [upsertIncoming] writes (or de-dups) a row keyed on
///   `(id, owner_pubkey)` — the rumor id is stable across the recipient
///   and self gift-wraps, so a multi-device account that receives both
///   collapses to one row.
@DriftAccessor(tables: [DmMessageReactions])
class DmReactionsDao extends DatabaseAccessor<AppDatabase>
    with _$DmReactionsDaoMixin {
  DmReactionsDao(super.attachedDatabase);

  /// Insert an optimistic outgoing row before the publish attempt.
  ///
  /// [placeholderId] is a short unique token (e.g. `pending-<uuid>`) used
  /// while the real rumor id is in flight. Once the publish succeeds,
  /// call [swapPlaceholderId] to swap to the real id.
  Future<void> insertOptimistic({
    required String placeholderId,
    required String conversationId,
    required String targetMessageId,
    required String targetMessageAuthor,
    required String reactorPubkey,
    required String emoji,
    required int createdAt,
    required String ownerPubkey,
    required String rumorEventJson,
  }) async {
    await into(dmMessageReactions).insert(
      DmMessageReactionsCompanion.insert(
        id: placeholderId,
        conversationId: conversationId,
        targetMessageId: targetMessageId,
        targetMessageAuthor: targetMessageAuthor,
        reactorPubkey: reactorPubkey,
        emoji: emoji,
        createdAt: createdAt,
        ownerPubkey: ownerPubkey,
        giftWrapId: const Value(null),
        rumorEventJson: Value(rumorEventJson),
        publishStatus: const Value('pending'),
      ),
    );
  }

  /// Swap the placeholder id for the real rumor event id once publish
  /// landed. Clears `rumorEventJson` (no longer needed for retry) and
  /// marks `publishStatus = 'sent'`.
  Future<void> swapPlaceholderId({
    required String placeholderId,
    required String realRumorId,
    required String ownerPubkey,
    String? giftWrapId,
  }) async {
    await (update(dmMessageReactions)..where(
          (t) => t.id.equals(placeholderId) & t.ownerPubkey.equals(ownerPubkey),
        ))
        .write(
          DmMessageReactionsCompanion(
            id: Value(realRumorId),
            giftWrapId: Value(giftWrapId),
            rumorEventJson: const Value(null),
            publishStatus: const Value('sent'),
          ),
        );
  }

  /// Mark an outgoing row as `'failed'` after a publish attempt threw.
  /// Keeps the `rumorEventJson` for retry.
  Future<void> markFailed({
    required String placeholderId,
    required String ownerPubkey,
  }) async {
    await (update(dmMessageReactions)..where(
          (t) => t.id.equals(placeholderId) & t.ownerPubkey.equals(ownerPubkey),
        ))
        .write(
          const DmMessageReactionsCompanion(publishStatus: Value('failed')),
        );
  }

  /// Mark an outgoing row as `'pending'` — used by retry to surface
  /// in-flight state in the persistent layer so a cubit rebuild
  /// (auth flip, hot-restart, navigation) recovers the correct UI.
  Future<void> markPending({
    required String id,
    required String ownerPubkey,
  }) async {
    await (update(
      dmMessageReactions,
    )..where((t) => t.id.equals(id) & t.ownerPubkey.equals(ownerPubkey))).write(
      const DmMessageReactionsCompanion(publishStatus: Value('pending')),
    );
  }

  /// Soft-delete a row (NIP-09 kind 5 deletion received, or own-reaction
  /// supersede when toggling a different emoji).
  Future<int> softDelete({
    required String id,
    required String ownerPubkey,
  }) async {
    return (update(dmMessageReactions)
          ..where((t) => t.id.equals(id) & t.ownerPubkey.equals(ownerPubkey)))
        .write(const DmMessageReactionsCompanion(isDeleted: Value(true)));
  }

  /// Hard-delete a failed-and-discarded pending row (long-press dismiss).
  Future<int> deleteById({
    required String id,
    required String ownerPubkey,
  }) async {
    return (delete(
      dmMessageReactions,
    )..where((t) => t.id.equals(id) & t.ownerPubkey.equals(ownerPubkey))).go();
  }

  /// Upsert an incoming reaction. Idempotent on `(id, owner_pubkey)`.
  Future<void> upsertIncoming({
    required String id,
    required String conversationId,
    required String targetMessageId,
    required String targetMessageAuthor,
    required String reactorPubkey,
    required String emoji,
    required int createdAt,
    required String giftWrapId,
    required String ownerPubkey,
  }) async {
    await into(dmMessageReactions).insertOnConflictUpdate(
      DmMessageReactionsCompanion.insert(
        id: id,
        conversationId: conversationId,
        targetMessageId: targetMessageId,
        targetMessageAuthor: targetMessageAuthor,
        reactorPubkey: reactorPubkey,
        emoji: emoji,
        createdAt: createdAt,
        ownerPubkey: ownerPubkey,
        giftWrapId: Value(giftWrapId),
      ),
    );
  }

  /// Returns the existing live (non-deleted) row by this reactor on the
  /// given target message, if any. Used by the cap-at-one supersede.
  Future<DmReactionRow?> getOwnLiveReaction({
    required String targetMessageId,
    required String reactorPubkey,
    required String ownerPubkey,
  }) async {
    final query = select(dmMessageReactions)
      ..where(
        (t) =>
            t.targetMessageId.equals(targetMessageId) &
            t.reactorPubkey.equals(reactorPubkey) &
            t.ownerPubkey.equals(ownerPubkey) &
            t.isDeleted.equals(false),
      )
      ..limit(1);
    return query.getSingleOrNull();
  }

  /// Reactive stream of every live reaction in [conversationId] for the
  /// account [ownerPubkey].
  Stream<List<DmReactionRow>> watchForConversation({
    required String conversationId,
    required String ownerPubkey,
  }) {
    final query = select(dmMessageReactions)
      ..where(
        (t) =>
            t.conversationId.equals(conversationId) &
            t.ownerPubkey.equals(ownerPubkey) &
            t.isDeleted.equals(false),
      )
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    return query.watch();
  }

  /// Return the stored rumor JSON for a pending/failed outgoing row, or
  /// `null` if no row matches or the row has no stored rumor.
  Future<String?> getRumorJson({
    required String id,
    required String ownerPubkey,
  }) async {
    final query = select(dmMessageReactions)
      ..where((t) => t.id.equals(id) & t.ownerPubkey.equals(ownerPubkey))
      ..limit(1);
    final row = await query.getSingleOrNull();
    return row?.rumorEventJson;
  }

  /// Return a single reaction row by stable reaction rumor id, or `null`
  /// when no row matches in this account's view.
  Future<DmReactionRow?> getById({
    required String id,
    required String ownerPubkey,
  }) {
    final query = select(dmMessageReactions)
      ..where((t) => t.id.equals(id) & t.ownerPubkey.equals(ownerPubkey))
      ..limit(1);
    return query.getSingleOrNull();
  }

  /// Has the gift wrap with id `giftWrapId` already produced a row? Used by the
  /// receive pipeline to short-circuit before decryption work. Returns
  /// `true` only when a non-null match exists in this account's view.
  Future<bool> hasGiftWrap({
    required String giftWrapId,
    required String ownerPubkey,
  }) async {
    final query = selectOnly(dmMessageReactions)
      ..addColumns([dmMessageReactions.id])
      ..where(
        dmMessageReactions.giftWrapId.equals(giftWrapId) &
            dmMessageReactions.ownerPubkey.equals(ownerPubkey),
      )
      ..limit(1);
    return (await query.get()).isNotEmpty;
  }

  /// Delete everything owned by [ownerPubkey]. Sign-out cleanup.
  Future<int> deleteAllForOwner(String ownerPubkey) async {
    return (delete(
      dmMessageReactions,
    )..where((t) => t.ownerPubkey.equals(ownerPubkey))).go();
  }
}
