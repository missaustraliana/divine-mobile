// ABOUTME: Unit tests for DmReactionsDao.
// ABOUTME: Covers optimistic writes, retry state transitions, soft delete,
// ABOUTME: wrapped receive dedup, and owner-scoped query behaviour.

import 'dart:io';

import 'package:db_client/db_client.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const _ownerA =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const _ownerB =
    'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210';
const String _reactorA = _ownerA;
const _reactorB =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _conversationId =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _targetMessageId =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
const _targetAuthor =
    'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';
const _pendingId =
    'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';
const _sentId =
    'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';
const _giftWrapId =
    '1111111111111111111111111111111111111111111111111111111111111111';

void main() {
  late AppDatabase database;
  late DmReactionsDao dao;
  late String tempDbPath;

  setUp(() async {
    final tempDir = Directory.systemTemp.createTempSync('dm_reactions_dao_');
    tempDbPath = '${tempDir.path}/test.db';

    database = AppDatabase.test(NativeDatabase(File(tempDbPath)));
    dao = database.dmReactionsDao;
  });

  tearDown(() async {
    await database.close();
    final file = File(tempDbPath);
    if (file.existsSync()) {
      file.deleteSync();
    }
    final dir = Directory(tempDbPath).parent;
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });

  group('DmReactionsDao', () {
    Future<void> insertPending({
      String id = _pendingId,
      String ownerPubkey = _ownerA,
      String reactorPubkey = _reactorA,
      String emoji = '🔥',
    }) {
      return dao.insertOptimistic(
        placeholderId: id,
        conversationId: _conversationId,
        targetMessageId: _targetMessageId,
        targetMessageAuthor: _targetAuthor,
        reactorPubkey: reactorPubkey,
        emoji: emoji,
        createdAt: 1_700_000_000,
        ownerPubkey: ownerPubkey,
        rumorEventJson: '{"id":"$id"}',
      );
    }

    test('insertOptimistic stores pending state and rumor json', () async {
      await insertPending();

      final row = await dao.getById(id: _pendingId, ownerPubkey: _ownerA);
      expect(row, isNotNull);
      expect(row!.publishStatus, equals('pending'));
      expect(row.rumorEventJson, contains(_pendingId));
      expect(row.giftWrapId, isNull);
    });

    test('swapPlaceholderId marks row sent and clears stored rumor', () async {
      await insertPending();

      await dao.swapPlaceholderId(
        placeholderId: _pendingId,
        realRumorId: _sentId,
        ownerPubkey: _ownerA,
        giftWrapId: _giftWrapId,
      );

      expect(await dao.getById(id: _pendingId, ownerPubkey: _ownerA), isNull);
      final row = await dao.getById(id: _sentId, ownerPubkey: _ownerA);
      expect(row, isNotNull);
      expect(row!.publishStatus, equals('sent'));
      expect(row.rumorEventJson, isNull);
      expect(row.giftWrapId, equals(_giftWrapId));
    });

    test('markFailed and markPending transition publish status', () async {
      await insertPending();

      await dao.markFailed(placeholderId: _pendingId, ownerPubkey: _ownerA);
      expect(
        (await dao.getById(
          id: _pendingId,
          ownerPubkey: _ownerA,
        ))!.publishStatus,
        equals('failed'),
      );

      await dao.markPending(id: _pendingId, ownerPubkey: _ownerA);
      expect(
        (await dao.getById(
          id: _pendingId,
          ownerPubkey: _ownerA,
        ))!.publishStatus,
        equals('pending'),
      );
    });

    test(
      'softDelete hides row from live queries but preserves record',
      () async {
        await insertPending(id: _sentId);

        final before = await dao.getOwnLiveReaction(
          targetMessageId: _targetMessageId,
          reactorPubkey: _reactorA,
          ownerPubkey: _ownerA,
        );
        expect(before, isNotNull);

        await dao.softDelete(id: _sentId, ownerPubkey: _ownerA);

        final row = await dao.getById(id: _sentId, ownerPubkey: _ownerA);
        expect(row!.isDeleted, isTrue);
        expect(
          await dao.getOwnLiveReaction(
            targetMessageId: _targetMessageId,
            reactorPubkey: _reactorA,
            ownerPubkey: _ownerA,
          ),
          isNull,
        );
      },
    );

    test('deleteById removes failed rows entirely', () async {
      await insertPending();

      final deleted = await dao.deleteById(
        id: _pendingId,
        ownerPubkey: _ownerA,
      );

      expect(deleted, equals(1));
      expect(await dao.getById(id: _pendingId, ownerPubkey: _ownerA), isNull);
    });

    test('upsertIncoming deduplicates by id and owner pubkey', () async {
      await dao.upsertIncoming(
        id: _sentId,
        conversationId: _conversationId,
        targetMessageId: _targetMessageId,
        targetMessageAuthor: _targetAuthor,
        reactorPubkey: _reactorB,
        emoji: '😂',
        createdAt: 1_700_000_000,
        giftWrapId: _giftWrapId,
        ownerPubkey: _ownerA,
      );
      await dao.upsertIncoming(
        id: _sentId,
        conversationId: _conversationId,
        targetMessageId: _targetMessageId,
        targetMessageAuthor: _targetAuthor,
        reactorPubkey: _reactorB,
        emoji: '😂',
        createdAt: 1_700_000_001,
        giftWrapId:
            '2222222222222222222222222222222222222222222222222222222222222222',
        ownerPubkey: _ownerA,
      );

      final rows = await dao
          .watchForConversation(
            conversationId: _conversationId,
            ownerPubkey: _ownerA,
          )
          .first;
      expect(rows, hasLength(1));
      expect(rows.single.id, equals(_sentId));
    });

    test('watchForConversation only returns live rows for one owner', () async {
      await insertPending();
      await insertPending(id: _sentId, ownerPubkey: _ownerB, emoji: '😂');
      await dao.softDelete(id: _pendingId, ownerPubkey: _ownerA);
      await dao.upsertIncoming(
        id: '3333333333333333333333333333333333333333333333333333333333333333',
        conversationId: _conversationId,
        targetMessageId: _targetMessageId,
        targetMessageAuthor: _targetAuthor,
        reactorPubkey: _reactorB,
        emoji: '😮',
        createdAt: 1_700_000_002,
        giftWrapId: _giftWrapId,
        ownerPubkey: _ownerA,
      );

      final rowsA = await dao
          .watchForConversation(
            conversationId: _conversationId,
            ownerPubkey: _ownerA,
          )
          .first;
      final rowsB = await dao
          .watchForConversation(
            conversationId: _conversationId,
            ownerPubkey: _ownerB,
          )
          .first;

      expect(rowsA.map((row) => row.emoji), equals(['😮']));
      expect(rowsB.map((row) => row.emoji), equals(['😂']));
    });

    test('getRumorJson and hasGiftWrap are owner scoped', () async {
      await insertPending();
      await dao.upsertIncoming(
        id: _sentId,
        conversationId: _conversationId,
        targetMessageId: _targetMessageId,
        targetMessageAuthor: _targetAuthor,
        reactorPubkey: _reactorB,
        emoji: '😂',
        createdAt: 1_700_000_001,
        giftWrapId: _giftWrapId,
        ownerPubkey: _ownerA,
      );

      expect(
        await dao.getRumorJson(id: _pendingId, ownerPubkey: _ownerA),
        contains(_pendingId),
      );
      expect(
        await dao.getRumorJson(id: _pendingId, ownerPubkey: _ownerB),
        isNull,
      );
      expect(
        await dao.hasGiftWrap(giftWrapId: _giftWrapId, ownerPubkey: _ownerA),
        isTrue,
      );
      expect(
        await dao.hasGiftWrap(giftWrapId: _giftWrapId, ownerPubkey: _ownerB),
        isFalse,
      );
    });

    test('deleteAllForOwner clears only the targeted account', () async {
      await insertPending();
      await insertPending(id: _sentId, ownerPubkey: _ownerB);

      final deleted = await dao.deleteAllForOwner(_ownerA);

      expect(deleted, equals(1));
      expect(await dao.getById(id: _pendingId, ownerPubkey: _ownerA), isNull);
      expect(await dao.getById(id: _sentId, ownerPubkey: _ownerB), isNotNull);
    });
  });
}
