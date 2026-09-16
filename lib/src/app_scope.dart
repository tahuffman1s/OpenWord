import 'package:flutter/widgets.dart';

import 'data/marks.dart';
import 'data/library.dart';
import 'data/settings.dart';

/// Makes the three app-wide stores available to the widget tree.
///
/// Each store is a [ChangeNotifier]; widgets listen to the one they care about
/// with an [AnimatedBuilder] rather than rebuilding the whole app.
class AppScope extends InheritedWidget {
  const AppScope({
    required this.settings,
    required this.library,
    required this.reading,
    required super.child,
    super.key,
  });

  final Settings settings;
  final LibraryController library;
  final ReadingStore reading;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope found in context');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      settings != oldWidget.settings ||
      library != oldWidget.library ||
      reading != oldWidget.reading;
}
