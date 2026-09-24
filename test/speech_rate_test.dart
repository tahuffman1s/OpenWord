import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/data/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<Settings> withPrefs(Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    return Settings.load();
  }

  test('1× is the voice\'s natural pace, unless chosen', () async {
    expect((await withPrefs(const {})).speechRate, 1.0);
  });

  test('a speed chosen before 1.23 sounds the same after it', () async {
    // 1.25× of the old, slower pace is the natural pace.
    expect((await withPrefs(const {'speechRate': 1.25})).speechRate, 1.0);
    expect((await withPrefs(const {'speechRate': 2.0})).speechRate, 1.5);
    expect((await withPrefs(const {'speechRate': 0.75})).speechRate, 0.75);
  });

  test('a speed chosen since is kept as chosen', () async {
    final settings = await withPrefs(const {'speechRate': 2.0});
    settings.speechRate = 1.25;
    expect(settings.speechRate, 1.25);
  });
}
