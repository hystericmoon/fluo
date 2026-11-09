import 'package:flutter_test/flutter_test.dart';
import 'package:fluo/data/format.dart';

void main() {
  final now = DateTime(2026, 11, 9, 15); // a Monday

  test('relativeDay', () {
    expect(relativeDay(DateTime(2026, 11, 9, 1), now: now), 'Today');
    expect(relativeDay(DateTime(2026, 11, 8, 23), now: now), 'Yesterday');
    expect(relativeDay(DateTime(2026, 11, 5), now: now), 'Thu');
    expect(relativeDay(DateTime(2026, 11, 3), now: now), 'Tue', reason: '6 days ago');
    expect(relativeDay(DateTime(2026, 11, 2), now: now), 'Last week', reason: '7 days ago');
    expect(relativeDay(DateTime(2026, 11, 1), now: now), 'Nov 1', reason: 'the Sunday before last week');
    expect(relativeDay(DateTime(2026, 10, 26), now: now), 'Oct 26', reason: 'two weeks back');
    expect(relativeDay(DateTime(2026, 10, 28), now: now), 'Oct 28');
    expect(relativeDay(DateTime(2025, 1, 2), now: now), 'Jan 2');
  });

  test('a late-night edit is still Today across midnight boundaries', () {
    expect(relativeDay(DateTime(2026, 11, 9, 23, 59), now: DateTime(2026, 11, 9, 0, 1)), 'Today');
  });

  test('Last week follows the calendar week, not a day count', () {
    final wed = DateTime(2026, 11, 11); // Wednesday
    expect(relativeDay(DateTime(2026, 11, 8), now: wed), 'Sun'); // 3 days ago
    expect(relativeDay(DateTime(2026, 11, 4), now: wed), 'Last week'); // Wed of last week, 7 days ago
    expect(relativeDay(DateTime(2026, 11, 2), now: wed), 'Last week'); // its Monday
    expect(relativeDay(DateTime(2026, 11, 1), now: wed), 'Nov 1');
  });

  test('a clock change does not skip a day', () {
    // 2026-03-29 is when Europe springs forward; UTC day maths is unaffected.
    expect(relativeDay(DateTime(2026, 3, 28, 12), now: DateTime(2026, 3, 29, 0, 30)), 'Yesterday');
  });

  test('screensLabel', () {
    expect(screensLabel(0), '0 screens');
    expect(screensLabel(1), '1 screen');
    expect(screensLabel(19), '19 screens');
  });
}
