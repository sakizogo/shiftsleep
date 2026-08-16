import 'package:shiftsleep/models/sleep_record.dart';

/// ========== Week 7 A 追加: 睡眠改善アドバイスエンジン ==========
/// 
/// 実データから改善ポイントを自動抽出し、ユーザーへの提案を生成
/// 
/// 責務:
/// - SJL/SRI/睡眠負債から改善ポイントを特定
/// - 具体的で実行可能なアドバイスを生成
/// - 無料版/有料版での内容区別
/// - シフトワーカーにストレスを与えない言い回しを採用
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
    // シフトワーカー向け: 体内時計の乱れは仕事の性質上避けられない
    // その中で「改善できることに焦点を当てる」という方針
    if (sjl >= 2.0) {
      advices.add(
        SleepAdvice(
          title: 'シフト勤務での体内時計ズレを最小化',
          description: 'SJL が 2時間以上あります。シフト勤務による体内時計の変動は避けられませんが、'
              'その中でも就寝・起床時刻を一定に保つことで、睡眠の質と疲労回復効果を高められます。'
              'あなたのシフトパターンに合わせた固定的な睡眠スケジュールを心がけてみてください。',
          category: 'sjl',
          priority: 1,
          actionTip: '現在のシフトパターンに合わせて、毎日同じ時刻に就寝・起床する目標を設定しましょう',
        ),
      );
    } else if (sjl >= 1.0) {
      advices.add(
        SleepAdvice(
          title: 'シフト変動での睡眠リズムを安定化',
          description: 'SJL が 1～2時間あります。シフト勤務の影響で平日と休日の睡眠時刻がずれていますが、'
              'この差を ±30分以内に抑えることで、睡眠の質を改善できます。'
              '可能な限り、休日でも平日と近い時刻に寝起きするリズムを作りましょう。',
          category: 'sjl',
          priority: 1,
          actionTip: '休日の起床時刻を平日の ±30分以内に設定してみてください',
        ),
      );
    } else {
      advices.add(
        SleepAdvice(
          title: '体内時計が安定した状態です',
          description: 'SJL が 1時間未満で、現在のシフトパターンの中でも体内時計が良く安定しています。'
              'この睡眠習慣をさらに続けることで、体調管理の安定性が高まります。',
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
          title: '睡眠時刻を安定させて体調を整える',
          description: 'SRI が 40未満で、毎日の睡眠時刻がバラバラです。'
              'シフト勤務でも、毎日 ±15分以内に睡眠時刻を統一することで、'
              '体調の安定性と日中のパフォーマンスが大きく向上します。',
          category: 'sri',
          priority: 1,
          actionTip: '毎日同じ時刻にアラームを設定し、一貫した睡眠スケジュールを作成してください',
          isPremiumOnly: false,
        ),
      );
    } else if (sri < 60) {
      advices.add(
        SleepAdvice(
          title: '睡眠時刻をさらに安定させる',
          description: 'SRI が 40～60で、睡眠時刻がやや不規則です。'
              '毎日 ±30分以内に睡眠時刻を固定することで、睡眠の深さと疲労回復が改善します。',
          category: 'sri',
          priority: 2,
          actionTip: '就寝時刻を毎日同じ時間に固定する実験を 2週間行ってみてください',
        ),
      );
    } else if (sri < 80) {
      advices.add(
        SleepAdvice(
          title: '睡眠時刻は安定しています',
          description: 'SRI が 60～80で、睡眠時刻が規則正しく保たれています。'
              'この習慣をさらに高めて SRI 85% 以上を目指すと、さらに睡眠の質が向上します。',
          category: 'sri',
          priority: 2,
          actionTip: null,
        ),
      );
    } else {
      advices.add(
        SleepAdvice(
          title: '睡眠リズムが完璧に安定しています',
          description: 'SRI が 80以上で、毎日の睡眠時刻が非常に安定しており、'
              '優れた睡眠習慣が確立されています。'
              'この素晴らしい生活パターンをそのまま維持してください。',
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
            title: '睡眠不足への対策が必要です',
            description: '10時間以上の睡眠不足が蓄積しています。'
                'このままでは心身の回復が間に合いません。'
                'シフト勤務の合間に昼寝を増やすなど、すぐに対策を取ることが重要です。',
            category: 'debt',
            priority: 1,
            actionTip: '週末に 2時間の追加睡眠を取るか、毎日 30分の昼寝を追加してみてください',
            isPremiumOnly: false,
          ),
        );
      } else if (debtHours >= 5) {
        advices.add(
          SleepAdvice(
            title: '睡眠時間を増やして回復を促す',
            description: '5～10時間の睡眠不足が蓄積しています。'
                '毎日の睡眠時間を 30分～1時間増やすことで、疲労回復が改善します。',
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
                '勤務の合間に 20～30分の短い昼寝を加えることで改善できます。',
            category: 'debt',
            priority: 2,
            actionTip: '勤務中に 20分の短い昼寝を取ってみてください',
          ),
        );
      }
    } else {
      advices.add(
        SleepAdvice(
          title: '十分な睡眠が取れています',
          description: '睡眠負債が解消され、十分な睡眠が取れています。'
              'あなたのシフトパターンと現在の睡眠習慣は良好なバランスが取れています。',
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
        title: 'ポリファシック睡眠が効果を発揮しています',
        description: '過去7日間で補助睡眠が ${supplementaryCount}日 記録されています。'
            '分割睡眠により、シフト勤務での睡眠効率が向上しています。'
            '現在の昼寝タイミングを最適化することで、さらに体調管理の質を高められます。',
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