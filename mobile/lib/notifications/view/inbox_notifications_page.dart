// ABOUTME: Inbox notifications scaffold — TabBar (All/Likes/Comments/
// ABOUTME: Follows/Reposts) wrapping the BLoC-driven NotificationsView.

import 'package:divine_ui/divine_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:models/models.dart';
import 'package:openvine/l10n/l10n.dart';
import 'package:openvine/notifications/bloc/notification_feed_bloc.dart';
import 'package:openvine/notifications/providers/notification_repository_provider.dart';
import 'package:openvine/notifications/view/notifications_view.dart';
import 'package:openvine/providers/app_providers.dart';

/// Inbox notifications page — owns the BLoC and tab scaffold.
///
/// Wraps [NotificationsView] with the existing 5-tab UI (All / Likes /
/// Comments / Follows / Reposts). Each tab passes a [NotificationKind]
/// filter to the same view; the underlying [NotificationFeedBloc] is shared
/// across tabs.
class InboxNotificationsPage extends ConsumerWidget {
  /// Creates an [InboxNotificationsPage].
  const InboxNotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationRepository = ref.watch(notificationRepositoryProvider);
    if (notificationRepository == null) {
      return const ColoredBox(
        color: VineTheme.backgroundColor,
        child: Center(
          child: CircularProgressIndicator(color: VineTheme.vineGreen),
        ),
      );
    }
    final followRepository = ref.watch(followRepositoryProvider);

    // Key on the watched dependency identities so the bloc rebuilds when
    // either repository swaps (account switch, sign-out → sign-in, or
    // provider invalidation). The upstream KeyedSubtree in `inbox_view.dart`
    // already forces this subtree to remount on pubkey change today, but
    // pinning the contract here keeps the page safe even if the inbox
    // scaffold is restructured. See `.claude/rules/state_management.md`.
    return BlocProvider(
      key: ValueKey((notificationRepository, followRepository)),
      create: (_) => NotificationFeedBloc(
        notificationRepository: notificationRepository,
        followRepository: followRepository,
      )..add(const NotificationFeedStarted()),
      child: const _InboxNotificationsScaffold(),
    );
  }
}

class _InboxNotificationsScaffold extends StatefulWidget {
  const _InboxNotificationsScaffold();

  @override
  State<_InboxNotificationsScaffold> createState() =>
      _InboxNotificationsScaffoldState();
}

class _InboxNotificationsScaffoldState
    extends State<_InboxNotificationsScaffold>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  static const _tabCount = 5;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabCount, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(VineTheme.shellInnerCornerRadius),
      ),
      child: ColoredBox(
        color: VineTheme.surfaceContainerHigh,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Material(
              type: MaterialType.transparency,
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                padding: const EdgeInsetsDirectional.only(start: 16),
                indicatorColor: VineTheme.tabIndicatorGreen,
                indicatorWeight: 4,
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: VineTheme.transparent,
                labelColor: VineTheme.whiteText,
                unselectedLabelColor: VineTheme.onSurfaceMuted55,
                labelPadding: const EdgeInsets.symmetric(horizontal: 14),
                labelStyle: VineTheme.titleMediumFont(),
                unselectedLabelStyle: VineTheme.titleMediumFont(
                  color: VineTheme.onSurfaceMuted55,
                ),
                tabs: [
                  Tab(text: context.l10n.notificationsTabAll),
                  Tab(text: context.l10n.notificationsTabLikes),
                  Tab(text: context.l10n.notificationsTabComments),
                  Tab(text: context.l10n.notificationsTabFollows),
                  Tab(text: context.l10n.notificationsTabReposts),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [
                  NotificationsView(),
                  NotificationsView(kindFilter: NotificationKind.like),
                  NotificationsView(kindFilter: NotificationKind.comment),
                  NotificationsView(kindFilter: NotificationKind.follow),
                  NotificationsView(kindFilter: NotificationKind.repost),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
