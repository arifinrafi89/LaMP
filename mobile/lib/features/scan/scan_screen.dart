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
import '../../core/state/shop_changes.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/ui/lamp_skeleton.dart';
import '../../widgets/ui/lamp_ui.dart';
import 'photo_prep.dart';
import 'photo_source.dart';
import 'scan_controller.dart';
import 'scan_models.dart';

/// Scan (plan 5.2, 5.5): one main action, take a photo. Then the photo, then
/// what was read, with every doubtful field waiting for the owner.
class ScanScreen extends StatelessWidget {
  const ScanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final pid = context.read<SessionController>().pharmacy!.id;
    return ChangeNotifierProvider(
      create: (context) => ScanController(
        context.read<ApiClient>(),
        pid,
        shrink: context.read<ShrinkPhoto>(),
        onSaved: context.read<ShopChanges>().saved,
      )..loadUsage(),
      child: const _ScanView(),
    );
  }
}

class _ScanView extends StatelessWidget {
  const _ScanView();

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final scan = context.watch<ScanController>();
    final Widget body = switch (scan.stage) {
      // Keyed, so one stage's scroll position never carries into the next.
      ScanStage.pick => const _Pick(key: ValueKey('stage-pick')),
      ScanStage.preparing => _Waiting(text: l.scanPreparing),
      ScanStage.preview || ScanStage.sending => const _Preview(key: ValueKey('stage-preview')),
      ScanStage.review || ScanStage.saving => const _Review(key: ValueKey('stage-review')),
      ScanStage.done => const _Done(key: ValueKey('stage-done')),
    };
    return Scaffold(appBar: AppBar(title: Text(l.tabScan)), body: body);
  }
}

/// The problem's words, and for a monthly limit the day it starts again.
class _ProblemText extends StatelessWidget {
  const _ProblemText(this.problem);

  final ApiProblem problem;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final c = context.lamp;
    final resets = problem.resetsOn;
    return Padding(
      padding: const EdgeInsets.only(top: Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(problemMessage(l, problem), style: LaMPType.sub.copyWith(color: c.dispute)),
          if (resets != null)
            Text(l.scanResetsOn(formatDay(resets, bangla: isBangla(context))),
                style: LaMPType.caption.copyWith(color: c.inkMuted)),
        ],
      ),
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.lamp;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Gap.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LampBusy(size: 28),
            const SizedBox(height: Gap.lg),
            Text(text, textAlign: TextAlign.center, style: LaMPType.body.copyWith(color: c.inkMuted)),
          ],
        ),
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/* 1. Pick                                                                    */
/* -------------------------------------------------------------------------- */

