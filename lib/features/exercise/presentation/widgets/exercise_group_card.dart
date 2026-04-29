import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/providers/sheet_state_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/exercise_record.dart';
import '../providers/one_rm_coach_provider.dart';
import './exercise_progression_sheet.dart';
import './exercise_record_card.dart';
import './inline_set_input.dart';

/// 카드 하단의 인라인 입력 모드. `add` = 신규 세트, `edit` = 특정 세트 수정.
enum _InputMode { none, add, edit }

class ExerciseGroupCard extends ConsumerStatefulWidget {
  final String exerciseName;
  final String exerciseType;
  final List<ExerciseRecord> records;
  final bool editable;
  final VoidCallback? onRemoveFromRoutine;

  /// 비편집 모드(과거 날짜)에서만 사용되는 콜백. 편집 모드일 때는 인라인 입력으로 처리.
  final Function(ExerciseRecord)? onEdit;
  final Function(String)? onDelete;

  const ExerciseGroupCard({
    super.key,
    required this.exerciseName,
    required this.exerciseType,
    required this.records,
    this.editable = false,
    this.onRemoveFromRoutine,
    this.onEdit,
    this.onDelete,
  });

  @override
  ConsumerState<ExerciseGroupCard> createState() => _ExerciseGroupCardState();
}

class _ExerciseGroupCardState extends ConsumerState<ExerciseGroupCard> {
  _InputMode _mode = _InputMode.none;
  String? _editingUuid;

  double get _totalVolume => widget.records
      .where((r) => r.countsTowardVolume)
      .fold(0.0, (sum, r) => sum + r.volume);

  bool get _hasExcludedSets =>
      widget.records.any((r) => !r.countsTowardVolume);

  /// 인라인 편집 모드 전이. 전역 `activeInlineEditProvider` 에 현재 카드 키를
  /// 반영해 FAB 가 겹치지 않도록 한다. (카드 식별자는 exerciseName, 운동명 단위로 그룹화되므로 고유)
  void _setMode(_InputMode next, {String? editingUuid}) {
    setState(() {
      _mode = next;
      _editingUuid = next == _InputMode.edit ? editingUuid : null;
    });
    final notifier = ref.read(activeInlineEditProvider.notifier);
    final key = widget.exerciseName;
    final current = notifier.state;
    if (next == _InputMode.none) {
      if (current.contains(key)) {
        notifier.state = {...current}..remove(key);
      }
    } else {
      if (!current.contains(key)) {
        notifier.state = {...current, key};
      }
    }
  }

  @override
  void dispose() {
    // 카드가 언마운트될 때(스크롤 아웃/리빌드) 점유한 키 해제 누락 방지
    final notifier = ref.read(activeInlineEditProvider.notifier);
    final key = widget.exerciseName;
    if (notifier.state.contains(key)) {
      notifier.state = {...notifier.state}..remove(key);
    }
    super.dispose();
  }

