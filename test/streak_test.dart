import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/data/marks.dart';
import 'package:openword/src/model/bible.dart';
import 'package:openword/src/model/local_date.dart';
import 'package:openword/src/model/streak.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({'sleep': '{"mode":"off"}'}),
  );

  final monday = DateTime(2026, 9, 28, 9, 30);
  DateTime days(int n) => monday.add(Duration(days: n));

  test('a streak grows a day at a time and once a day', () {
    var streak = Streak.none;
    expect(streak.currentOn(monday), 0);
    streak = streak.extendedOn(monday);
    expect(streak.count, 1);
    expect(streak.practisedOn(monday), isTrue);
    expect(streak.extendedOn(monday.add(const Duration(hours: 5))), streak);
    streak = streak.extendedOn(days(1));
    expect(streak.count, 2);
    expect(streak.best, 2);
    expect(streak.last, LocalDate.only(days(1)));
  });

  test('it stands through the next day and breaks after', () {
    final streak = Streak.none.extendedOn(monday).extendedOn(days(1));
    expect(streak.currentOn(days(1)), 2);
    expect(streak.currentOn(days(2)), 2);
    expect(streak.needsPractiseOn(days(2)), isTrue);
    expect(streak.needsPractiseOn(days(1)), isFalse);
    expect(streak.currentOn(days(3)), 0);
    expect(streak.needsPractiseOn(days(3)), isFalse);
    // A new run starts at one; the best is kept.
    final again = streak.extendedOn(days(3));
    expect(again.count, 1);
    expect(again.best, 2);
  });

  test('a clock set back does not count the run', () {
    final streak = Streak.none.extendedOn(days(2));
    expect(streak.currentOn(monday), 0);
  });

  test('round-trips through JSON, and refuses nonsense', () {
    final streak = Streak.none.extendedOn(monday).extendedOn(days(1));
    expect(Streak.fromJson(streak.toJson()), streak);
    expect(Streak.fromJson({'count': -1}), isNull);
    expect(Streak.fromJson({'count': 'x'}), isNull);
    // A best below the count is the count.
    expect(Streak.fromJson({'count': 3, 'best': 1})!.best, 3);
  });

  group('in the store', () {
    const john = Reference('JHN', 3, 16);

    test('practice is recorded, kept, and shown on the next day', () async {
      var today = monday;
      final store = await ReadingStore.load(clock: () => today);
      expect(store.streak.currentOn(today), 0);
      store.recordPractice();
      store.recordPractice();
      expect(store.streak.count, 1);
      expect(store.streak.practisedOn(today), isTrue);

      today = days(1);
      final again = await ReadingStore.load(clock: () => today);
      expect(again.streak.currentOn(today), 1);
      expect(again.streak.needsPractiseOn(today), isTrue);
      again.recordPractice();
      expect(again.streak.count, 2);
    });

    test('goes into a backup and the better one is kept', () async {
      var today = monday;
      final store = await ReadingStore.load(clock: () => today);
      store.toggleMemorise(john);
      store.recordPractice();
      today = days(1);
      store.recordPractice();
      final backup = store.export();
      expect(backup, contains('"streak"'));

      SharedPreferences.setMockInitialValues({});
      final fresh = await ReadingStore.load(clock: () => today);
      expect(fresh.import(backup).ok, isTrue);
      expect(fresh.streak, store.streak);

      // The device practised on more recently sets the run; the best of
      // the two stays the best.
      SharedPreferences.setMockInitialValues({});
      today = days(5);
      final other = await ReadingStore.load(clock: () => today);
      other.recordPractice();
      final merged = await ReadingStore.load(clock: () => today);
      merged.import(backup);
      expect(merged.streak.best, 2);
      merged.import(other.export());
      expect(merged.streak.count, 1);
      expect(merged.streak.best, 2);
      expect(merged.streak.last, LocalDate.only(today));
      // The older backup brought back changes nothing.
      expect(merged.import(backup).total, 0);
    });

    test('a backup holding only a streak still imports', () async {
      final store = await ReadingStore.load(clock: () => monday);
      store.recordPractice();
      expect(store.hasBackupContent, isTrue);
      SharedPreferences.setMockInitialValues({});
      final fresh = await ReadingStore.load(clock: () => monday);
      expect(fresh.import(store.export()).ok, isTrue);
      expect(fresh.streak.count, 1);
    });
  });
}
