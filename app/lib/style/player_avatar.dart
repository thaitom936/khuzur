import 'package:flutter/material.dart';

/// Original, bundled vector portraits: crisp at every table and lobby size.
enum DefaultAvatar {
  fox,
  cat,
  dog,
  bear,
  rabbit,
  panda,
  koala,
  lion,
  owl,
  penguin,
  tiger,
  raccoon,
}

DefaultAvatar defaultAvatarFor(String name) {
  var hash = 0;
  for (final rune in name.trim().runes) {
    hash = (hash * 31 + rune) & 0x7fffffff;
  }
  return DefaultAvatar.values[hash % DefaultAvatar.values.length];
}

class PlayerAvatar extends StatelessWidget {
  final String name;
  final double size;
  final DefaultAvatar? avatar;

  const PlayerAvatar({
    required this.name,
    this.size = 40,
    this.avatar,
    super.key,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: name,
    child: RepaintBoundary(
      child: ClipOval(
        child: CustomPaint(
          size: Size.square(size),
          painter: _AvatarPainter(avatar ?? defaultAvatarFor(name)),
        ),
      ),
    ),
  );
}

class _AvatarPainter extends CustomPainter {
  final DefaultAvatar avatar;
  const _AvatarPainter(this.avatar);

  static const _backgrounds = [
    0xfff9dfc4,
    0xffdfe3f4,
    0xffd6e8ee,
    0xffe4dbc9,
    0xffefdeeb,
    0xffd7eadf,
    0xffe0e6f0,
    0xfff4e5b7,
    0xffdfdeef,
    0xffd8eaf3,
    0xfff4dfd1,
    0xffdce7dd,
  ];
  static const _coats = [
    0xffdd824b,
    0xff949bb5,
    0xffbd8963,
    0xff9b7056,
    0xfff7f0e6,
    0xfff8f6ea,
    0xff9aa9b0,
    0xffdfa650,
    0xff95735d,
    0xff354e60,
    0xffe4a04c,
    0xff9aabb0,
  ];
  static const ink = Color(0xff293b40);
  static const cream = Color(0xfffff3df);
  static const pink = Color(0xffd79591);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 96, size.height / 96);
    final coat = Color(_coats[avatar.index]);
    void oval(double x, double y, double w, double h, Color color) =>
        canvas.drawOval(
          Rect.fromCenter(center: Offset(x, y), width: w, height: h),
          Paint()..color = color,
        );
    void line(List<Offset> points, Color color, [double width = 2]) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    void shape(List<Offset> points, Color color) {
      final path = Path()..addPolygon(points, true);
      canvas.drawPath(path, Paint()..color = color);
    }

    void pointedEars() {
      shape(const [Offset(18, 43), Offset(17, 14), Offset(40, 33)], coat);
      shape(const [Offset(56, 33), Offset(79, 14), Offset(78, 43)], coat);
      shape(const [Offset(23, 33), Offset(22, 22), Offset(33, 33)], pink);
      shape(const [Offset(63, 33), Offset(74, 22), Offset(73, 33)], pink);
    }