class _Pick extends StatelessWidget {
  const _Pick({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.lamp;
    final l = L10n.of(context);
    final scan = context.watch<ScanController>();
    final photos = context.read<PhotoSource>();
    final bn = isBangla(context);
    final left = scan.scansLeft;
    final problem = scan.problem;

    return ListView(
      padding: const EdgeInsets.all(Gap.lg),
      children: [
        SegmentedButton<ScanKind>(
          segments: [
            ButtonSegment(
                value: ScanKind.invoice,
                label: Text(l.scanKindBill, key: const ValueKey('scan-kind-bill'))),
            ButtonSegment(
                value: ScanKind.salesPage,
                label: Text(l.scanKindSales, key: const ValueKey('scan-kind-sales'))),
          ],
          selected: {scan.kind},
          showSelectedIcon: false,
          onSelectionChanged: (s) => scan.setKind(s.first),
        ),
        const SizedBox(height: Gap.lg),
        LampCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.receipt_long_outlined, size: IconSize.xl, color: c.inkMuted),
              const SizedBox(height: Gap.md),
              Text(l.scanHint, textAlign: TextAlign.center, style: LaMPType.body.copyWith(color: c.ink)),
              const SizedBox(height: Gap.lg),
              ElevatedButton.icon(
                key: const ValueKey('scan-camera'),
                onPressed: () => scan.take(photos.camera),
                style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(l.scanTakePhoto),
              ),
              const SizedBox(height: Gap.sm),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: Gap.sm,
                children: [
                  TextButton.icon(
                    key: const ValueKey('scan-gallery'),
                    onPressed: () => scan.take(photos.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text(l.scanFromGallery),
                  ),
                  TextButton.icon(
                    key: const ValueKey('scan-pdf'),
                    onPressed: () => scan.take(photos.pdf),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: Text(l.scanFromPdf),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (left != null) ...[
          const SizedBox(height: Gap.md),
          Text(l.scanScansLeft(formatCount(left, bangla: bn)),
              textAlign: TextAlign.center, style: LaMPType.caption.copyWith(color: c.inkMuted)),
        ],
        if (problem != null) _ProblemText(problem),
      ],
    );
  }
}

/* -------------------------------------------------------------------------- */
/* 2. Preview and send                                                        */
/* -------------------------------------------------------------------------- */

class _Preview extends StatelessWidget {
  const _Preview({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.lamp;
    final l = L10n.of(context);
    final scan = context.watch<ScanController>();
    final file = scan.file!;
    final sending = scan.stage == ScanStage.sending;
    final problem = scan.problem;

    return ListView(
      padding: const EdgeInsets.all(Gap.lg),
      children: [
        AnimatedOpacity(
          opacity: sending ? 0.5 : 1,
          duration: const Duration(milliseconds: 200),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(LaMPRadius.card),
            child: file.isPdf
                ? LampCard(
                    child: Row(
                      children: [
                        Icon(Icons.picture_as_pdf_outlined, size: IconSize.xl, color: c.inkMuted),
                        const SizedBox(width: Gap.md),
                        Expanded(child: Text(l.scanPdfReady, style: LaMPType.body.copyWith(color: c.ink))),
                      ],
                    ),
                  )
                // A fixed height, so the buttons don't jump when it decodes.
                : SizedBox(
                    height: 320,
                    child: Image.memory(
                      file.bytes,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      // The server reads what the phone can't show; say only
                      // that there is a photo, never a raw error.
                      errorBuilder: (context, _, _) => LampCard(
                        child: Icon(Icons.image_outlined, size: IconSize.xl, color: c.inkMuted),
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: Gap.lg),
        if (sending) ...[
          const Center(child: LampBusy(size: 28)),
          const SizedBox(height: Gap.md),
          Text(l.scanSending, textAlign: TextAlign.center, style: LaMPType.body.copyWith(color: c.inkMuted)),
        ] else ...[
          ElevatedButton.icon(
            key: const ValueKey('scan-send'),
            onPressed: scan.send,
            style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            icon: const Icon(Icons.send_outlined),
            label: Text(l.scanSend),
          ),
          const SizedBox(height: Gap.sm),
          OutlinedButton.icon(
            key: const ValueKey('scan-retake'),
            onPressed: scan.retake,
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            icon: const Icon(Icons.refresh),
            label: Text(l.scanRetake),
          ),
        ],
        if (problem != null) _ProblemText(problem),
      ],
    );
  }
}

/* -------------------------------------------------------------------------- */
/* 3. Review                                                                  */
/* -------------------------------------------------------------------------- */

String fieldLabel(L10n l, String name) => switch (name) {
      'supplier_name' => l.fieldSupplierName,
      'invoice_no' => l.fieldInvoiceNo,
      'invoice_date' => l.fieldInvoiceDate,
      'due_date' => l.fieldDueDate,
      'total' => l.fieldTotal,
      'product' => l.fieldProduct,
      'strength' => l.fieldStrength,
      'pack' => l.fieldPack,
      'batch_no' => l.fieldBatchNo,
      'expiry_date' => l.fieldExpiryDate,
      'qty' => l.fieldQty,
      'unit_cost' => l.fieldUnitCost,
      'line_total' => l.fieldLineTotal,
      'date' => l.fieldDate,
      'cash_sales' => l.fieldCashSales,
      'credit_sales' => l.fieldCreditSales,
      'dues_collected' => l.fieldDuesCollected,
      'expenses' => l.fieldExpenses,
      _ => name,
    };

/// A field's value as the owner reads it. Batch numbers, strengths and
/// names keep their own digits (plan 5.4); amounts, counts and dates follow
/// the language.
String fieldText(BuildContext context, ReviewField f) {
  final v = f.value;
  if (v == null || (v is String && v.isEmpty)) return L10n.of(context).scanEmpty;
  final bn = isBangla(context);
  return switch (f.type) {
    FieldType.money when v is num => formatMoney(v, bangla: bn),
    FieldType.integer when v is num => formatCount(v.toInt(), bangla: bn),
    FieldType.date when v is String && DateTime.tryParse(v) != null =>
      formatDay(DateTime.parse(v), bangla: bn),
    _ => '$v',
  };
}

class _Review extends StatelessWidget {
  const _Review({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.lamp;
    final l = L10n.of(context);
    final scan = context.watch<ScanController>();
    final r = scan.review!;
    final bn = isBangla(context);
    final open = r.waiting.length + r.failedChecks.where((k) => !k.acknowledged).length;
    final saving = scan.stage == ScanStage.saving;
    final problem = scan.problem;

    String groupTitle(int i, List<ReviewField> g) {
      final name = r.kind == ScanKind.invoice ? 'product' : 'date';
      final f = g.where((x) => x.name == name).firstOrNull;
      return f == null ? l.scanLine(formatCount(i + 1, bangla: bn)) : fieldText(context, f);
    }

    // Not a lazy list: a bill is a few dozen rows, and every one of them
    // must exist for "scroll to the next field to check" to work.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Gap.lg),
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LampCard(
          background: open == 0 ? c.verifiedSoft : c.pendingSoft,
          child: Row(
            children: [
              Icon(open == 0 ? Icons.check_circle_outline : Icons.visibility_outlined,
                  color: open == 0 ? c.verified : c.pending),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Text(
                  open == 0 ? l.scanAllChecked : l.scanToCheck(formatCount(open, bangla: bn)),
                  style: LaMPType.sub.copyWith(color: c.ink),
                ),
              ),
            ],
          ),
        ),
        if (r.suspiciousText.isNotEmpty) ...[
          const SizedBox(height: Gap.md),
          LampCard(
            background: c.disputeSoft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.gpp_maybe_outlined, color: c.dispute),
                const SizedBox(width: Gap.md),
                Expanded(child: Text(l.scanSuspicious, style: LaMPType.sub.copyWith(color: c.ink))),
              ],
            ),
          ),
        ],
        for (final check in r.failedChecks) ...[
          const SizedBox(height: Gap.md),
          _CheckCard(check: check),
        ],
        if (r.header.isNotEmpty) ...[
          const SizedBox(height: Gap.md),
          LampCard(
            padding: EdgeInsets.zero,
            child: Column(children: [for (final f in r.header) _FieldRow(field: f)]),
          ),
        ],
        for (var i = 0; i < r.items.length; i++) ...[
          const SizedBox(height: Gap.lg),
          LampSectionHeader(title: groupTitle(i, r.items[i])),
          LampCard(
            padding: EdgeInsets.zero,
            child: Column(children: [for (final f in r.items[i]) _FieldRow(field: f)]),
          ),
        ],
        const SizedBox(height: Gap.xl),
        ElevatedButton(
          key: const ValueKey('scan-save'),
          onPressed: r.canSave && !saving ? scan.save : null,
          style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: saving
              ? const LampBusy()
              : Text(r.kind == ScanKind.invoice ? l.scanSaveBill : l.scanSavePage),
        ),
        if (problem != null) _ProblemText(problem),
        const SizedBox(height: Gap.lg),
      ],
      ),
    );
  }
}

class _CheckCard extends StatelessWidget {
  const _CheckCard({required this.check});

