/// Calendar dates, kept as midnight UTC of the local day.
///
/// A date held that way is a whole number of days from any other, so the
/// days between two of them are never 23 or 25 hours across a change of
/// clocks, and one written down reads back as the same day anywhere.
abstract final class LocalDate {
  /// Midnight UTC of [moment]'s local calendar date.
  static DateTime only(DateTime moment) =>
      DateTime.utc(moment.year, moment.month, moment.day);

  static String format(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static DateTime? parse(Object? raw) {
    if (raw is! String) return null;
    final parts = raw.split('-');
    if (parts.length != 3) return null;
    final numbers = parts.map(int.tryParse).toList();
    if (numbers.contains(null)) return null;
    return DateTime.utc(numbers[0]!, numbers[1]!, numbers[2]!);
  }
}