    oval(48, 48, 96, 96, Color(_backgrounds[avatar.index]));
    oval(71, 16, 40, 40, Colors.white.withValues(alpha: .18));
    oval(48, 99, 67, 53, coat);
    oval(48, 93, 34, 33, cream);
    switch (avatar) {
      case DefaultAvatar.rabbit:
        oval(32, 25, 19, 47, coat);
        oval(64, 25, 19, 47, coat);
        oval(32, 23, 8, 30, pink);
        oval(64, 23, 8, 30, pink);
      case DefaultAvatar.fox ||
          DefaultAvatar.cat ||
          DefaultAvatar.tiger ||
          DefaultAvatar.raccoon:
        pointedEars();
      case DefaultAvatar.bear || DefaultAvatar.panda || DefaultAvatar.koala:
        final earColor = avatar == DefaultAvatar.panda ? ink : coat;
        final diameter = avatar == DefaultAvatar.koala ? 33.0 : 25.0;
        oval(22, 32, diameter, diameter, earColor);
        oval(74, 32, diameter, diameter, earColor);
        if (avatar != DefaultAvatar.panda) {
          oval(
            22,
            32,
            diameter * .55,
            diameter * .55,
            pink.withValues(alpha: .65),
          );
          oval(
            74,
            32,
            diameter * .55,
            diameter * .55,
            pink.withValues(alpha: .65),
          );
        }
      case DefaultAvatar.lion:
        oval(48, 51, 80, 79, const Color(0xffa96e41));
        oval(19, 32, 16, 20, const Color(0xffa96e41));
        oval(77, 32, 16, 20, const Color(0xffa96e41));
      case DefaultAvatar.dog:
        oval(22, 47, 24, 54, const Color(0xff805744));
        oval(74, 47, 24, 54, const Color(0xff805744));
      case DefaultAvatar.owl:
        shape(const [Offset(19, 43), Offset(16, 15), Offset(42, 30)], coat);
        shape(const [Offset(54, 30), Offset(80, 15), Offset(77, 43)], coat);
      case DefaultAvatar.penguin:
        break;
    }
    oval(48, 53, avatar == DefaultAvatar.penguin ? 63 : 65, 64, coat);
    if (avatar == DefaultAvatar.fox) {
      shape(const [
        Offset(18, 48),
        Offset(45, 65),
        Offset(48, 79),
        Offset(29, 72),
      ], cream);
      shape(const [
        Offset(78, 48),
        Offset(51, 65),
        Offset(48, 79),
        Offset(67, 72),
      ], cream);
    } else if (avatar == DefaultAvatar.penguin || avatar == DefaultAvatar.owl) {
      oval(34, 51, 28, 39, cream);
      oval(62, 51, 28, 39, cream);
      oval(48, 67, 44, 27, cream);
    } else {
      oval(48, 67, 37, 25, cream);
    }
    if (avatar == DefaultAvatar.panda) {
      oval(32, 49, 19, 24, ink);
      oval(64, 49, 19, 24, ink);
    }
    if (avatar == DefaultAvatar.raccoon) {
      oval(30, 49, 27, 19, ink);
      oval(66, 49, 27, 19, ink);
      oval(48, 50, 24, 12, ink);
    }
    if (avatar == DefaultAvatar.dog) {
      oval(33, 48, 24, 29, const Color(0xff805744));
    }
    if (avatar == DefaultAvatar.cat || avatar == DefaultAvatar.tiger) {
      final stripe = avatar == DefaultAvatar.tiger
          ? const Color(0xff80523d)
          : const Color(0xff69758d);
      line(const [Offset(39, 25), Offset(41, 34)], stripe, 3);
      line(const [Offset(48, 23), Offset(48, 34)], stripe, 3);
      line(const [Offset(57, 25), Offset(55, 34)], stripe, 3);
      if (avatar == DefaultAvatar.tiger) {
        line(const [Offset(17, 48), Offset(26, 51)], stripe, 3);
        line(const [Offset(79, 48), Offset(70, 51)], stripe, 3);
      }
      for (final y in [61.0, 67.0]) {
        line(
          [Offset(17, y - 2), Offset(30, y)],
          ink.withValues(alpha: .5),
          1.5,
        );
        line(
          [Offset(66, y), Offset(79, y - 2)],
          ink.withValues(alpha: .5),
          1.5,
        );
      }
    }
    final lightEyes =
        avatar == DefaultAvatar.panda || avatar == DefaultAvatar.raccoon;
    if (avatar == DefaultAvatar.owl) {
      oval(33, 48, 19, 21, const Color(0xffdcb972));
      oval(63, 48, 19, 21, const Color(0xffdcb972));
    }
    for (final x in [33.0, 63.0]) {
      oval(x, 49, 7, 9, lightEyes ? cream : ink);
      oval(x + 1, 47, 2, 2, lightEyes ? ink : Colors.white);
    }
    if (avatar == DefaultAvatar.owl || avatar == DefaultAvatar.penguin) {
      shape(const [
        Offset(41, 60),
        Offset(55, 60),
        Offset(48, 70),
      ], const Color(0xffe5a643));
    } else {
      oval(
        48,
        avatar == DefaultAvatar.koala ? 57 : 62,
        avatar == DefaultAvatar.koala ? 14 : 10,
        avatar == DefaultAvatar.koala ? 21 : 7,
        ink,
      );
      line(const [Offset(48, 65), Offset(48, 71), Offset(43, 73)], ink, 1.6);
      line(const [Offset(48, 71), Offset(53, 73)], ink, 1.6);
    }
    if (avatar == DefaultAvatar.rabbit || avatar == DefaultAvatar.cat) {
      oval(25, 59, 10, 5, pink.withValues(alpha: .6));
      oval(71, 59, 10, 5, pink.withValues(alpha: .6));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AvatarPainter oldDelegate) =>
      oldDelegate.avatar != avatar;
}
