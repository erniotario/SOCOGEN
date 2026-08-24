import 'package:flutter/material.dart';

import '../theme/app_breakpoints.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

/// One column of an [AdaptiveTable].
///
/// Widths are relative weights rather than pixels, so a table always
/// fills the space it is given without overflowing. [align] is applied
/// by the table itself, which means the same cell widget can be reused
/// in the card layout without fighting a baked-in `textAlign`.
class AppColumn {
  final String label;
  final int flex;
  final Alignment align;

  /// Whether this column appears in the detail grid of the compact card
  /// layout. Action columns opt out — they get their own slot.
  final bool inCompactDetails;

  const AppColumn(
    this.label, {
    this.flex = 10,
    this.align = Alignment.centerLeft,
  }) : inCompactDetails = true;

  /// Right-aligned column, for quantities.
  const AppColumn.number(this.label, {this.flex = 9})
      : align = Alignment.centerRight,
        inCompactDetails = true;

  /// Trailing column holding row actions (edit / delete / …).
  const AppColumn.actions({this.flex = 8})
      : label = 'ACTIONS',
        align = Alignment.centerRight,
        inCompactDetails = false;
}

/// One row of an [AdaptiveTable]. [cells] must be the same length as the
/// table's columns.
class AppRow {
  final List<Widget> cells;
  final VoidCallback? onTap;

  /// Optional colored stripe down the leading edge, used to encode a
  /// row's kind at a glance (entry vs output, stock status, …).
  final Color? accent;

  /// Marks the row as the current selection (used where picking a row
  /// drives a detail panel).
  final bool selected;

  const AppRow({
    required this.cells,
    this.onTap,
    this.accent,
    this.selected = false,
  });
}

/// Convenience builders for the cell widgets an [AdaptiveTable] expects.
/// Cells are plain, alignment-agnostic widgets — the table positions
/// them according to the column spec.
class Cells {
  Cells._();

  static Widget text(String value, {TextStyle? style, int maxLines = 1}) =>
      Text(
        value,
        style: style ?? AppTextStyles.tableCell,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      );

  static Widget muted(String value) => Text(
        value,
        style: AppTextStyles.bodyMuted,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );

  /// A product reference or other key, tinted so it reads as an id.
  static Widget identifier(String value) => Text(
        value,
        style: AppTextStyles.identifier,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );

  /// A quantity, rendered with tabular figures so columns of numbers
  /// line up on the decimal.
  static Widget number(
    Object value, {
    Color? color,
    bool strong = false,
    double? size,
  }) =>
      Text(
        '$value',
        style: (strong ? AppTextStyles.numericStrong : AppTextStyles.numeric)
            .copyWith(color: color, fontSize: size),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );

  /// Placeholder for an empty value — never leave a cell blank, an
  /// explicit dash reads as "no value" rather than "not loaded".
  static Widget get blank => const Text(
        '—',
        style: TextStyle(fontSize: 13, color: AppColors.textMuted),
      );
}

/// A data table that reshapes itself to the space it is given.
///
/// Wide layouts get a classic header + rows table (horizontally
/// scrollable if the pane is narrower than [minTableWidth], so columns
/// never squeeze below a readable size). Below [AppBreakpoints.medium]
/// — phones in portrait — each record becomes a card with a title,
/// subtitle and a two-column grid of labelled values, which is legible
/// where a seven-column table is not.
class AdaptiveTable extends StatelessWidget {
  final List<AppColumn> columns;
  final List<AppRow> rows;

  /// Shown in place of the rows when [rows] is empty.
  final Widget? empty;

  /// Column used as the card headline in the compact layout.
  final int titleColumn;

  /// Column used as the card subtitle; pass null to omit.
  final int? subtitleColumn;

  /// Column holding row actions, pinned to the card header on compact.
  final int? actionsColumn;

  final double rowHeight;

  /// Below this pane width the table falls back to horizontal scrolling
  /// rather than shrinking columns further.
  final double minTableWidth;

  /// Set when the table is placed inside an outer scroll view: it then
  /// sizes itself to its rows instead of filling (and scrolling within)
  /// the space it is given.
  final bool shrinkWrap;

