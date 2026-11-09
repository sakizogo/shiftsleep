import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/models/vacation_model.dart';
import 'package:shiftsleep/services/vacation_allocation.dart';
import 'package:shiftsleep/services/vacation_load_state.dart';

// N118 3/4 3b：有給設定を読み込めなかったときに押せるかどうかの判定・知らせの文言・入力欄の値（P8）のテスト

VacationSettings _settings() => VacationSettings(
      userId: 'test_user',
      hiredDate: DateTime(2024, 4, 1),
      annualDays: 11,
      createdAt: DateTime(2024, 4, 1),
      updatedAt: DateTime(2024, 4, 1),
    );

final _carryOver = CarryOver(baseDate: DateTime(2025, 10, 1), days: 5);

void main() {
  group('canEditVacationSettings', () {
    test('読み込み中は押せない', () {
      expect(canEditVacationSettings(VacationLoadState.loading), isFalse);
    });
    test('失敗中は押せない', () {
      expect(canEditVacationSettings(VacationLoadState.failed), isFalse);
    });
    test('読み込めていれば押せる', () {
      expect(canEditVacationSettings(VacationLoadState.loaded), isTrue);
    });
  });

  group('canReloadVacationSettings', () {
    test('再読み込み中でなければ押せる', () {
      expect(canReloadVacationSettings(reloading: false), isTrue);
    });
    test('再読み込み中は押せない（二度押し防止）', () {
      expect(canReloadVacationSettings(reloading: true), isFalse);
    });
  });

  group('vacationSettingsReloadMessage', () {
    test('成功は ✅ で既定の色', () {
      final message = vacationSettingsReloadMessage(succeeded: true);
      expect(message.text, startsWith('✅'));
      expect(message.color, isNull);
    });
    test('失敗は ⚠️ でオレンジ', () {
      final message = vacationSettingsReloadMessage(succeeded: false);
      expect(message.text, startsWith('⚠️'));
      expect(message.color, Colors.orange);
    });
  });

  test('失敗の画面の文言は ❌ で始まり、保存できないことと［再読み込み］を伝える', () {
    expect(vacationSettingsLoadFailedTitle, startsWith('❌'));
    expect(vacationSettingsLoadFailedBody, contains('保存'));
    expect(vacationSettingsLoadFailedBody, contains('再読み込み'));
  });

  group('vacationFormValues', () {
    test('P8：vacation_settings の行がなくても、持ち越しと初回付与日は入る', () {
      final form = vacationFormValues(
        settings: null,
        carriedOverDays: 5,
        carryOver: _carryOver,
        hasCarryOverTarget: true,
        carryOverExpired: false,
        firstAccrualDate: DateTime(2024, 10, 1),
      );
      expect(form.carriedOverText, '5');
      expect(form.carriedOverBaseDate, DateTime(2025, 10, 1));
      expect(form.firstAccrualDateText, '2024年10月1日');
    });

    test('行がなければ入社日と付与日数は null（欄はそのまま）', () {
      final form = vacationFormValues(
        settings: null,
        carriedOverDays: 0,
        carryOver: null,
        hasCarryOverTarget: false,
        carryOverExpired: false,
        firstAccrualDate: null,
      );
      expect(form.hiredDate, isNull);
      expect(form.annualDaysText, isNull);
    });

    test('行があれば入社日と付与日数が入る', () {
      final form = vacationFormValues(
        settings: _settings(),
        carriedOverDays: 0,
        carryOver: null,
        hasCarryOverTarget: false,
        carryOverExpired: false,
        firstAccrualDate: null,
      );
      expect(form.hiredDate, DateTime(2024, 4, 1));
      expect(form.annualDaysText, '11');
    });

    test('持ち越しが 0 なら空', () {
      final form = vacationFormValues(
        settings: _settings(),
        carriedOverDays: 0,
        carryOver: null,
        hasCarryOverTarget: false,
        carryOverExpired: false,
        firstAccrualDate: null,
      );
      expect(form.carriedOverText, '');
      expect(form.carriedOverBaseDate, isNull);
    });

    test('対象の付与が失効していれば、持ち越しは空で基準日も出さない（N80）', () {
      final form = vacationFormValues(
        settings: _settings(),
        carriedOverDays: 5,
        carryOver: _carryOver,
        hasCarryOverTarget: true,
        carryOverExpired: true,
        firstAccrualDate: null,
      );
      expect(form.carriedOverText, '');
      expect(form.carriedOverBaseDate, isNull);
    });

    test('対象の付与がなければ、持ち越しは入るが基準日は出さない', () {
      final form = vacationFormValues(
        settings: _settings(),
        carriedOverDays: 5,
        carryOver: _carryOver,
        hasCarryOverTarget: false,
        carryOverExpired: false,
        firstAccrualDate: null,
      );
      expect(form.carriedOverText, '5');
      expect(form.carriedOverBaseDate, isNull);
    });

    test('初回付与日が未登録なら null（欄はそのまま）', () {
      final form = vacationFormValues(
        settings: _settings(),
        carriedOverDays: 0,
        carryOver: null,
        hasCarryOverTarget: false,
        carryOverExpired: false,
        firstAccrualDate: null,
      );
      expect(form.firstAccrualDateText, isNull);
    });
  });

  // ========== N118 3/4 3c：有給使用画面 ==========

  group('canAddVacationUsage', () {
    test('読み込み中は追加・削除できない', () {
      expect(canAddVacationUsage(VacationLoadState.loading), isFalse);
    });
    test('失敗中は追加・削除できない', () {
      expect(canAddVacationUsage(VacationLoadState.failed), isFalse);
    });
    test('読み込めていれば追加・削除できる', () {
      expect(canAddVacationUsage(VacationLoadState.loaded), isTrue);
    });
  });

  group('vacationUsageReloadMessage', () {
    test('成功は ✅ で既定の色', () {
      final message = vacationUsageReloadMessage(succeeded: true);
      expect(message.text, startsWith('✅'));
      expect(message.color, isNull);
    });
    test('失敗は ⚠️ でオレンジ', () {
      final message = vacationUsageReloadMessage(succeeded: false);
      expect(message.text, startsWith('⚠️'));
      expect(message.color, Colors.orange);
    });
  });

  test('有給使用画面の失敗の文言は ❌ で始まり、追加できないことと［再読み込み］を伝える', () {
    expect(vacationUsageLoadFailedTitle, startsWith('❌'));
    expect(vacationUsageLoadFailedBody, contains('追加'));
    expect(vacationUsageLoadFailedBody, contains('再読み込み'));
  });

  // ========== N118 3/4 3d：有給の統計カード ==========

  group('vacationStatsDaysText', () {
    test('読めなかった（null）は「—」', () {
      expect(vacationStatsDaysText(null), '—');
    });
    test('0 日は「0.0日」（失敗と分ける）', () {
      expect(vacationStatsDaysText(0), '0.0日');
    });
    test('半日は小数 1 桁', () {
      expect(vacationStatsDaysText(1.5), '1.5日');
    });
  });

  group('showVacationStatsDetails', () {
    test('読み込み中は内訳・消滅予定を出さない', () {
      expect(showVacationStatsDetails(VacationLoadState.loading), isFalse);
    });
    test('失敗中は内訳・消滅予定を出さない（D4）', () {
      expect(showVacationStatsDetails(VacationLoadState.failed), isFalse);
    });
    test('読み込めていれば出す', () {
      expect(showVacationStatsDetails(VacationLoadState.loaded), isTrue);
    });
  });

  test('統計カードの失敗の文言は ❌ で始まる', () {
    expect(vacationStatsLoadFailedText, startsWith('❌'));
  });
}
