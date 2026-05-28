// ABOUTME: This just allows the button to be tapped again so we can do the super cool and magnificent refresh.

import 'package:flutter_riverpod/legacy.dart';

/// Incremented each time the user taps the home tab while already on it.
///
/// [VideoFeedView] listens to this and calls `_animateToFeedPage(0)` on
/// every increment, scrolling the feed back to position 0.
final homeTabRetapProvider = StateProvider<int>((ref) => 0);

/// True while the feed is actively refreshing after a home-tab retap.
///
/// Set to true by [VideoFeedView] when it dispatches [VideoFeedRefreshRequested]
/// and back to false when the bloc reaches success/failure. Read by
/// [_HomeTabButton] in the bottom nav to drive the refresh animation.
final homeTabRefreshingProvider = StateProvider<bool>((ref) => false);
