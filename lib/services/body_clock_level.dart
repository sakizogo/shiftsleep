/// N213：ホームの「体内時計の状態」の段階（SJL だけで判定。SRI は見ない）
/// - 境目はちょうどの値を上の段階に入れる（2 以上・1 以上・1 未満）
enum BodyClockLevel { disrupted, slightlyDisrupted, normal, notJudgeable }

/// N213：SJL（時間）から段階を決める。null は計算できない
BodyClockLevel bodyClockLevel(double? sjl) {
  if (sjl == null) return BodyClockLevel.notJudgeable;
  if (sjl >= 2) return BodyClockLevel.disrupted;
  if (sjl >= 1) return BodyClockLevel.slightlyDisrupted;
  return BodyClockLevel.normal;
}

/// N213：段階の言葉（色だけに頼らず見出しにも出す）
String bodyClockLevelLabel(BodyClockLevel level) {
  switch (level) {
    case BodyClockLevel.disrupted:
      return '大きく乱れている';
    case BodyClockLevel.slightlyDisrupted:
      return 'やや乱れている';
    case BodyClockLevel.normal:
      return '正常範囲';
    case BodyClockLevel.notJudgeable:
      return '判定できません';
  }
}
