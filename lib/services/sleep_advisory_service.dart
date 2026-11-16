import 'package:shiftsleep/models/sleep_record.dart';
import 'package:shiftsleep/services/sleep_record_kind.dart';  // N184：isNapSleepRecord
import 'package:shiftsleep/services/sleep_debt.dart';  // N198：SleepDebtSummary

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

/// N186：実行ヒント（actionTip）の出し方
enum ActionTipView {
  /// 出さない（actionTip がない／無料で 🔒 の案内が OFF）
  hidden,

  /// 🔒 の案内だけ出す（無料で 🔒 の案内が ON）
  locked,

  /// 中身を出す（プレミアム）
  shown,
}

/// N186：無料のときに実行ヒントの代わりに出す 🔒 の案内（詳細画面と同じ文言）
const String actionTipLockedLabel = '実行ヒント（プレミアム版で解放）';

/// N186：実行ヒントをどう出すか（ホームと改善アドバイスの詳細で共通）
ActionTipView actionTipView(
  SleepAdvice advice, {
  required bool isPremium,
  required bool promoVisible,
}) {
  if (advice.actionTip == null) return ActionTipView.hidden;
  if (isPremium) return ActionTipView.shown;
  return promoVisible ? ActionTipView.locked : ActionTipView.hidden;
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
    required double? sjl,  // N183：null なら SJL のアドバイスは出さない
    required double? sri,  // N197：null なら SRI のアドバイスは出さない
    required SleepDebtSummary? sleepDebt,  // N197：null なら睡眠負債のアドバイスは出さない（N198：1 日平均の不足で判定）
    required List<SleepRecord> last7DaysRecords,
    bool isPremiumUser = false,
  }) {
    final List<SleepAdvice> advices = [];

    // ========== SJL ベースのアドバイス ==========
    // シフトワーカー向け: 体内時計の乱れは仕事の性質上避けられない
    // その中で「改善できることに焦点を当てる」という方針
    if (sjl == null) {
      // N183：計算できないときは、priority 1 も 3 も出さない
    } else if (sjl >= 2.0) {
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
    if (sri == null) {
      // N197：計算できないときは出さない
    } else if (sri < 40) {
      // N196 A 2/2：日勤と夜勤が入れ替わる人に無理な言い方（毎日 ±15 分など）をしない・寝方のタイプを決めつけない
      advices.add(
        SleepAdvice(
          title: '睡眠の時間帯が日ごとに大きく変わっています',
          description: 'SRI が 40 未満で、24 時間前と比べて寝ている時間帯が大きく変わる日が多くなっています。'
              'シフトが切り替わる時期には避けにくいことですが、同じ勤務が続く日は寝る時間帯をなるべくそろえると、体が慣れやすくなります。',
          category: 'sri',
          priority: 1,
          actionTip: '同じ勤務が続く日は寝る時間帯をそろえ、勤務が切り替わる前後は、無理のない範囲で数時間ずつずらしてみてください',
          isPremiumOnly: false,
        ),
      );
    } else if (sri < 60) {
      advices.add(
        SleepAdvice(
          title: '睡眠の時間帯をもう少しそろえてみましょう',
          description: 'SRI が 40〜60 で、寝る時間帯が日ごとにやや変わっています。'
              '毎回すべてをそろえなくても、寝る時間帯の一部が日をまたいで重なるようにすると、リズムが崩れにくくなります。',
          category: 'sri',
          priority: 2,
          actionTip: '勤務が変わっても、毎回同じ数時間（例：4 時間ほど）は眠っている時間帯を作ってみてください',
        ),
      );
    } else if (sri < 80) {
      advices.add(
        SleepAdvice(
          title: '睡眠の時間帯はおおむねそろっています',
          description: 'SRI が 60〜80 で、寝る時間帯はおおむねそろっています。'
              'シフト勤務の中でこの状態を保てているのは良いことです。',
          category: 'sri',
          priority: 2,
          actionTip: null,
        ),
      );
    } else {
      advices.add(
        SleepAdvice(
          title: '睡眠の時間帯がよくそろっています',
          description: 'SRI が 80 以上で、毎日の寝る時間帯がよくそろっています。'
              '今のリズムを続けてみてください。',
          category: 'sri',
          priority: 3,
          actionTip: null,
        ),
      );
    }

    // ========== 睡眠負債 ベースのアドバイス ==========
    // N198：1 日平均の不足で判定（30 分以上で改善推奨、60 分以上で要注意）
    if (sleepDebt != null) {
      final shortage = formatSleepDuration(sleepDebt.shortage);
      switch (sleepDebt.level) {
        case SleepDebtLevel.notJudgeable:
          break;  // N197：計算できないときは出さない
        case SleepDebtLevel.alert:
          advices.add(
            SleepAdvice(
              title: '睡眠不足が続いています',
              description: '直近4週間、1日の睡眠が目安（7時間）より平均 $shortage 少なくなっています。'
                  '不足が続くと、眠気や疲れが抜けにくくなります。'
                  '勤務の前後や休みの日に、眠る時間を少しずつ増やしてみてください。'
                  '${sleepDebt.belowNationalGuide ? nationalGuideNote(sleepDebt.averageSleep) : ''}',
              category: 'debt',
              priority: 1,
              actionTip: '夜勤の前に仮眠を取る、勤務明けにまとまって眠れる時間を作るなど、勤務に合わせて眠る時間を確保してみてください',
            ),
          );
        case SleepDebtLevel.improve:
          advices.add(
            SleepAdvice(
              title: '睡眠時間を少し増やしてみましょう',
              description: '直近4週間、1日の睡眠が目安（7時間）より平均 $shortage 少なめです。'
                  '1日30分ほど眠る時間を増やすと、疲れが取れやすくなります。',
              category: 'debt',
              priority: 1,
              actionTip: '次の勤務までの時間に合わせて、寝る時刻を30分早めるか、20〜30分の仮眠を足してみてください',
            ),
          );
        case SleepDebtLevel.slight:
          advices.add(
            SleepAdvice(
              title: '睡眠時間はおおむね目安どおりです',
              description: '直近4週間、1日の睡眠が目安（7時間）より平均 $shortage 少なめですが、30分未満です。'
                  '今の睡眠時間を保っていきましょう。',
              category: 'debt',
              priority: 3,
            ),
          );
        case SleepDebtLevel.enough:
          advices.add(
            SleepAdvice(
              title: '十分な睡眠が取れています',
              description: '直近4週間の1日平均は目安（7時間）以上です。',
              category: 'debt',
              priority: 3,
            ),
          );
      }
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
  /// N184：昼寝・仮眠（5 時間未満。記録中は除く）を取った日が 3 日以上あれば出す
  static SleepAdvice? _generatePolyphasicAdvice(
    List<SleepRecord> last7DaysRecords,
  ) {
    if (last7DaysRecords.isEmpty) return null;

    // 昼寝・仮眠を取った日数（入眠の日付で数える。1 日に 2 回でも 1 日）
    final napDays = last7DaysRecords
        .where(isNapSleepRecord)
        .map((r) => DateTime(r.sleepStartTime.year, r.sleepStartTime.month, r.sleepStartTime.day))
        .toSet()
        .length;

    if (napDays >= 3) {
      return SleepAdvice(
        title: '仮眠を上手に取り入れています',
        description: '過去7日間のうち $napDays日、5時間未満の睡眠（昼寝・仮眠）を取っています。'
            'シフトの合間の短い仮眠は、眠気や疲れをやわらげるのに役立ちます。',
        category: 'debt',
        priority: 2,
        actionTip: '仮眠は 20〜30 分ほどにすると、起きたあとのだるさが出にくくなります',
        isPremiumOnly: true,
      );
    }

    return null;
  }

  /// lib/services/sleep_advisory_service.dart の filterAdviceByPlan メソッド修正版
  /// 
  /// 既存の filterAdviceByPlan メソッドを以下に置き換えてください

  static List<SleepAdvice> filterAdviceByPlan(
    List<SleepAdvice> advices, {
    required bool isPremiumUser,
  }) {
    if (isPremiumUser) {
      // 有料版: すべてのアドバイスを表示（最大5個）
      return advices.take(5).toList();
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