  double? _calcDelta(({double? current, double? fourWeeksAgo})? entry) {
    if (entry == null) return null;
    if (entry.current == null || entry.fourWeeksAgo == null) return null;
    return entry.current! - entry.fourWeeksAgo!;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final typeColor =
        getExerciseTypeColor(widget.exerciseType, theme.brightness);

    // batch 결과에서 본 종목 entry 추출 (loading 시 null → 칩 자동 hidden)
    final batchAsync = ref.watch(batchExerciseE1RMProvider);
    final e1rmEntry = batchAsync.valueOrNull?[widget.exerciseName];
    final hasChip = e1rmEntry?.current != null;
    final hasX =
        widget.editable && widget.onRemoveFromRoutine != null;
    final showSecondRow = hasChip || hasX;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header — 탭 시 진행 추세 시트 오픈
          InkWell(
            onTap: () => showExerciseProgressionSheet(
              context,
              exerciseType: widget.exerciseType,
              exerciseName: widget.exerciseName,
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row 1 — icon + name/type + volume
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: typeColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(exerciseTypeIcon(widget.exerciseType),
                            size: 20, color: AppTheme.colorNavy),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.exerciseName,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              widget.exerciseType,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.outline,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${_totalVolume.toStringAsFixed(0)}kg',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (_hasExcludedSets)
                            Text(
                              '본세트 기준',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.outline,
                                fontSize: 10,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  // Row 2 — chip(좌) + x(우). 둘 다 조건부, 둘 다 없으면 행 자체 미렌더.
                  if (showSecondRow) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (hasChip)
                          _E1RMChip(
                            currentE1RM: e1rmEntry!.current!,
                            deltaKg: _calcDelta(e1rmEntry),
                            onTap: () => context.push(
                              '/exercise/coach/one-rm?exercise=${Uri.encodeComponent(widget.exerciseName)}',
                            ),
                          ),
                        const Spacer(),
                        if (hasX)
                          IconButton(
                            tooltip: '운동 제거',
                            icon: const Icon(Icons.close, size: 18),
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            padding: EdgeInsets.zero,
                            color: colorScheme.onSurfaceVariant,
                            // 부모 _removeExerciseCard 가 record 1+ 일 때 confirm.
                            onPressed: widget.onRemoveFromRoutine,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          // Sets List
          if (widget.records.isEmpty && widget.editable)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Text(
                '아직 기록 없음 · + 버튼으로 첫 세트를 추가하세요',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: widget.records.length,
              separatorBuilder: (context, index) =>
                  const Divider(height: 1, indent: 48),
              itemBuilder: (context, index) {
                final record = widget.records[index];
                final isEditingThis = _mode == _InputMode.edit &&
                    _editingUuid == record.uuid;
                if (isEditingThis) {
                  return InlineSetInput(
                    exerciseType: widget.exerciseType,
                    exerciseName: widget.exerciseName,
                    editing: record,
                    onClose: () => _setMode(_InputMode.none),
                  );
                }
                return _SetRow(
                  record: record,
                  editable: widget.editable,
                  onTap: () {
                    if (widget.editable) {
                      _setMode(_InputMode.edit, editingUuid: record.uuid);
                    } else if (widget.onEdit != null) {
                      widget.onEdit!(record);
                    }
                  },
                  onDelete: () {
                    if (widget.onDelete != null) widget.onDelete!(record.uuid);
                  },
                );
              },
            ),
          if (widget.editable) ...[
            const Divider(height: 1),
            if (_mode == _InputMode.add)
              InlineSetInput(
                exerciseType: widget.exerciseType,
                exerciseName: widget.exerciseName,
                onClose: () => _setMode(_InputMode.none),
              )
            else
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () => _setMode(_InputMode.add),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('세트 추가'),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _SetRow extends StatelessWidget {
  final ExerciseRecord record;
  final bool editable;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _SetRow({
    required this.record,
    required this.editable,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final isWork = record.setType == SetType.work;
    final row = InkWell(
      onTap: editable ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              child: isWork
                  ? Text(
                      '${record.currentSet}세트',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.outline,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  : _SetTypeBadge(setType: record.setType),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Row(
                children: [
                  _StatItem(
                    label: record.weight % 1 == 0
                        ? '${record.weight.toInt()}kg'
                        : '${record.weight}kg',
                  ),
                  const SizedBox(width: 8),
                  _StatItem(label: '${record.reps}회'),
                  const SizedBox(width: 8),
                  _StatItem(label: 'RPE ${record.rpe.toStringAsFixed(1)}'),
                ],
              ),
            ),
            Text(
              '${record.volume.toStringAsFixed(0)}kg',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: record.countsTowardVolume
                    ? null
                    : colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );

    if (!editable) return row;

    return Dismissible(
      key: ValueKey(record.uuid),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: colorScheme.errorContainer,
        child: Icon(Icons.delete_outline, color: colorScheme.onErrorContainer),
      ),
      onDismissed: (_) => onDelete(),
      child: row,
    );
  }
}

class _SetTypeBadge extends StatelessWidget {
  final SetType setType;
  const _SetTypeBadge({required this.setType});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (label, bg, fg, border) = switch (setType) {
      SetType.warmup => (
          '웜',
          Colors.transparent,
          cs.onSurfaceVariant,
          cs.outline,
        ),
      SetType.drop => (
          '드',
          AppTheme.colorCoral.withValues(alpha: 0.18),
          AppTheme.colorCoral,
          AppTheme.colorCoral,
        ),
      SetType.failure => (
          '실',
          AppTheme.colorCoral,
          Colors.white,
          AppTheme.colorCoral,
        ),
      SetType.work => ('본', Colors.transparent, cs.onSurface, cs.outline),
    };
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  const _StatItem({required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 11,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 헤더 Row 2 에 표시되는 e1RM 칩. 데이터가 곧 진입점.
/// 탭 시 1RM 코치 풀스크린(해당 종목 자동 선택) 진입.
class _E1RMChip extends StatelessWidget {
  final double currentE1RM;
  final double? deltaKg;
  final VoidCallback onTap;
  const _E1RMChip({
    required this.currentE1RM,
    required this.deltaKg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mint = isDark ? AppTheme.colorMintDark : AppTheme.colorMintDeep;
    final mintTint =
        isDark ? AppTheme.colorMintTintDark : AppTheme.colorMintTint;
    final coral = isDark ? AppTheme.colorCoralDark : AppTheme.colorCoralDeep;

    final showDelta = deltaKg != null && deltaKg!.abs() >= 0.5;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(100),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: mintTint,
            borderRadius: BorderRadius.circular(100),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bolt_outlined, size: 12, color: mint),
              const SizedBox(width: 4),
              Text(
                'e1RM ${currentE1RM.toStringAsFixed(0)}',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: mint,
                  letterSpacing: -0.2,
                ),
              ),
              if (showDelta) ...[
                const SizedBox(width: 6),
                Text(
                  '${deltaKg! >= 0 ? '▲' : '▼'} ${deltaKg!.abs().toStringAsFixed(0)}kg',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: deltaKg! >= 0 ? mint : coral,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
