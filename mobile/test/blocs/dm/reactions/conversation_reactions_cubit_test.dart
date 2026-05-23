// ABOUTME: Cubit tests for ConversationReactionsCubit.

import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:dm_repository/dm_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:models/models.dart';
import 'package:openvine/blocs/dm/reactions/conversation_reactions_cubit.dart';

class _MockReactionsRepository extends Mock implements DmReactionsRepository {}

const _owner =
    '1111111111111111111111111111111111111111111111111111111111111111';
const _peer =
    '2222222222222222222222222222222222222222222222222222222222222222';
const _convo =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
const _msgId =
    'mmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmm';

void main() {
  group(ConversationReactionsCubit, () {
    late _MockReactionsRepository repo;
    late StreamController<List<DmReaction>> streamController;

    setUp(() {
      repo = _MockReactionsRepository();
      streamController = StreamController<List<DmReaction>>.broadcast();
      when(
        () => repo.watchForConversation(any()),
      ).thenAnswer((_) => streamController.stream);
    });

    tearDown(() async {
      await streamController.close();
    });

    blocTest<ConversationReactionsCubit, ConversationReactionsState>(
      'transitions through loading -> loaded on subscription tick',
      build: () => ConversationReactionsCubit(
        reactionsRepository: repo,
        ownerPubkey: _owner,
      ),
      act: (cubit) async {
        cubit.add(
          const ConversationReactionsStarted(conversationId: _convo),
        );
        await Future<void>.delayed(Duration.zero);
        streamController.add(const <DmReaction>[]);
      },
      expect: () => [
        isA<ConversationReactionsState>().having(
          (s) => s.status,
          'status',
          ConversationReactionsStatus.loading,
        ),
        isA<ConversationReactionsState>().having(
          (s) => s.status,
          'status',
          ConversationReactionsStatus.loaded,
        ),
      ],
    );

    blocTest<ConversationReactionsCubit, ConversationReactionsState>(
      'toggle publishes; pending then cleared on success',
      build: () {
        when(
          () => repo.publish(
            conversationId: any(named: 'conversationId'),
            targetMessageId: any(named: 'targetMessageId'),
            targetMessageAuthor: any(named: 'targetMessageAuthor'),
            emoji: any(named: 'emoji'),
          ),
        ).thenAnswer(
          (_) async => const DmReactionPublishResult(
            success: true,
            rumorId: 'r-1',
          ),
        );
        return ConversationReactionsCubit(
          reactionsRepository: repo,
          ownerPubkey: _owner,
        );
      },
      act: (cubit) async {
        cubit.add(
          const ConversationReactionToggled(
            conversationId: _convo,
            messageId: _msgId,
            messageAuthorPubkey: _peer,
            emoji: '❤️',
          ),
        );
      },
      expect: () => [
        isA<ConversationReactionsState>().having(
          (s) =>
              s.pending[const ReactionPublishKey(
                messageId: _msgId,
                emoji: '❤️',
              )],
          'pending entry',
          ReactionPublishLocalStatus.sending,
        ),
        isA<ConversationReactionsState>().having(
          (s) => s.pending.isEmpty,
          'pending cleared',
          isTrue,
        ),
      ],
    );

    blocTest<ConversationReactionsCubit, ConversationReactionsState>(
      'toggle publish failure marks pending as failed',
      build: () {
        when(
          () => repo.publish(
            conversationId: any(named: 'conversationId'),
            targetMessageId: any(named: 'targetMessageId'),
            targetMessageAuthor: any(named: 'targetMessageAuthor'),
            emoji: any(named: 'emoji'),
          ),
        ).thenAnswer(
          (_) async => const DmReactionPublishResult(
            success: false,
            rumorId: 'r-2',
            errorMessage: 'relay down',
          ),
        );
        return ConversationReactionsCubit(
          reactionsRepository: repo,
          ownerPubkey: _owner,
        );
      },
      act: (cubit) async {
        cubit.add(
          const ConversationReactionToggled(
            conversationId: _convo,
            messageId: _msgId,
            messageAuthorPubkey: _peer,
            emoji: '🔥',
          ),
        );
      },
      verify: (cubit) {
        final entry =
            cubit.state.pending[const ReactionPublishKey(
              messageId: _msgId,
              emoji: '🔥',
            )];
        expect(entry, ReactionPublishLocalStatus.failed);
      },
    );

    blocTest<ConversationReactionsCubit, ConversationReactionsState>(
      'subscription tick groups reactions by message id',
      build: () => ConversationReactionsCubit(
        reactionsRepository: repo,
        ownerPubkey: _owner,
      ),
      act: (cubit) async {
        cubit.add(
          const ConversationReactionsStarted(conversationId: _convo),
        );
        await Future<void>.delayed(Duration.zero);
        streamController.add([
          const DmReaction(
            id: 'r-3',
            conversationId: _convo,
            targetMessageId: _msgId,
            targetMessageAuthor: _peer,
            reactorPubkey: _peer,
            emoji: '👍',
            createdAt: 1700000000,
            ownerPubkey: _owner,
            publishStatus: DmReactionPublishStatus.received,
          ),
        ]);
      },
      verify: (cubit) {
        final list = cubit.state.reactionsByMessageId[_msgId];
        expect(list, isNotNull);
        expect(list!.length, 1);
        expect(list.first.emoji, '👍');
      },
    );
  });
}
