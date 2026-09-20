import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'src/app_scope.dart';
import 'src/data/library.dart';
import 'src/data/marks.dart';
import 'src/data/settings.dart';
import 'src/data/shelf.dart';
import 'src/data/updates.dart';
import 'src/ui/reader_screen.dart';
import 'src/ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await Settings.load();
  final reading = await ReadingStore.load();
  final shelf = await _openShelf();
  final library = LibraryController(shelf: shelf);
  // Reading the Scripture takes a fraction of a second; start it while the
  // first frame is being built.
  library.load(settings.translationId);
  runApp(
    OpenWordApp(
      settings: settings,
      reading: reading,
      library: library,
      updates: UpdateService(settings: settings),
    ),
  );
}

/// Finds the directory imported translations live in.
///
/// Returns null on the web, and on any platform that will not say where its
/// documents go: the app then reads only what it ships with.
Future<Shelf?> _openShelf() async {
  if (kIsWeb) return null;
  try {
    final documents = await getApplicationDocumentsDirectory();
    final shelf = Shelf.at('${documents.path}/translations');
    await shelf?.refresh();
    return shelf;
  } on Object catch (error) {
    debugPrint('OpenWord: no shelf for imported translations: $error');
    return null;
  }
}

class OpenWordApp extends StatelessWidget {
  const OpenWordApp({
    required this.settings,
    required this.reading,
    required this.library,
    required this.updates,
    super.key,
  });

  final Settings settings;
  final ReadingStore reading;
  final LibraryController library;
  final UpdateService updates;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      settings: settings,
      library: library,
      reading: reading,
      updates: updates,
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

/// Shows the reader once the Scripture is decoded, and a splash until then.
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final library = AppScope.of(context).library;
    return AnimatedBuilder(
      animation: library,
      builder: (context, _) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: library.isReady
            ? const ReaderScreen()
            : _Splash(message: library.errorMessage),
      ),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash({this.message});

  /// Set when the bundled text could not be read at all.
  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Icon(
                  Icons.auto_stories_rounded,
                  size: 48,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'OpenWord',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              if (message == null)
                const SizedBox(
                  width: 120,
                  child: LinearProgressIndicator(minHeight: 4),
                )
              else
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
