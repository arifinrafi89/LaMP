import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/api/problem.dart';
import '../../core/constants/palette.dart';
import '../../core/constants/typography.dart';
import '../../core/design/luma_sheet.dart';
import '../../core/l10n/digits.dart';
import '../../core/state/session_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/ui/lamp_failed.dart';
import '../../widgets/ui/lamp_skeleton.dart';
import '../../widgets/ui/lamp_ui.dart';
import 'stock_controller.dart';
import 'stock_models.dart';

/// Stock (plan 5.2): what expires in the next 60 days, and what can still go
/// back. One main action: open a batch that can go back. Free on every plan.
class StockScreen extends StatelessWidget {
  const StockScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final pid = context.read<SessionController>().pharmacy!.id;
    return ChangeNotifierProvider(
      create: (context) => StockController(context.read<ApiClient>(), pid)..load(),
      child: const _StockView(),
    );
  }
}

class _StockView extends StatelessWidget {
  const _StockView();

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final stock = context.watch<StockController>();
    final data = stock.expiry;
    final problem = stock.problem;

    final Widget body;
    if (data == null && problem != null) {
      body = LampFailed(problem: problem, onRetry: stock.load);
    } else if (data == null) {
      body = ListView(
        padding: const EdgeInsets.all(Gap.lg),
        children: const [LampSkeletonCard(lines: 2), SizedBox(height: Gap.md), LampSkeletonCard()],
      );
    } else {
      body = RefreshIndicator(onRefresh: stock.load, child: _Batches(data: data, problem: problem));
    }
    return Scaffold(appBar: AppBar(title: Text(l.navStock)), body: body);
  }
}

String _daysLeft(L10n l, int days, bool bn) =>
    days <= 0 ? l.stockExpired : l.stockDaysLeft(formatCount(days, bangla: bn));

class _Batches extends StatelessWidget {
  const _Batches({required this.data, required this.problem});

  final StockExpiry data;
  final ApiProblem? problem;

  @override
  Widget build(BuildContext context) {
    final c = context.lamp;
    final l = L10n.of(context);
    final bn = isBangla(context);
    final back = data.canGoBack;
    final notBack = data.cannotGoBack;
    final horizon = formatCount(data.horizonDays, bangla: bn);

    if (data.batches.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(Gap.lg),
        children: [
          LampEmpty(
            icon: Icons.inventory_2_outlined,
            title: l.stockNothingTitle(horizon),
            message: l.stockNothingBody,
            action: ElevatedButton.icon(
              key: const ValueKey('stock-scan'),
              onPressed: () => context.go('/scan'),
              icon: const Icon(Icons.document_scanner_outlined),
              label: Text(l.stockScanBill),
            ),
          ),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(Gap.lg),
      children: [
        if (problem != null)
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.md),
            child: Text(problemMessage(l, problem!), style: LaMPType.caption.copyWith(color: c.pending)),
          ),
        LampCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LampStat(
                label: l.stockAtRisk(horizon),
                value: formatMoney(data.atRiskValue, bangla: bn),
                caption: data.returnValue > 0
                    ? l.stockCanGoBackTotal(formatMoney(data.returnValue, bangla: bn))
                    : null,
              ),
              if (back.isNotEmpty) ...[
                const SizedBox(height: Gap.lg),
                ElevatedButton(
                  key: const ValueKey('stock-first-return'),
                  onPressed: () => showBatch(context, back.first),
                  style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  child: Text(l.stockFirstReturn),
                ),
              ],
            ],
          ),
        ),
        if (back.isNotEmpty) ...[
          const SizedBox(height: Gap.lg),
          LampSectionHeader(title: l.stockCanGoBackHeader),
          _BatchList(batches: back),
        ],
        if (notBack.isNotEmpty) ...[
          const SizedBox(height: Gap.lg),
          LampSectionHeader(title: l.stockCannotGoBackHeader),
          _BatchList(batches: notBack),
        ],
      ],
    );
  }
}

class _BatchList extends StatelessWidget {
  const _BatchList({required this.batches});

  final List<ExpiringBatch> batches;

  @override
  Widget build(BuildContext context) {
    final c = context.lamp;
    final l = L10n.of(context);
    final bn = isBangla(context);
    return LampCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (final b in batches)
            LampRow(
              key: ValueKey('batch-${b.batchNo}'),
              icon: b.returnEligible ? Icons.undo : Icons.hourglass_bottom,
              iconColor: b.daysLeft <= 14 ? c.pending : c.inkMuted,
              // Product names keep their own digits: "10 mg" (plan 5.4).
              title: b.product,
              subtitle: l.stockBatchLine(
                  b.batchNo, formatCount(b.qty, bangla: bn), formatMoney(b.costValue, bangla: bn)),
              trailing: Text(_daysLeft(l, b.daysLeft, bn),
                  style: LaMPType.caption.copyWith(color: b.daysLeft <= 14 ? c.pending : c.inkMuted)),
              onTap: () => showBatch(context, b),
            ),
        ],
      ),
    );
  }
}

/// One batch: where it stands, and whether its supplier still takes it back.
Future<void> showBatch(BuildContext context, ExpiringBatch b) {
  final c = context.lamp;
  final l = L10n.of(context);
  final bn = isBangla(context);
  return LumaSheet.show<void>(
    context: context,
    title: b.product,
    fitContent: true,
    builder: (_) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LampKeyValue(label: l.fieldBatchNo, value: b.batchNo, mono: true),
        LampKeyValue(label: l.stockExpiry, value: formatDay(b.expiryDate, bangla: bn)),
        LampKeyValue(
          label: l.stockLeft,
          value: _daysLeft(l, b.daysLeft, bn),
          valueColor: b.daysLeft <= 14 ? c.pending : null,
        ),
        LampKeyValue(label: l.fieldQty, value: formatCount(b.qty, bangla: bn), mono: true),
        LampKeyValue(label: l.stockCostValue, value: formatMoney(b.costValue, bangla: bn), mono: true),
        LampKeyValue(label: l.fieldSupplierName, value: b.supplier),
        const SizedBox(height: Gap.md),
        LampCard(
          background: b.returnEligible ? c.surfaceAlt : c.pendingSoft,
          child: Row(
            children: [
              Icon(b.returnEligible ? Icons.undo : Icons.block, color: b.returnEligible ? c.ink : c.pending),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Text(
                  b.returnEligible ? l.stockTakesBack(b.supplier) : l.stockWontTakeBack(b.supplier),
                  style: LaMPType.sub.copyWith(color: c.ink),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