  const AdaptiveTable({
    super.key,
    required this.columns,
    required this.rows,
    this.empty,
    this.titleColumn = 0,
    this.subtitleColumn = 1,
    this.actionsColumn,
    this.rowHeight = 44,
    this.minTableWidth = 720,
    this.shrinkWrap = false,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = AppBreakpoints.of(constraints.maxWidth);
        if (size.isCompact) return _buildCards(context);
        return _buildTable(context, constraints.maxWidth);
      },
    );
  }

  // --- Wide layout ------------------------------------------------------

  Widget _buildTable(BuildContext context, double available) {
    final needsHScroll = available < minTableWidth;
    final tableWidth = needsHScroll ? minTableWidth : available;

    Widget rowList = ListView.builder(
      primary: false,
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      itemCount: rows.length,
      itemExtent: rowHeight,
      itemBuilder: (context, i) => _WideRow(
        columns: columns,
        row: rows[i],
        alternate: i.isOdd,
        height: rowHeight,
      ),
    );
    if (!shrinkWrap) rowList = Scrollbar(child: rowList);

    final body = rows.isEmpty
        ? SizedBox(height: 200, child: empty ?? const SizedBox.shrink())
        : rowList;

    Widget table = SizedBox(
      width: tableWidth,
      child: Column(
        mainAxisSize: shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
        children: [
          _HeaderRow(columns: columns),
          if (shrinkWrap) body else Expanded(child: body),
        ],
      ),
    );

    if (needsHScroll) {
      table = Scrollbar(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: table,
        ),
      );
    }

    return Container(
      decoration: appSurfaceDecoration(
        color: AppColors.surface,
        radius: AppRadius.lg,
      ),
      clipBehavior: Clip.antiAlias,
      child: table,
    );
  }

  // --- Compact layout ---------------------------------------------------

  Widget _buildCards(BuildContext context) {
    if (rows.isEmpty) return empty ?? const SizedBox.shrink();

    final detailColumns = <int>[
      for (var i = 0; i < columns.length; i++)
        if (i != titleColumn &&
            i != subtitleColumn &&
            i != actionsColumn &&
            columns[i].inCompactDetails)
          i,
    ];

    return ListView.separated(
      primary: false,
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, i) => _RecordCard(
        columns: columns,
        row: rows[i],
        titleColumn: titleColumn,
        subtitleColumn: subtitleColumn,
        actionsColumn: actionsColumn,
        detailColumns: detailColumns,
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  final List<AppColumn> columns;

  const _HeaderRow({required this.columns});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: const BoxDecoration(
        color: AppColors.elevated,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          for (final column in columns)
            Expanded(
              flex: column.flex,
              child: Align(
                alignment: column.align,
                child: Text(
                  column.label,
                  style: AppTextStyles.tableHeader,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _WideRow extends StatefulWidget {
  final List<AppColumn> columns;
  final AppRow row;
  final bool alternate;
  final double height;

  const _WideRow({
    required this.columns,
    required this.row,
    required this.alternate,
    required this.height,
  });

  @override
  State<_WideRow> createState() => _WideRowState();
}

class _WideRowState extends State<_WideRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.row.accent;
    final base = widget.row.selected
        ? AppColors.selected
        : (widget.alternate ? AppColors.bg : AppColors.surface);

    final content = AnimatedContainer(
      duration: AppDurations.instant,
      curve: AppCurves.standard,
      height: widget.height,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: _hovering && !widget.row.selected
            ? AppColors.surfaceHover
            : base,
        border: Border(
          bottom: const BorderSide(color: AppColors.border),
          left: BorderSide(
            color: accent ?? Colors.transparent,
            width: accent == null ? 0 : 3,
          ),
        ),
      ),
      child: Row(
        children: [
          for (var i = 0; i < widget.columns.length; i++)
            Expanded(
              flex: widget.columns[i].flex,
              child: Align(
                alignment: widget.columns[i].align,
                child: i < widget.row.cells.length
                    ? widget.row.cells[i]
                    : const SizedBox.shrink(),
              ),
            ),
        ],
      ),
    );

    return MouseRegion(
      cursor: widget.row.onTap == null
          ? MouseCursor.defer
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.row.onTap,
        child: content,
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  final List<AppColumn> columns;
  final AppRow row;
  final int titleColumn;
  final int? subtitleColumn;
  final int? actionsColumn;
  final List<int> detailColumns;

  const _RecordCard({
    required this.columns,
    required this.row,
    required this.titleColumn,
    required this.subtitleColumn,
    required this.actionsColumn,
    required this.detailColumns,
  });

  Widget? _cell(int? index) {
    if (index == null || index >= row.cells.length) return null;
    return row.cells[index];
  }

  @override
  Widget build(BuildContext context) {
    final accent = row.accent;
    final title = _cell(titleColumn);
    final subtitle = _cell(subtitleColumn);
    final actions = _cell(actionsColumn);

    return Material(
      color: row.selected ? AppColors.selected : AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        onTap: row.onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: row.selected ? AppColors.accent : AppColors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (accent != null) ...[
                      Container(
                        width: 3,
                        height: 30,
                        margin: const EdgeInsets.only(right: AppSpacing.md),
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                        ),
                      ),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (title != null)
                            DefaultTextStyle.merge(
                              style: const TextStyle(fontSize: 15),
                              child: title,
                            ),
                          if (subtitle != null) ...[
                            const SizedBox(height: AppSpacing.xxs),
                            subtitle,
                          ],
                        ],
                      ),
                    ),
                    if (actions != null) ...[
                      const SizedBox(width: AppSpacing.sm),
                      actions,
                    ],
                  ],
                ),
              ),
              if (detailColumns.isNotEmpty) ...[
                const Divider(color: AppColors.border, height: 1),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: _DetailGrid(
                    entries: [
                      for (final i in detailColumns)
                        (label: columns[i].label, value: row.cells[i]),
                    ],
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

/// Two-column grid of labelled values shown inside a record card.
class _DetailGrid extends StatelessWidget {
  final List<({String label, Widget value})> entries;

  const _DetailGrid({required this.entries});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = AppSpacing.md;
        final columns = constraints.maxWidth >= 420 ? 3 : 2;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: AppSpacing.md,
          children: [
            for (final entry in entries)
              SizedBox(
                width: width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.label,
                      style: AppTextStyles.captionMuted,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: entry.value,
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
