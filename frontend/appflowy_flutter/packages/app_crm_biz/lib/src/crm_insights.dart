import 'crm_entity.dart';

/// CRM 派生洞察（**纯计算、无 IO**）。
///
/// 有些信息只有"跨实体"才看得出来，例如：
/// - 某个客户名下的收款单还欠多少钱（客户 → 合同/项目 → 收款）；
/// - 某个客户是否"有逾期"（自身的、或名下项目/合同/收款的关键日期逾期）；
/// - 一个实体多久没被跟进了（最近一条跟踪记录距今多少天）。
///
/// 这些都会同时出现在**列表卡片**与**详情页头卡**里，所以集中在这里算一次，
/// UI 只负责渲染。判定口径（阈值、终态）也放在这里，避免散落在各页面。
class CrmInsights {
  CrmInsights({
    required List<CrmEntity> entities,
    Map<String, CrmEvent> latestEvents = const {},
    DateTime? now,
  })  : _latestEvents = latestEvents,
        _today = dateOnly(now ?? DateTime.now()) {
    for (final entity in entities) {
      _byId[entity.id] = entity;
      _byType.putIfAbsent(entity.type, () => <CrmEntity>[]).add(entity);
    }
    _childrenOfCustomer = _buildChildrenIndex();
  }

  final Map<String, CrmEntity> _byId = {};
  final Map<String, List<CrmEntity>> _byType = {};
  final Map<String, CrmEvent> _latestEvents;
  final DateTime _today;
  late final Map<String, List<CrmEntity>> _childrenOfCustomer;

  /// 「久未跟进」阈值（天，按类型固定；暂不做设置项）。
  /// 线索最容易凉、合同周期最长，客户居中。
  static const Map<String, int> staleThresholdDays = {
    CrmEntityType.lead: 7,
    CrmEntityType.project: 14,
    CrmEntityType.customer: 21,
    CrmEntityType.contract: 30,
    CrmEntityType.receivable: 14,
  };

  /// 手动「⭐ 今天要跟进」标记：存在实体 `extra` 里的日期（`yyyy-MM-dd`）。
  static const String followUpKey = 'follow_up_at';

  /// 「推迟到某天」：`extra.snooze_until`（`yyyy-MM-dd`），该日之前不再出现在清单里。
  /// 用的是现成的扩展字段机制，**不改数据库结构**。
  static const String snoozeKey = 'snooze_until';

  /// 各类型的**终态阶段**：到了这里就不再提醒跟进。
  static const Map<String, List<String>> closedStages = {
    CrmEntityType.lead: ['已转项目', '已丢弃'],
    CrmEntityType.project: ['已成交', '已流失'],
    CrmEntityType.contract: ['已完成', '已终止'],
    CrmEntityType.receivable: <String>[],
  };

  // ------------------------------------------------------------ 基础访问

  CrmEntity? byId(String id) => _byId[id];

  List<CrmEntity> ofType(String type) => _byType[type] ?? const <CrmEntity>[];

  /// 全部实体（"今天该跟进"要跨类型扫）。
  List<CrmEntity> get all => _byId.values.toList(growable: false);

  /// 该实体的最近一条跟踪记录（没有则 null）。
  CrmEvent? latestEventOf(String entityId) => _latestEvents[entityId];

  /// 该客户名下的项目 / 合同 / 收款（跨两级关联一起算进来）。
  List<CrmEntity> childrenOfCustomer(String customerId) =>
      _childrenOfCustomer[customerId] ?? const <CrmEntity>[];

  /// 该客户未收金额合计（＝名下收款单「应收 − 已收」的正差额之和）。
  double unpaidOf(String customerId) {
    var total = 0.0;
    for (final child in childrenOfCustomer(customerId)) {
      if (child.type == CrmEntityType.receivable) {
        total += child.unpaidAmount;
      }
    }
    return total;
  }

  // ------------------------------------------------------------ 判定口径

  /// 是否终态（终态不再提醒跟进）。
  static bool isClosed(CrmEntity entity) =>
      (closedStages[entity.type] ?? const <String>[]).contains(entity.stage);

  /// 关键日期已过期多少天（未过期 / 无关键日期 / 终态 → null）。
  int? daysOverdue(CrmEntity entity) {
    final eventTime = entity.eventTime;
    if (eventTime == null || isClosed(entity)) {
      return null;
    }
    final days = _today.difference(dateOnly(eventTime)).inDays;
    return days > 0 ? days : null;
  }

