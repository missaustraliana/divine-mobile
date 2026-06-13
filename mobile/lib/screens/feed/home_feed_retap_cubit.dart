// ABOUTME: This just allows the button to be tapped again so we can do the super cool and magnificent refresh.

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum HomeFeedRetapStatus { idle, refreshing }

class HomeFeedRetapState extends Equatable {
  const HomeFeedRetapState({this.status = HomeFeedRetapStatus.idle});

  final HomeFeedRetapStatus status;

  bool get isRefreshing => status == HomeFeedRetapStatus.refreshing;

  HomeFeedRetapState copyWith({HomeFeedRetapStatus? status}) =>
      HomeFeedRetapState(status: status ?? this.status);

  @override
  List<Object?> get props => [status];
}

/// Coordinates home tab retap gesture to refresh the feed.
///
/// [VineBottomNav] calls [request] when the home tab is tapped while already
/// on home. The nav bar shows a loading spinner while [isRefreshing] is true
/// and ignores taps until the refresh completes.
///
/// [VideoFeedView] listens via [BlocListener]: on [request] it dispatches a
/// feed refresh and calls [completeRefresh] when it settles, at which point
/// [FeedVideosState.animateToPage(0)] scrolls the feed back to the top.
///
/// Provided in [app_router.dart] above the home [Navigator] so it is
/// reachable from both [VineBottomNav] (via [NavigatorKeys.home.currentContext])
/// and [VideoFeedView].
class HomeFeedRetapCubit extends Cubit<HomeFeedRetapState> {
  HomeFeedRetapCubit() : super(const HomeFeedRetapState());

  /// Request a refresh.
  void request() {
    if (state.isRefreshing) return;
    emit(state.copyWith(status: HomeFeedRetapStatus.refreshing));
  }

  /// Called by [VideoFeedView] once the feed refresh has settled.
  void completeRefresh() {
    emit(state.copyWith(status: HomeFeedRetapStatus.idle));
  }
}
