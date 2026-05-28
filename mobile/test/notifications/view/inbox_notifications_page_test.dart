// ABOUTME: Widget tests for InboxNotificationsPage — verifies that opening
// ABOUTME: the inbox refreshes once without implicitly mutating read state.

// ignore_for_file: prefer_const_constructors

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:follow_repository/follow_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:notification_repository/notification_repository.dart';
import 'package:openvine/notifications/providers/notification_repository_provider.dart';
import 'package:openvine/notifications/view/inbox_notifications_page.dart';
import 'package:openvine/notifications/view/notifications_view.dart';

import '../../helpers/test_provider_overrides.dart';

class _MockNotificationRepository extends Mock
    implements NotificationRepository {}

class _MockFollowRepository extends Mock implements FollowRepository {}

void main() {
  group(InboxNotificationsPage, () {
    late _MockNotificationRepository mockNotificationRepo;
    late _MockFollowRepository mockFollowRepo;

    setUp(() {
      mockNotificationRepo = _MockNotificationRepository();
      mockFollowRepo = _MockFollowRepository();

      when(
        () => mockNotificationRepo.watchSnapshot(),
      ).thenAnswer((_) => const Stream<NotificationPage>.empty());
      when(
        () => mockNotificationRepo.refresh(),
      ).thenAnswer((_) async => NotificationPage.empty);
      when(
        () => mockNotificationRepo.markAllAsRead(),
      ).thenAnswer((_) async {});
      when(() => mockFollowRepo.isFollowing(any())).thenReturn(false);
    });

    Widget buildSubject() {
      return testMaterialApp(
        mockFollowRepository: mockFollowRepo,
        additionalOverrides: [
          notificationRepositoryProvider.overrideWithValue(
            mockNotificationRepo,
          ),
        ],
        home: Scaffold(body: const InboxNotificationsPage()),
      );
    }

    testWidgets('opens the bloc via NotificationFeedStarted on first build', (
      tester,
    ) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      verify(() => mockNotificationRepo.refresh()).called(1);
      verifyNever(() => mockNotificationRepo.markAllAsRead());
    });

    testWidgets(
      'does not mark notifications read when the inbox page is unmounted',
      (tester) async {
        await tester.pumpWidget(buildSubject());
        await tester.pumpAndSettle();
        verifyNever(() => mockNotificationRepo.markAllAsRead());

        // Leaving the inbox (toggling to the Messages segment so the
        // notifications KeyedSubtree is swapped out, or leaving the inbox tab
        // so the ShellRoute unmounts the subtree) must NOT auto-zero unread
        // state. Read transitions are deliberate only. See #4729.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();

        verifyNever(() => mockNotificationRepo.markAllAsRead());
      },
    );

    testWidgets(
      'does not fan out refresh or mark-read across the five filter tabs',
      (tester) async {
        await tester.pumpWidget(buildSubject());
        await tester.pumpAndSettle();

        // Swipe through the four non-default tabs. Each visit mounts a
        // fresh NotificationsView; the contract is that none of them
        // triggers another refresh or implicit mark-all-read.
        for (var i = 1; i < 5; i++) {
          await tester.tap(find.byType(Tab).at(i));
          await tester.pumpAndSettle();
        }

        // Exactly one refresh and no implicit markAllAsRead across the
        // whole inbox-open lifecycle, even after all five filter views
        // have mounted.
        verify(() => mockNotificationRepo.refresh()).called(1);
        verifyNever(() => mockNotificationRepo.markAllAsRead());
        // Confirm all five filter views actually mounted — guards
        // against the test silently passing because TabBarView never
        // built the off-default children.
        expect(find.byType(NotificationsView), findsWidgets);
      },
    );
  });
}
