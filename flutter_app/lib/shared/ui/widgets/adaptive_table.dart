import 'package:flutter/material.dart';

import 'package:erp/shared/ui/theme/app_breakpoints.dart';
import 'package:erp/shared/ui/theme/app_colors.dart';
import 'package:erp/shared/ui/theme/app_spacing.dart';
import 'package:erp/shared/ui/theme/app_text_styles.dart';

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
/// Roomy panes get a classic header + rows table (horizontally
/// scrollable if the pane is narrower than [minTableWidth], so columns
/// never squeeze below a readable size). Below [cardsBelow] each record
/// becomes a card with a title, subtitle and a grid of labelled values,
/// which is legible where a seven-column table is not.
///
/// The default cuts over at [AppBreakpoints.expanded], so phones *and*
/// tablets get cards: a tablet can technically fit the table, but only
/// by scrolling sideways to reach the action buttons, which is worse
/// than reading the same record as a card.
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

  /// Pane width under which rows are rendered as cards rather than as a
  /// table. Raise it for a table that needs even more room to be worth
  /// showing; lower it to keep the table on smaller panes.
  final double cardsBelow;

  /// Tightens the card layout so more records fit on a phone screen.
  /// Worth it for a long feed the operator scans rather than reads, at
  /// the cost of a more crowded card.
  final bool dense;

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
    this.cardsBelow = AppBreakpoints.expanded,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < cardsBelow) return _buildCards(context);
        return _buildTable(context, constraints.maxWidth);
      },
    );
  }

  // --- Wide layout ------------------------------------------------------

  Widget _buildTable(BuildContext context, double available) {
    final needsHScroll = available < minTableWidth;
    final tableWidth = needsHScroll ? minTableWidth : available;

    Widget rowList(ScrollController? controller) => ListView.builder(
          primary: false,
          controller: controller,
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

    final Widget body = rows.isEmpty
        ? SizedBox(height: 200, child: empty ?? const SizedBox.shrink())
        : shrinkWrap
            ? rowList(null)
            : _BarredScroll(builder: (context, c) => rowList(c));

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
      final unscrolled = table;
      table = _BarredScroll(
        builder: (context, c) => SingleChildScrollView(
          controller: c,
          scrollDirection: Axis.horizontal,
          child: unscrolled,
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

  List<int> get _detailColumns => <int>[
        for (var i = 0; i < columns.length; i++)
          if (i != titleColumn &&
              i != subtitleColumn &&
              i != actionsColumn &&
              columns[i].inCompactDetails)
            i,
      ];

  Widget _card(int i) => _RecordCard(
        columns: columns,
        row: rows[i],
        titleColumn: titleColumn,
        subtitleColumn: subtitleColumn,
        actionsColumn: actionsColumn,
        detailColumns: _detailColumns,
        dense: dense,
      );

  Widget _wideRow(int i) => _WideRow(
        columns: columns,
        row: rows[i],
        alternate: i.isOdd,
        height: rowHeight,
      );

  /// Slivers rendering exactly the same content, for a page that scrolls
  /// as one piece.
  ///
  /// This is the form to use when the table sits under other content
  /// (KPI tiles, filters): [shrinkWrap] would also make it fit, but it
  /// builds every row up front, so a 660-row report stutters. Slivers
  /// keep the single scroll *and* the lazy row building.
  List<Widget> _slivers(double width) {
    if (rows.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: SizedBox(height: 220, child: empty ?? const SizedBox.shrink()),
        ),
      ];
    }

    if (width < cardsBelow) {
      return [
        SliverList.separated(
          itemCount: rows.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (context, i) => _card(i),
        ),
      ];
    }

    return [
      SliverToBoxAdapter(
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.lg),
          ),
          child: _HeaderRow(columns: columns),
        ),
      ),
      SliverFixedExtentList.builder(
        itemExtent: rowHeight,
        itemCount: rows.length,
        itemBuilder: (context, i) => _wideRow(i),
      ),
    ];
  }

  Widget _buildCards(BuildContext context) {
    if (rows.isEmpty) return empty ?? const SizedBox.shrink();

    final detailColumns = _detailColumns;

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
        dense: dense,
      ),
    );
  }
}

/// Sliver form of [AdaptiveTable], for pages built as a
/// [CustomScrollView].
///
/// Prefer this over `AdaptiveTable(shrinkWrap: true)` whenever the row
/// count can grow: shrink-wrapping forces every row to be built before
/// the first frame, which is what made the Rapports and Transactions
/// pages stutter with a real catalogue behind them.
class SliverAdaptiveTable extends StatelessWidget {
  final AdaptiveTable table;

  const SliverAdaptiveTable({super.key, required this.table});

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) => SliverMainAxisGroup(
        slivers: table._slivers(constraints.crossAxisExtent),
      ),
    );
  }
}

/// Pairs a [Scrollbar] with the scroll view it controls.
///
/// A `Scrollbar` given no controller falls back to the *primary* one,
/// which a `primary: false` list never uses. The thumb still paints
/// itself from scroll notifications, so the bug is invisible until you
/// try to grab it — and on a 655-product catalogue an ungrabbable thumb
/// means the wheel is the only way down. Owning the controller here
/// keeps both on the same [ScrollPosition].
class _BarredScroll extends StatefulWidget {
  final Widget Function(BuildContext context, ScrollController controller)
      builder;

  const _BarredScroll({required this.builder});

  @override
  State<_BarredScroll> createState() => _BarredScrollState();
}

class _BarredScrollState extends State<_BarredScroll> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Visibility and interactivity are left to `scrollbarTheme`, which
    // already keeps the thumb pinned on desktop and fades it on touch.
    return Scrollbar(
      controller: _controller,
      // MaterialScrollBehavior fits every desktop scroll view with a
      // scrollbar of its own. Left on, it paints a second thumb in the
      // same track as this one — and since ours draws over it, the
      // pointer meets the top thumb while the working one sits beneath.
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: widget.builder(context, _controller),
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
  final bool dense;

  const _RecordCard({
    required this.columns,
    required this.row,
    required this.titleColumn,
    required this.subtitleColumn,
    required this.actionsColumn,
    required this.detailColumns,
    this.dense = false,
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
    final pad = dense ? AppSpacing.sm : AppSpacing.md;

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
                padding: EdgeInsets.fromLTRB(pad, pad, AppSpacing.sm, pad),
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
                  padding: EdgeInsets.all(pad),
                  child: _DetailGrid(
                    dense: dense,
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
  final bool dense;

  const _DetailGrid({required this.entries, this.dense = false});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = dense ? AppSpacing.sm : AppSpacing.md;
        final columns = constraints.maxWidth >= 420 ? 3 : 2;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: dense ? AppSpacing.sm : AppSpacing.md,
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
