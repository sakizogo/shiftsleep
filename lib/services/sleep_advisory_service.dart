import 'package:shiftsleep/models/sleep_record.dart';

/// ========== Week 7 A 追加: 睡眠改善アドバイスエンジン ==========
/// 
/// 実データから改善ポイントを自動抽出し、ユーザーへの提案を生成
/// 
/// 責務:
/// - SJL/SRI/睡眠負債から改善ポイントを特定
/// - 具体的で実行可能なアドバイスを生成
/// - 無料版/有料版での内容区別
class SleepAdvice {
  final String title;           // アドバイスのタイトル
  final String description;     // 詳細説明
  final String category;        // 'sjl' | 'sri' | 'debt'
  final int priority;           // 優先度 1～3（1が最高）
  final bool isPremiumOnly;     // 有料版のみ表示
  final String? actionTip;      // 実行可能なアクション

  SleepAdvice({
    required this.title,
    required this.description,
    required this.category,
    this.priority = 2,
    this.isPremiumOnly = false,
    this.actionTip,
  });
}

class SleepAdvisoryService {
  /// 実データから改善アドバイスを生成
  /// 
  /// Parameters:
  ///   - sjl: Social Jetlag (時間)
  ///   - sri: Sleep Regularity Index (%)
  ///   - sleepDebt: 睡眠負債 (Duration)
  ///   - last7DaysRecords: 過去7日の睡眠記録
  ///   - isPremiumUser: 有料ユーザーか（デフォルト: false）
  /// 
  /// Returns:
  ///   優先度順に並んだ SleepAdvice リスト
  static List<SleepAdvice> generateAdvice({
    required double sjl,
    required double sri,
    required Duration sleepDebt,
    required List<SleepRecord> last7DaysRecords,
    bool isPremiumUser = false,
  }) {
    final List<SleepAdvice> advices = [];

    // ========== SJL ベースのアドバイス ==========
    if (sjl >= 2.0) {
      advices.add(
        SleepAdvice(
          title: '体内時計が大きく乱れています',
          description: 'SJL が 2時間以上あるため、体内時計の同期ズレが大きくなっています。'
              '毎日の就寝・起床時刻を一定に保つことが最優先です。',
          category: 'sjl',
          priority: 1,
          actionTip: '毎日 23:00 に寝ることを 1週間継続してみてください',
        ),
      );
    } else if (sjl >= 1.0) {
      advices.add(
        SleepAdvice(
          title: '体内時計がやや乱れています',
          description: 'SJL が 1～2時間あるため、体内時計がやや乱れています。'
              '平日と休日の睡眠時刻の差を ±30分 以内に抑えることが効果的です。',
          category: 'sjl',
          priority: 1,
          actionTip: '休日の起床時刻を平日の ±30分以内に設定しましょう',
        ),
      );
    } else {
      advices.add(
        SleepAdvice(
          title: '体内時計は正常範囲です',
          description: 'SJL が 1時間未満で、体内時計の状態は良好です。'
              '現在の睡眠習慣を維持することが重要です。',
          category: 'sjl',
          priority: 3,
          actionTip: null,
        ),
      );
    }

    // ========== SRI ベースのアドバイス ==========
    if (sri < 40) {
      advices.add(
        SleepAdvice(
          title: '睡眠時刻が不規則です',
          description: 'SRI が 40未満で、毎日の睡眠時刻がバラバラです。'
              '寝る時間と起きる時間を毎日 ±15分以内に統一することが重要です。',
          category: 'sri',
          priority: 1,
          actionTip: '毎日同じ時刻にアラームを設定し、一貫した睡眠スケジュールを作成してください',
          isPremiumOnly: false,
        ),
      );
    } else if (sri < 60) {
      advices.add(
        SleepAdvice(
          title: '睡眠時刻がやや不規則です',
          description: 'SRI が 40～60で、睡眠時刻がやや不規則です。'
              '毎日 ±30分以内に睡眠時刻を固定することで改善できます。',
          category: 'sri',
          priority: 2,
          actionTip: '就寝時刻を毎日同じ時間に固定する実験を 2週間行ってみてください',
        ),
      );
    } else if (sri < 80) {
      advices.add(
        SleepAdvice(
          title: '睡眠時刻は規則正しいです',
          description: 'SRI が 60～80で、睡眠時刻が規則正しく保たれています。'
              'この習慣をさらに改善して SRI 85% 以上を目指しましょう。',
          category: 'sri',
          priority: 2,
          actionTip: null,
        ),
      );
    } else {
      advices.add(
        SleepAdvice(
          title: '睡眠時刻が非常に規則正しいです',
          description: 'SRI が 80以上で、毎日の睡眠時刻が非常に安定しています。'
              '優れた睡眠習慣が確立されています。',
          category: 'sri',
          priority: 3,
          actionTip: null,
        ),
      );
    }

    // ========== 睡眠負債 ベースのアドバイス ==========
    if (sleepDebt.isNegative) {
      final debtHours = sleepDebt.inHours.abs();
      
      if (debtHours >= 10) {
        advices.add(
          SleepAdvice(
            title: '睡眠不足が深刻です',
            description: '10時間以上の睡眠不足が蓄積しています。'
                '心身の健康に影響を与えます。週末に昼寝を増やすなど、すぐに対策が必要です。',
            category: 'debt',
            priority: 1,
            actionTip: '週末に 2時間の追加睡眠を取ってください',
            isPremiumOnly: false,
          ),
        );
      } else if (debtHours >= 5) {
        advices.add(
          SleepAdvice(
            title: '睡眠不足が蓄積しています',
            description: '5～10時間の睡眠不足が蓄積しています。'
                '毎日の睡眠時間を 30分～1時間 増やすことで改善できます。',
            category: 'debt',
            priority: 1,
            actionTip: '毎日の就寝時刻を 30分早めるか、起床時刻を 30分遅くしてみてください',
          ),
        );
      } else {
        advices.add(
          SleepAdvice(
            title: '軽度の睡眠不足があります',
            description: '5時間未満の軽度な睡眠不足があります。'
                '昼寝を 20～30分追加することで改善できます。',
            category: 'debt',
            priority: 2,
            actionTip: '昼間に 20分の短い昼寝を取ってみてください',
          ),
        );
      }
    } else {
      advices.add(
        SleepAdvice(
          title: '十分な睡眠が取れています',
          description: '睡眠負債が解消され、十分な睡眠が取れています。'
              '現在の睡眠習慣を継続することが重要です。',
          category: 'debt',
          priority: 3,
          actionTip: null,
        ),
      );
    }

    // ========== 分割睡眠ベースのアドバイス（有料版のみ）==========
    if (isPremiumUser && last7DaysRecords.length >= 3) {
      final advice = _generatePolyphasicAdvice(last7DaysRecords);
      if (advice != null) {
        advices.add(advice);
      }
    }

    // 優先度でソート
    advices.sort((a, b) => a.priority.compareTo(b.priority));

    return advices;
  }

