// ABOUTME: Widget tests for ReactionsRow.
// ABOUTME: Covers chip rendering, semantic labels, and retry/toggle
// ABOUTME: dispatching through ConversationReactionsCubit.

import 'package:bloc_test/bloc_test.dart';
import 'package:divine_ui/divine_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:models/models.dart';
import 'package:openvine/blocs/dm/reactions/conversation_reactions_cubit.dart';
import 'package:openvine/screens/inbox/conversation/widgets/reactions_row.dart';

import '../../../../helpers/test_provider_overrides.dart';

class _MockConversationReactionsCubit
    extends MockBloc<ConversationReactionsEvent, ConversationReactionsState>
    implements ConversationReactionsCubit {}

void main() {
  const ownerPubkey =
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
  const otherPubkey =
      'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210';
  const conversationId =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const messageId =
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

  DmReaction makeReaction({
    required String id,
    required String reactorPubkey,
    required String emoji,
    DmReactionPublishStatus publishStatus = DmReactionPublishStatus.sent,
  }) {
    return DmReaction(
      id: id,
      conversationId: conversationId,
      targetMessageId: messageId,
      targetMessageAuthor: otherPubkey,
      reactorPubkey: reactorPubkey,
      emoji: emoji,
      createdAt: 1_700_000_000,
      ownerPubkey: ownerPubkey,
      publishStatus: publishStatus,
    );
  }

  Widget buildSubject(_MockConversationReactionsCubit cubit) {
    return testMaterialApp(
      home: Scaffold(
        body: BlocProvider<ConversationReactionsCubit>.value(
          value: cubit,
          child: const ReactionsRow(
            conversationId: conversationId,
            messageId: messageId,
            messageAuthorPubkey: otherPubkey,
            ownerPubkey: ownerPubkey,
            otherParticipantName: 'Alex',
            isSentByMe: false,
          ),
        ),
      ),
    );
  }

  group('ReactionsRow', () {
    late _MockConversationReactionsCubit cubit;

    setUpAll(() {
      registerFallbackValue(
        const ConversationReactionToggled(
          conversationId: conversationId,
          messageId: messageId,
          messageAuthorPubkey: otherPubkey,
          emoji: '🔥',
        ),
      );
      registerFallbackValue(
        const ConversationReactionRetryRequested(
          rumorId:
              'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
          messageId: messageId,
          messageAuthorPubkey: otherPubkey,
          emoji: '🔥',
        ),
      );
    });

    setUp(() {
      cubit = _MockConversationReactionsCubit();
    });

    testWidgets('renders aggregated chips with semantic labels', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      const state = ConversationReactionsState(
        reactionsByMessageId: {
          messageId: [
            DmReaction(
              id: 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
              conversationId: conversationId,
              targetMessageId: messageId,
              targetMessageAuthor: otherPubkey,
              reactorPubkey: ownerPubkey,
              emoji: '🔥',
              createdAt: 1_700_000_000,
              ownerPubkey: ownerPubkey,
              publishStatus: DmReactionPublishStatus.sent,
            ),
            DmReaction(
              id: 'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
              conversationId: conversationId,
              targetMessageId: messageId,
              targetMessageAuthor: otherPubkey,
              reactorPubkey: otherPubkey,
              emoji: '😂',
              createdAt: 1_700_000_001,
              ownerPubkey: ownerPubkey,
              publishStatus: DmReactionPublishStatus.received,
            ),
          ],
        },
      );
      when(() => cubit.state).thenReturn(state);
      whenListen(cubit, Stream.value(state), initialState: state);

      await tester.pumpWidget(buildSubject(cubit));
      await tester.pump();

      expect(find.text('🔥'), findsOneWidget);
      expect(find.text('😂'), findsOneWidget);
      final chips = find.byType(ReactionChip);
      expect(
        tester.getSemantics(chips.at(0)).label,
        contains('Your reaction: 🔥'),
      );
      expect(
        tester.getSemantics(chips.at(1)).label,
        contains('Alex reacted with 😂'),
      );
      semantics.dispose();
    });

    testWidgets('tapping failed own chip dispatches retry request', (
      tester,
    ) async {
      const failedId =
          'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
      const state = ConversationReactionsState(
        reactionsByMessageId: {
          messageId: [
            DmReaction(
              id: failedId,
              conversationId: conversationId,
              targetMessageId: messageId,
              targetMessageAuthor: otherPubkey,
              reactorPubkey: ownerPubkey,
              emoji: '🔥',
              createdAt: 1_700_000_000,
              ownerPubkey: ownerPubkey,
              publishStatus: DmReactionPublishStatus.failed,
            ),
          ],
        },
      );
      when(() => cubit.state).thenReturn(state);
      whenListen(cubit, Stream.value(state), initialState: state);

      await tester.pumpWidget(buildSubject(cubit));
      await tester.pump();

      await tester.tap(find.text('🔥'));
      await tester.pump();

      verify(
        () => cubit.add(
          const ConversationReactionRetryRequested(
            rumorId: failedId,
            messageId: messageId,
            messageAuthorPubkey: otherPubkey,
            emoji: '🔥',
          ),
        ),
      ).called(1);
    });

    testWidgets('tapping settled chip dispatches toggle event', (tester) async {
      final state = ConversationReactionsState(
        reactionsByMessageId: {
          messageId: [
            makeReaction(id: '1', reactorPubkey: otherPubkey, emoji: '🔥'),
          ],
        },
      );
      when(() => cubit.state).thenReturn(state);
      whenListen(cubit, Stream.value(state), initialState: state);

      await tester.pumpWidget(buildSubject(cubit));
      await tester.pump();
      await tester.tap(find.text('🔥'));
      await tester.pump();

      verify(
        () => cubit.add(
          const ConversationReactionToggled(
            conversationId: conversationId,
            messageId: messageId,
            messageAuthorPubkey: otherPubkey,
            emoji: '🔥',
          ),
        ),
      ).called(1);
    });
  });
}