  /// 逾期天数：自身关键日期逾期优先；客户再看名下项目/合同/收款，取最久的那条。
  /// 无逾期返回 null。
  int? overdueDaysOf(CrmEntity entity) {
    final own = daysOverdue(entity);
    if (own != null) {
      return own;
    }
    if (entity.type != CrmEntityType.customer) {
      return null;
    }
    int? worst;
    for (final child in childrenOfCustomer(entity.id)) {
      final days = daysOverdue(child);
      if (days != null && (worst == null || days > worst)) {
        worst = days;
      }
    }
    return worst;
  }

  /// 该实体（含客户名下子实体）是否存在逾期。
  bool hasOverdue(CrmEntity entity) => overdueDaysOf(entity) != null;

  /// 距离最近一次互动多少天（没有跟踪记录时回落到创建时间）。
  int daysSinceInteraction(CrmEntity entity) {
    final last = latestEventOf(entity.id)?.eventTime ?? entity.createdAt;
    final days = _today.difference(dateOnly(last)).inDays;
    return days > 0 ? days : 0;
  }

  /// 是否"久未跟进"（超过该类型的阈值，且不在终态）。
  bool isStale(CrmEntity entity) {
    if (isClosed(entity)) {
      return false;
    }
    final threshold = staleThresholdDays[entity.type];
    if (threshold == null) {
      return false;
    }
    return daysSinceInteraction(entity) > threshold;
  }

  /// 关键日期距离今天多少天（**含到期当天**：0 = 今天到期，>0 = 已逾期多少天）。
  /// 无关键日期 / 终态 → null。
  int? keyDateDueDays(CrmEntity entity) {
    final eventTime = entity.eventTime;
    if (eventTime == null || isClosed(entity)) {
      return null;
    }
    final days = _today.difference(dateOnly(eventTime)).inDays;
    return days >= 0 ? days : null;
  }

  /// 手动标记「今天要跟进」的日期（没标记 / 标记在未来 → null）。
  DateTime? manualFollowUpAt(CrmEntity entity) {
    final raw = entity.extra[followUpKey]?.trim() ?? '';
    if (raw.isEmpty) {
      return null;
    }
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      // 值不是日期（例如手写的 "1"）也当"今天要跟进"，避免静默丢失用户标记。
      return _today;
    }
    final day = dateOnly(parsed);
    return day.isAfter(_today) ? null : day;
  }

  /// 手动标记为"今天要跟进"？
  bool isManuallyFlagged(CrmEntity entity) => manualFollowUpAt(entity) != null;

  /// 是否被"推迟"到今天之后（`extra.snooze_until`）。
  bool isSnoozed(CrmEntity entity) {
    final raw = entity.extra[snoozeKey]?.trim() ?? '';
    if (raw.isEmpty) {
      return false;
    }
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      return false;
    }
    return dateOnly(parsed).isAfter(_today);
  }

  /// **「今天该跟进」清单**（设计定稿第 2 节的三条规则）。
  ///
  /// 每条实体最多出现一次，命中的规则取其中优先级最高的：
  /// 手动标记 > 关键日期到期/逾期 > 久未跟进。
  /// 排序：手动标记 → 逾期最久 → 久未跟进天数最多。
  List<CrmFollowUp> followUps() {
    final items = <CrmFollowUp>[];
    for (final entity in all) {
      if (isClosed(entity) || isSnoozed(entity)) {
        continue;
      }
      final manual = manualFollowUpAt(entity);
      if (manual != null) {
        final days = _today.difference(manual).inDays;
        items.add(
          CrmFollowUp(
            entity: entity,
            reason: CrmFollowUpReason.manual,
            detail: days > 0 ? '标记后已过 $days 天' : '手动标记',
            days: days,
          ),
        );
        continue;
      }
      final due = keyDateDueDays(entity);
      if (due != null) {
        items.add(
          CrmFollowUp(
            entity: entity,
            reason: CrmFollowUpReason.overdue,
            detail: due == 0 ? '关键日期今天到期' : '关键日期已逾期 $due 天',
            days: due,
          ),
        );
        continue;
      }
      if (isStale(entity)) {
        final days = daysSinceInteraction(entity);
        items.add(
          CrmFollowUp(
            entity: entity,
            reason: CrmFollowUpReason.stale,
            detail: '$days 天没联系了',
            days: days,
          ),
        );
      }
    }
    items.sort((a, b) {
      final byReason = a.reason.weight.compareTo(b.reason.weight);
      if (byReason != 0) {
        return byReason;
      }
      final byDays = b.days.compareTo(a.days);
      return byDays != 0 ? byDays : a.entity.title.compareTo(b.entity.title);
    });
    return items;
  }

  // ------------------------------------------------------------ 内部实现

  /// 客户 → 名下实体 的索引（项目 / 合同 / 收款，含"合同挂在项目上"的两级情况）。
  Map<String, List<CrmEntity>> _buildChildrenIndex() {
    final index = <String, List<CrmEntity>>{};
    for (final type in const [
      CrmEntityType.project,
      CrmEntityType.contract,
      CrmEntityType.receivable,
    ]) {
      for (final entity in ofType(type)) {
        final customerId = _customerIdOf(entity);
        if (customerId.isEmpty) {
          continue;
        }
        index.putIfAbsent(customerId, () => <CrmEntity>[]).add(entity);
      }
    }
    return index;
  }

  /// 推导一个实体"属于哪个客户"：自身外键 → 合同所属客户 → 合同所在项目的客户。
  String _customerIdOf(CrmEntity entity) {
    if (entity.customerId.isNotEmpty) {
      return entity.customerId;
    }
    final contract = _byId[entity.contractId];
    if (contract != null) {
      if (contract.customerId.isNotEmpty) {
        return contract.customerId;
      }
      final project = _byId[contract.projectId];
      if (project != null && project.customerId.isNotEmpty) {
        return project.customerId;
      }
    }
    return _byId[entity.projectId]?.customerId ?? '';
  }
}

