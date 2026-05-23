import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openvine/widgets/user_avatar.dart';
import 'package:openvine/widgets/vine_cached_image.dart';

final Uint8List _transparentImageBytes = Uint8List.fromList(<int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

void main() {
  Widget buildAvatar({String? imageUrl}) {
    return MaterialApp(
      home: Scaffold(
        body: UserAvatar(imageUrl: imageUrl, name: 'Test User'),
      ),
    );
  }

  group('UserAvatar.isSvgImageUrl', () {
    test('returns true for svg URLs', () {
      expect(
        UserAvatar.isSvgImageUrl('https://divine.video/divine-logo.svg'),
        isTrue,
      );
      expect(
        UserAvatar.isSvgImageUrl(
          'https://divine.video/divine-logo.svg?size=128',
        ),
        isTrue,
      );
      expect(
        UserAvatar.isSvgImageUrl(
          'https://divine.video/assets/DIVINE-LOGO.SVG#avatar',
        ),
        isTrue,
      );
    });

    test('returns false for non-svg or invalid URLs', () {
      expect(
        UserAvatar.isSvgImageUrl('https://divine.video/avatar.png'),
        isFalse,
      );
      expect(UserAvatar.isSvgImageUrl('not a url'), isFalse);
      expect(UserAvatar.isSvgImageUrl(null), isFalse);
      expect(UserAvatar.isSvgImageUrl(''), isFalse);
    });
  });

  group('UserAvatar rendering', () {
    testWidgets('keeps raster avatar URLs on VineCachedImage', (tester) async {
      await tester.pumpWidget(
        buildAvatar(imageUrl: 'https://divine.video/avatar.png'),
      );

      expect(find.byType(VineCachedImage), findsOneWidget);
    });

    testWidgets('renders direct image providers without network widgets', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UserAvatar(
              imageProvider: MemoryImage(_transparentImageBytes),
              name: 'Test User',
            ),
          ),
        ),
      );

      expect(find.byType(Image), findsOneWidget);
      expect(find.byType(VineCachedImage), findsNothing);
    });
  });
}