  /// ========== 分割睡眠の活用アドバイスを生成（有料版機能）==========
  /// 
  /// メイン睡眠と補助睡眠のバランスから、ポリファシック睡眠の導入を提案
  static SleepAdvice? _generatePolyphasicAdvice(
    List<SleepRecord> last7DaysRecords,
  ) {
    if (last7DaysRecords.isEmpty) return null;

    // メイン睡眠と補助睡眠の日数を集計
    final primaryCount = last7DaysRecords
        .where((r) => r.sleepRole == SleepRole.primary)
        .length;
    final supplementaryCount = last7DaysRecords
        .where((r) => r.sleepRole == SleepRole.supplementary)
        .length;

    // 補助睡眠がある場合、ポリファシック睡眠の改善アドバイスを生成
    if (supplementaryCount >= 3) {
      return SleepAdvice(
        title: 'ポリファシック睡眠の導入効果が見られます',
        description: '過去7日間で補助睡眠が ${supplementaryCount}日 記録されています。'
            '分割睡眠により、シフト勤務での睡眠効率が向上しています。'
            '現在の昼寝タイミングを最適化することで、さらに効果を高められます。',
        category: 'debt',
        priority: 2,
        actionTip: '毎日 14:00～14:30 に 30分の昼寝を設定してみてください',
        isPremiumOnly: true,
      );
    }

    return null;
  }

  /// アドバイスの種類別に分類（無料版：1つ、有料版：3～5個）
  static List<SleepAdvice> filterAdviceByPlan(
    List<SleepAdvice> advices, {
    required bool isPremiumUser,
  }) {
    if (isPremiumUser) {
      // 有料版: 優先度1, 2 のアドバイスを表示（最大5個）
      return advices
          .where((a) => a.priority <= 2)
          .take(5)
          .toList();
    } else {
      // 無料版: 優先度1 のアドバイスのみ表示（最大1個）
      return advices
          .where((a) => a.priority == 1 && !a.isPremiumOnly)
          .take(1)
          .toList();
    }
  }

  /// アドバイスを日本語で人間らしい文体に変換（オプション）
  static String formatAdviceForDisplay(SleepAdvice advice) {
    return '''
【${advice.title}】

${advice.description}

${advice.actionTip != null ? '💡 実行ヒント: ${advice.actionTip}' : ''}
    '''.trim();
  }
}
// ====================================================================