/// 去掉时分秒（比较"天"时用；也避免夏令时/时区带来的半天误差）。
DateTime dateOnly(DateTime time) => DateTime(time.year, time.month, time.day);

/// 「今天该跟进」的命中原因（排序优先级＝枚举顺序）。
enum CrmFollowUpReason {
  /// 手动 ⭐ 标记（`extra.follow_up_at`）—— 用户说了算，排最前。
  manual(0, '已标记'),

  /// 关键日期到期/逾期。
  overdue(1, '临近'),

  /// 超过该类型的久未跟进阈值。
  stale(2, '久未跟进');

  const CrmFollowUpReason(this.weight, this.label);

  /// 排序权重（小者优先）。
  final int weight;

  /// 简短标签（横条上用）。
  final String label;
}

/// 「今天该跟进」的一条待办。
class CrmFollowUp {
  const CrmFollowUp({
    required this.entity,
    required this.reason,
    required this.detail,
    required this.days,
  });

  final CrmEntity entity;
  final CrmFollowUpReason reason;

  /// 一句话原因（「关键日期已逾期 3 天」「45 天没联系了」）。
  final String detail;

  /// 排序次键：越久越靠前（逾期天数 / 未跟进天数 / 标记后过了几天）。
  final int days;
}

/// 列表排序口径（设计定稿第 1 节）：
/// - **客户**：按最近互动时间倒序（从未互动过的回落到更新时间），顺序稳定、不跳动；
/// - **线索 / 项目 / 合同 / 收款**：按关键日期升序，逾期与临近的先浮上来，没设日期的排最后；
/// - **联系人**：按更新时间倒序（联系人本身没有关键日期）。
List<CrmEntity> sortCrmEntities(
  List<CrmEntity> entities, {
  required String type,
  required CrmInsights insights,
}) {
  final sorted = List<CrmEntity>.of(entities);
  if (type == CrmEntityType.customer) {
    sorted.sort((a, b) {
      final aAt = insights.latestEventOf(a.id)?.eventTime ?? a.updatedAt;
      final bAt = insights.latestEventOf(b.id)?.eventTime ?? b.updatedAt;
      final byInteraction = bAt.compareTo(aAt);
      return byInteraction != 0
          ? byInteraction
          : b.updatedAt.compareTo(a.updatedAt);
    });
    return sorted;
  }
  if (type == CrmEntityType.contact) {
    sorted.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return sorted;
  }
  sorted.sort((a, b) {
    final aDate = a.eventTime;
    final bDate = b.eventTime;
    if (aDate != null && bDate != null) {
      final byDate = aDate.compareTo(bDate);
      if (byDate != 0) {
        return byDate;
      }
    } else if (aDate != null) {
      return -1;
    } else if (bDate != null) {
      return 1;
    }
    return b.updatedAt.compareTo(a.updatedAt);
  });
  return sorted;
}
