import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openvine/widgets/branded_loading_indicator.dart';
import 'package:openvine/widgets/video_feed_item/video_loading_placeholder.dart';
import 'package:openvine/widgets/vine_cached_image.dart';

void main() {
  Widget buildSubject({
    String? thumbnailUrl,
    bool shouldPortraitExpand = true,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: VideoLoadingPlaceholder(
          videoId: 'video-1',
          index: 0,
          feedMode: 'following',
          thumbnailUrl: thumbnailUrl,
          shouldPortraitExpand: shouldPortraitExpand,
        ),
      ),
    );
  }

  group('VideoLoadingPlaceholder', () {
    testWidgets('uses VineCachedImage when a thumbnail URL is present', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildSubject(thumbnailUrl: 'https://example.com/thumb.jpg'),
      );

      expect(find.byType(VineCachedImage), findsOneWidget);
      expect(find.byType(BrandedLoadingIndicator), findsOneWidget);
    });

    testWidgets('shows only the loading indicator when thumbnail is missing', (
      tester,
    ) async {
      await tester.pumpWidget(buildSubject());

      expect(find.byType(VineCachedImage), findsNothing);
      expect(find.byType(BrandedLoadingIndicator), findsOneWidget);
    });
  });
}