  final ReviewCheck check;

  @override
  Widget build(BuildContext context) {
    final c = context.lamp;
    final l = L10n.of(context);
    final done = check.acknowledged;
    final bn = isBangla(context);
    return LampCard(
      background: done ? null : c.pendingSoft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.rule, color: done ? c.inkMuted : c.pending),
              const SizedBox(width: Gap.md),
              // The server's English; only the digits change (as on Today).
              Expanded(child: Text(check.name, style: LaMPType.sub.copyWith(color: c.ink))),
            ],
          ),
          const SizedBox(height: Gap.sm),
          Text(bn ? bnNumbers(check.detail) : check.detail,
              style: LaMPType.body.copyWith(color: c.inkMuted)),
          const SizedBox(height: Gap.sm),
          Align(
            alignment: Alignment.centerRight,
            child: done
                ? LampChip(label: l.scanCheckOk, tone: LampTone.neutral, icon: Icons.check)
                : OutlinedButton(
                    key: ValueKey('check-ok-${check.name}'),
                    onPressed: () => context.read<ScanController>().acknowledge(check),
                    child: Text(l.scanCheckOk),
                  ),
          ),
        ],
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.field});

  final ReviewField field;

  @override
  Widget build(BuildContext context) {
    final c = context.lamp;
    final l = L10n.of(context);
    final scan = context.read<ScanController>();
    final f = field;
    final mono = f.type == FieldType.money || f.type == FieldType.integer;
    final valueStyle = (mono ? LaMPType.monoBody : LaMPType.body).copyWith(color: c.ink);

    return Container(
      color: f.waiting ? c.pendingSoft : null,
      padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(fieldLabel(l, f.name), style: LaMPType.caption.copyWith(color: c.inkFaint)),
                    const SizedBox(height: 2),
                    Text(fieldText(context, f), style: valueStyle),
                  ],
                ),
              ),
              if (f.waiting)
                LampChip(label: l.scanCheckThis, tone: LampTone.pending)
              else
                IconButton(
                  key: ValueKey('field-change-${f.path}'),
                  tooltip: l.scanChange,
                  onPressed: () => editField(context, scan, f),
                  icon: Icon(Icons.edit_outlined, size: IconSize.sm, color: c.inkMuted),
                ),
            ],
          ),
          if (f.waiting)
            Wrap(
              alignment: WrapAlignment.end,
              spacing: Gap.sm,
              children: [
                TextButton(
                  key: ValueKey('field-change-${f.path}'),
                  onPressed: () => editField(context, scan, f),
                  child: Text(l.scanChange),
                ),
                OutlinedButton(
                  key: ValueKey('field-right-${f.path}'),
                  onPressed: () => scan.confirm(f.path),
                  child: Text(l.scanRight),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Opens the right editor for [f]: a calendar for a date, a box otherwise.
Future<void> editField(BuildContext context, ScanController scan, ReviewField f) async {
  if (f.type == FieldType.date) {
    final now = DateTime.now();
    final v = f.value;
    final first = DateTime(2000);
    final last = DateTime(2100);
    // A misread year (0202) must still open the calendar: start it in range.
    var initial = v is String ? DateTime.tryParse(v) ?? now : now;
    if (initial.isBefore(first) || initial.isAfter(last)) initial = now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (picked != null) scan.edit(f.path, apiDate(picked));
    return;
  }
  await LumaSheet.show<void>(
    context: context,
    title: fieldLabel(L10n.of(context), f.name),
    fitContent: true,
    builder: (_) => _EditSheet(scan: scan, field: f),
  );
}

class _EditSheet extends StatefulWidget {
  const _EditSheet({required this.scan, required this.field});

  final ScanController scan;
  final ReviewField field;

  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late final _text = TextEditingController(
    text: switch (widget.field.value) {
      null => '',
      final num n when n == n.roundToDouble() => '${n.toInt()}',
      final v => '$v',
    },
  );
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() {
    final l = L10n.of(context);
    if (widget.scan.edit(widget.field.path, _text.text)) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _error = switch (widget.field.type) {
          FieldType.money => l.fieldBadAmount,
          FieldType.integer => l.fieldBadWhole,
          _ => l.fieldBadText,
        });
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final numeric = widget.field.type == FieldType.money || widget.field.type == FieldType.integer;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('field-input'),
          controller: _text,
          autofocus: true,
          keyboardType: numeric
              ? TextInputType.numberWithOptions(decimal: widget.field.type == FieldType.money)
              : TextInputType.text,
          onSubmitted: (_) => _save(),
        ),
        LampErrorText(_error),
        const SizedBox(height: Gap.md),
        ElevatedButton(
          key: const ValueKey('field-save'),
          onPressed: _save,
          style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: Text(l.fieldSave),
        ),
      ],
    );
  }
}

