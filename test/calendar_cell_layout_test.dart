// N51 F（L2）：カレンダーの行の高さ
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/services/calendar_cell_layout.dart';

void main() {
  group('calendarRowHeight', () {
    test('1.0 倍は今までどおり 75', () {
      expect(calendarRowHeight(1.0), 75);
    });

    test('1.0 倍より小さくても 75（縮めない）', () {
      expect(calendarRowHeight(0.85), 75);
    });

    test('1.3 倍は 86（文字の行だけ伸ばす）', () {
      expect(calendarRowHeight(1.3), 86);
    });

    test('1.3 倍より大きくても、マスの中の上限 1.3 倍と同じ高さ', () {
      expect(calendarRowHeight(2.0), calendarRowHeight(calendarCellMaxTextScale));
    });

    test('倍率が大きくなるほど低くならない', () {
      expect(calendarRowHeight(1.15), greaterThan(75));
      expect(calendarRowHeight(1.15), lessThanOrEqualTo(calendarRowHeight(1.3)));
    });
  });

  group('calendarDaysOfWeekHeight', () {
    test('1.0 倍は table_calendar の既定の 16', () {
      expect(calendarDaysOfWeekHeight(1.0), 16);
    });

    test('1.0 倍より小さくても 16', () {
      expect(calendarDaysOfWeekHeight(0.85), 16);
    });

    test('1.3 倍は 22、2.0 倍は 34（上限はつけない）', () {
      expect(calendarDaysOfWeekHeight(1.3), 22);
      expect(calendarDaysOfWeekHeight(2.0), 34);
    });

    test('2.0 倍の曜日（14px の 2 倍、行の高さ約 1.17）が入る', () {
      expect(calendarDaysOfWeekHeight(2.0), greaterThanOrEqualTo(14 * 2.0 * 1.17));
    });
  });
}
