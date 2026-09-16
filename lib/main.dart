import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

import 'src/app_scope.dart';
import 'src/data/bookmarks.dart';
import 'src/data/library.dart';
import 'src/data/settings.dart';
import 'src/ui/download_screen.dart';
import 'src/ui/reader_screen.dart';
import 'src/ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await Settings.load();
  final reading = await ReadingStore.load();
  final library = LibraryController();
  // Kick off the cache lookup while the first frame is being built.
  library.initialize(settings.translationId);
  runApp(OpenWordApp(settings: settings, reading: reading, library: library));
}

class OpenWordApp extends StatelessWidget {
  const OpenWordApp({
    required this.settings,
    required this.reading,
    required this.library,
    super.key,
  });

  final Settings settings;
  final ReadingStore reading;
  final LibraryController library;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      settings: settings,
      library: library,
      reading: reading,
      child: AnimatedBuilder(
        animation: settings,
        builder: (context, _) {
          return DynamicColorBuilder(
            builder: (lightDynamic, darkDynamic) => MaterialApp(
              title: 'OpenWord',
              debugShowCheckedModeBanner: false,
              themeMode: settings.themeMode,
              theme: AppTheme.build(
                dynamicScheme: lightDynamic,
                settings: settings,
                brightness: Brightness.light,
              ),
              darkTheme: AppTheme.build(
                dynamicScheme: darkDynamic,
                settings: settings,
                brightness: Brightness.dark,
              ),
              home: const _Root(),
            ),
          );
        },
      ),
    );
  }
}

/// Shows the reader once a Bible is on the device, and the download flow
/// before that.
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final library = AppScope.of(context).library;
    return AnimatedBuilder(
      animation: library,
      builder: (context, _) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        child: library.isReady ? const ReaderScreen() : const DownloadScreen(),
      ),
    );
  }
}
