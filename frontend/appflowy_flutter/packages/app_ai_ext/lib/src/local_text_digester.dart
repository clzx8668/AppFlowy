import 'dart:math' as math;

import '../app_ai_ext.dart';

/// 本地抽取式摘要器（**完全离线、零网络、零依赖**）。
///
/// 作用：在没有配置任何大模型的情况下，也能给闪念/日记产出"摘要 + 标签"，
/// 让 AI 记忆库这条链路先跑通；后续接大模型时只需换一个 [TextDigester] 实现。
///
/// 做法（经典抽取式，够用且可解释）：
/// 1. 按中英文标点切句；
/// 2. 中文取 2-gram/3-gram、英文按词切分，统计词频（去停用词）；
/// 3. 用句子里高频词的占比给句子打分，取前 N 句、保持原文顺序；
/// 4. 标签取词频最高的若干词（中文优先 2-gram，避免单字碎片）。
class LocalTextDigester implements TextDigester {
  const LocalTextDigester({
    this.maxSummarySentences = 3,
    this.maxSummaryChars = 160,
    this.maxTags = 6,
  });

  final int maxSummarySentences;
  final int maxSummaryChars;
  final int maxTags;

  @override
  String get engine => 'local';

  @override
  Future<AiDigestResult> digest(String text, {String? title}) async {
    final normalized = _normalize(text);
    if (normalized.isEmpty) {
      return const AiDigestResult(summary: '');
    }

    final sentences = _splitSentences(normalized);
    final tokenCounts = _countTokens(normalized);
    final tags = _pickTags(tokenCounts, normalized);

    final summary = sentences.length <= maxSummarySentences
        ? _truncate(sentences.join(''), maxSummaryChars)
        : _topSentences(sentences, tokenCounts);

    return AiDigestResult(summary: summary, tags: tags, engine: engine);
  }

  String _normalize(String text) {
    return text
        .replaceAll('\r\n', '\n')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n{2,}'), '\n')
        .trim();
  }

  List<String> _splitSentences(String text) {
    final raw = text.split(RegExp(r'(?<=[。！？!?；;\n])'));
    return raw
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
  }

  Map<String, int> _countTokens(String text) {
    final counts = <String, int>{};
    void bump(String token) {
      counts[token] = (counts[token] ?? 0) + 1;
    }

    // 英文/数字：按词切分
    for (final word in RegExp(r'[A-Za-z][A-Za-z0-9_-]{1,}')
        .allMatches(text)
        .map((m) => m.group(0)!.toLowerCase())) {
      if (!_stopWords.contains(word)) {
        bump(word);
      }
    }

    // 中文：按连续汉字串取 2-gram / 3-gram
    for (final run in RegExp(r'[\u4e00-\u9fa5]+')
        .allMatches(text)
        .map((m) => m.group(0)!)) {
      for (var n = 2; n <= 4; n++) {
        if (run.length < n) {
          continue;
        }
        for (var i = 0; i + n <= run.length; i++) {
          final token = run.substring(i, i + n);
          if (!_stopWords.contains(token)) {
            bump(token);
          }
        }
      }
    }
    return counts;
  }

  List<String> _pickTags(Map<String, int> counts, String text) {
    // 评分：词频 × 长度（长词信息量大；中文 4-gram 往往才是完整词组）
    // 再加上"词边界"加分：同一批候选里，能对齐标点/数字边界的那个通常才是真正的词
    // （例如"不能超过"比同为 4-gram 的"度不能超"更可能成词）。
    double scoreOf(MapEntry<String, int> entry) {
      final isAscii = RegExp(r'^[a-z0-9_-]+$').hasMatch(entry.key);
      final weight = isAscii ? 2 : entry.key.length;
      return entry.value * weight + _boundaryScore(entry.key, text) * 0.5;
    }

    final candidates = counts.entries.where((e) => e.value >= 2).toList()
      ..sort((a, b) {
        final byScore = scoreOf(b).compareTo(scoreOf(a));
        if (byScore != 0) {
          return byScore;
        }
        return b.key.length.compareTo(a.key.length);
      });

    final tags = <String>[];
    for (final entry in candidates) {
      // 去重/合并：包含关系，或与已选标签有 ≥2 字的连续重叠（例如"客户现"/"户现场"），
      // 一律视为同一个词的碎片，只保留评分最高的那个；
      // 另外，短碎片（2 字）只要和长标签有 1 字重叠也算碎片（例如"不能超过"与"超过"）。
      final covered = tags.any((t) {
        final run = _longestCommonRun(t, entry.key);
        if (t.contains(entry.key) || entry.key.contains(t) || run >= 2) {
          return true;
        }
        return run == 1 && entry.key.length <= 2 && t.length >= 4;
      });
      if (covered) {
        continue;
      }
      tags.add(entry.key);
      if (tags.length >= maxTags) {
        break;
      }
    }
    return tags;
  }