/* -------------------------------------------------------------------------- */
/* 4. Done                                                                    */
/* -------------------------------------------------------------------------- */

class _Done extends StatelessWidget {
  const _Done({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.lamp;
    final l = L10n.of(context);
    final scan = context.read<ScanController>();
    final bill = scan.review?.kind != ScanKind.salesPage;
    return ListView(
      padding: const EdgeInsets.all(Gap.lg),
      children: [
        LampCard(
          background: c.verifiedSoft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.verified_outlined, size: IconSize.xl, color: c.verified),
              const SizedBox(height: Gap.md),
              Text(bill ? l.scanSavedBill : l.scanSavedPage,
                  textAlign: TextAlign.center, style: LaMPType.head.copyWith(color: c.ink)),
              const SizedBox(height: Gap.sm),
              Text(bill ? l.scanSavedBillDetail : l.scanSavedPageDetail,
                  textAlign: TextAlign.center, style: LaMPType.body.copyWith(color: c.inkMuted)),
            ],
          ),
        ),
        const SizedBox(height: Gap.lg),
        ElevatedButton(
          key: const ValueKey('scan-today'),
          onPressed: () => context.go('/today'),
          style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: Text(l.scanGoToday),
        ),
        const SizedBox(height: Gap.sm),
        OutlinedButton(
          key: const ValueKey('scan-another'),
          onPressed: () {
            scan.startOver();
            scan.loadUsage();
          },
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: Text(l.scanAnother),
        ),
      ],
    );
  }
}
