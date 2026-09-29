// Run from app/: flutter test tool/export_default_avatars.dart
// Exports the same original vector artwork used by PlayerAvatar for reuse.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:card/style/player_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('export default avatar library and contact sheet', (
    tester,
  ) async {
    await (FontLoader('Preview')..addFont(
          rootBundle.load(
            'assets/fonts/Permanent_Marker/PermanentMarker-Regular.ttf',
          ),
        ))
        .load();
    final output = Directory('../design/avatars')..createSync(recursive: true);
    tester.view.physicalSize = const Size(960, 840);
    tester.view.devicePixelRatio = 1;
    final key = GlobalKey();
    Future<void> save(Widget child, String filename) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Preview'),
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(key: key, child: child),
            ),
          ),
        ),
      );
      await tester.pump();
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '${output.path}/$filename.png',
        ).writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }

    for (final avatar in DefaultAvatar.values) {
      await save(
        PlayerAvatar(name: avatar.name, avatar: avatar, size: 512),
        avatar.name,
      );
    }
    await save(
      Container(
        width: 960,
        height: 840,
        color: const Color(0xfff5f3ed),
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            const Text(
              'MUUSHIG · DEFAULT AVATARS',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: Color(0xff183f35),
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: GridView.count(
                crossAxisCount: 4,
                childAspectRatio: 1.05,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (final avatar in DefaultAvatar.values)
                    Column(
                      children: [
                        PlayerAvatar(
                          name: avatar.name,
                          avatar: avatar,
                          size: 154,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          avatar.name.toUpperCase(),
                          style: const TextStyle(
                            color: Color(0xff244b43),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      'preview',
    );
    await tester.pumpWidget(const SizedBox());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