  /// 词边界得分：该词出现在"非汉字/非字母"边界上的次数。
  int _boundaryScore(String token, String text) {
    var score = 0;
    var index = text.indexOf(token);
    while (index >= 0) {
      final before = index == 0 ? '' : text[index - 1];
      final afterIndex = index + token.length;
      final after = afterIndex >= text.length ? '' : text[afterIndex];
      if (!_isWordChar(before) || !_isWordChar(after)) {
        score++;
      }
      index = text.indexOf(token, index + 1);
    }
    return score;
  }

  /// 汉字/字母算"词内字符"；数字与标点、空白一样视为边界（中文里数字多是独立信息）。
  bool _isWordChar(String char) =>
      char.isNotEmpty && RegExp(r'[A-Za-z_\u4e00-\u9fa5]').hasMatch(char);

  /// 两个字符串的最长公共连续子串长度（中文重叠判断用）。
  int _longestCommonRun(String a, String b) {
    var best = 0;
    for (var i = 0; i < a.length; i++) {
      for (var j = 0; j < b.length; j++) {
        var k = 0;
        while (i + k < a.length && j + k < b.length && a[i + k] == b[j + k]) {
          k++;
        }
        if (k > best) {
          best = k;
        }
      }
    }
    return best;
  }

  String _topSentences(List<String> sentences, Map<String, int> counts) {
    final scored = <(int, double, String)>[];
    for (var i = 0; i < sentences.length; i++) {
      final sentence = sentences[i];
      final tokens = _countTokens(sentence);
      if (tokens.isEmpty) {
        scored.add((i, 0, sentence));
        continue;
      }
      var score = 0.0;
      tokens.forEach((token, count) {
        score += (counts[token] ?? 0) * count;
      });
      // 归一化：长句天然容易得高分，这里按长度做一次抑制
      score = score / math.max(8, sentence.length);
      scored.add((i, score, sentence));
    }

    scored.sort((a, b) {
      final byScore = b.$2.compareTo(a.$2);
      return byScore != 0 ? byScore : a.$1.compareTo(b.$1);
    });

    final picked = scored.take(maxSummarySentences).toList()
      ..sort((a, b) => a.$1.compareTo(b.$1));
    return _truncate(picked.map((e) => e.$3).join(''), maxSummaryChars);
  }

  String _truncate(String text, int limit) {
    final trimmed = text.trim();
    if (trimmed.length <= limit) {
      return trimmed;
    }
    return '${trimmed.substring(0, limit)}…';
  }
}

/// 轻量停用词（中英混合，够用即可，后续可外置成资源文件）。
const Set<String> _stopWords = {
  // 英文
  'the', 'and', 'for', 'are', 'but', 'not', 'you', 'this', 'that', 'with',
  'have', 'has', 'was', 'were', 'will', 'can', 'our', 'your', 'from', 'they',
  'them', 'his', 'her', 'its', 'about', 'into', 'than', 'then', 'when', 'what',
  'how', 'why', 'all', 'any', 'one', 'two', 'out', 'get', 'got', 'just',
  // 中文（2-gram / 3-gram 层面的高频虚词组合）
  '我们', '你们', '他们', '这个', '那个', '什么', '怎么', '可以', '已经',
  '因为', '所以', '但是', '如果', '就是', '还是', '这样', '那样',
  '没有', '不是', '一个', '一些', '这些', '那些', '自己', '现在', '时候',
  '今天', '明天', '昨天', '然后', '而且', '其实', '应该', '可能', '觉得',
  '知道', '看到', '进行', '需要', '非常', '比较', '有点', '真的',
  '一下', '一直', '不能', '不要', '为了', '由于', '关于', '通过', '以及',
};
