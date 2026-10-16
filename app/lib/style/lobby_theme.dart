import 'package:flutter/material.dart';

Future<T?> showLobbyDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) => showDialog<T>(
  context: context,
  builder: (_) => LobbyTheme(child: Builder(builder: builder)),
);

/// Shared chrome for the lobby, club pages and every chat surface.
class LobbyTheme extends StatelessWidget {
  const LobbyTheme({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final dark = base.brightness == Brightness.dark;
    final background = Color(dark ? 0xff18221e : 0xfff5f3ed);
    final surface = Color(dark ? 0xff26352e : 0xffffffff);
    final ink = Color(dark ? 0xffecf3ed : 0xff203b32);
    final primary = Color(dark ? 0xffb1d3be : 0xff183f35);
    final soft = Color(dark ? 0xff344d3e : 0xffe7efe7);
    final line = Color(dark ? 0xff3e5146 : 0xffdfe5de);
    final scheme = base.colorScheme.copyWith(
      primary: primary,
      onPrimary: Color(dark ? 0xff17372a : 0xffffffff),
      surface: surface,
      onSurface: ink,
      onSurfaceVariant: Color(dark ? 0xffafc3b5 : 0xff62736b),
      secondaryContainer: soft,
      onSecondaryContainer: primary,
      outlineVariant: line,
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    final button = FilledButton.styleFrom(
      minimumSize: const Size(48, 48),
      shape: shape,
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
    );
    return Theme(
      data: base.copyWith(
        colorScheme: scheme,
        scaffoldBackgroundColor: background,
        textTheme: base.textTheme.apply(bodyColor: ink, displayColor: ink),
        appBarTheme: AppBarTheme(
          backgroundColor: background,
          foregroundColor: ink,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          toolbarHeight: 64,
          titleSpacing: 16,
          titleTextStyle: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: ink,
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: surface,
          indicatorColor: soft,
          elevation: 0,
          labelTextStyle: WidgetStatePropertyAll(
            TextStyle(fontSize: 12, color: ink),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(style: button),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(48, 48),
            shape: shape,
            side: BorderSide(color: line),
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        cardTheme: CardThemeData(
          color: surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: line),
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        chipTheme: base.chipTheme.copyWith(
          backgroundColor: background,
          selectedColor: primary,
          secondarySelectedColor: primary,
          side: BorderSide.none,
          shape: const StadiumBorder(),
        ),
      ),
      child: child,
    );
  }
}
