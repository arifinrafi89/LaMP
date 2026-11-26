import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/api/problem.dart';
import '../../core/constants/palette.dart';
import '../../core/constants/typography.dart';
import '../../core/design/luma_press.dart';
import '../../core/design/luma_sheet.dart';
import '../../core/design/luma_toast.dart';
import '../../core/l10n/digits.dart';
import '../../core/state/session_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/ui/lamp_ui.dart';
import 'setup_controller.dart';
import 'setup_models.dart';

/// Setup, the first day (plan 5.2): name the shop, the main suppliers, the
/// cash in the drawer, rent and salaries, then stock. Every step after the
/// first can be skipped; Today lists what is still missing.
class SetupScreen extends StatelessWidget {
  const SetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) =>
          SetupController(context.read<ApiClient>(), context.read<SessionController>())..init(),
      child: const _SetupView(),
    );
  }
}

bool _bangla(BuildContext context) => Localizations.localeOf(context).languageCode == 'bn';

String _num(BuildContext context, int n) => _bangla(context) ? bnDigits('$n') : '$n';

class _SetupView extends StatelessWidget {
  const _SetupView();

  @override
  Widget build(BuildContext context) {
    final c = context.lamp;
    final l = L10n.of(context);
    final setup = context.watch<SetupController>();
    final step = setup.step;
    final total = SetupStep.values.length;

    return PopScope(
      canPop: step == SetupStep.shop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setup.back();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.navSetup),
          leading: step == SetupStep.shop
              ? null
              : IconButton(
                  key: const ValueKey('setup-back'),
                  tooltip: l.back,
                  icon: const Icon(Icons.arrow_back),
                  onPressed: setup.busy ? null : setup.back,
                ),
          automaticallyImplyLeading: false,
          actions: [
            if (step != SetupStep.shop)
              TextButton(
                key: const ValueKey('setup-skip'),
                onPressed: setup.busy ? null : setup.skip,
                child: Text(l.setupSkip),
              ),
          ],
        ),
        body: !setup.ready
            ? const Center(child: CircularProgressIndicator())
            : SafeArea(
                top: false,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                l.setupStepOf(_num(context, step.index + 1), _num(context, total)),
                                style: LaMPType.caption.copyWith(color: c.inkFaint),
                              ),
                              const SizedBox(height: Gap.sm),
                              LampProgress(value: (step.index + 1) / total),
                            ],
                          ),
                        ),
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: KeyedSubtree(
                              key: ValueKey(step),
                              child: switch (step) {
                                SetupStep.shop => const _ShopStep(),
                                SetupStep.suppliers => const _SuppliersStep(),
                                SetupStep.cash => const _CashStep(),
                                SetupStep.expenses => const _ExpensesStep(),
                                SetupStep.stock => const _StockStep(),
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

/// The frame every step shares: a heading, a line under it, the step's own
/// fields, then the error (if any) and one main button.
class _StepFrame extends StatelessWidget {
  const _StepFrame({
    required this.title,
    required this.subtitle,
    required this.children,
    required this.action,
    this.error,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;
  final Widget action;

  /// A local check that failed; the server's problem is shown otherwise.
  final String? error;

  @override
  Widget build(BuildContext context) {
    final c = context.lamp;
    final l = L10n.of(context);
    final problem = context.watch<SetupController>().problem;
    final message = error ?? (problem == null ? null : problemMessage(l, problem));
    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.xl, Gap.lg, Gap.xl),
      children: [
        Text(title, style: LaMPType.title.copyWith(color: c.ink)),
        const SizedBox(height: Gap.xs),
        Text(subtitle, style: LaMPType.body.copyWith(color: c.inkMuted)),
        const SizedBox(height: Gap.xl),
        ...children,
        if (message != null)
          Padding(
            padding: const EdgeInsets.only(top: Gap.md),
            child: Text(message,
                key: const ValueKey('setup-error'),
                style: LaMPType.body.copyWith(color: c.dispute)),
          ),
        const SizedBox(height: Gap.xl),
        action,
      ],
    );
  }
}

class _MainButton extends StatelessWidget {
  const _MainButton({required this.label, required this.onPressed, this.keyName = 'setup-next'});

  final String label;
  final VoidCallback? onPressed;
  final String keyName;

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<SetupController>().busy;
    return ElevatedButton(
      key: ValueKey(keyName),
      onPressed: busy ? null : onPressed,
      style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      child: busy
          ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : Text(label),
    );
  }
}

Widget _label(BuildContext context, String text) => Padding(
      padding: const EdgeInsets.only(bottom: Gap.sm, top: Gap.md),
      child: Text(text, style: LaMPType.meta.copyWith(color: context.lamp.inkMuted)),
    );

const _amountKeyboard = TextInputType.numberWithOptions(decimal: true);

/* -------------------------------------------------------------------------- */
/* 1. The shop                                                                */
/* -------------------------------------------------------------------------- */

class _ShopStep extends StatefulWidget {
  const _ShopStep();

  @override
  State<_ShopStep> createState() => _ShopStepState();
}

class _ShopStepState extends State<_ShopStep> {
  late final _name = TextEditingController(text: context.read<SetupController>().pharmacy?.name);
  final _city = TextEditingController();
  final _area = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    _area.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = L10n.of(context);
    final name = _name.text.trim();
    final city = _city.text.trim();
    if (name.isEmpty || city.isEmpty) {
      LumaHaptics.reject();
      setState(() => _error = l.setupShopNeeded);
      return;
    }
    setState(() => _error = null);
    await context.read<SetupController>().saveShop(name: name, city: city, area: _area.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return _StepFrame(
      title: l.setupShopTitle,
      subtitle: l.setupShopSubtitle,
      error: _error,
      action: _MainButton(label: l.continueLabel, onPressed: _save),
      children: [
        _label(context, l.setupShopName),
        TextField(
          key: const ValueKey('shop-name'),
          controller: _name,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(prefixIcon: Icon(Icons.storefront_outlined)),
        ),
        _label(context, l.setupShopCity),
        TextField(
          key: const ValueKey('shop-city'),
          controller: _city,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(prefixIcon: Icon(Icons.location_city_outlined)),
        ),
        _label(context, l.setupShopArea),
        TextField(
          key: const ValueKey('shop-area'),
          controller: _area,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _save(),
          decoration: const InputDecoration(prefixIcon: Icon(Icons.place_outlined)),
        ),
      ],
    );
  }
}

/* -------------------------------------------------------------------------- */
/* 2. Suppliers                                                               */
/* -------------------------------------------------------------------------- */

class _SuppliersStep extends StatelessWidget {
  const _SuppliersStep();

  @override
  Widget build(BuildContext context) {
    final c = context.lamp;
    final l = L10n.of(context);
    final setup = context.watch<SetupController>();
    return _StepFrame(
      title: l.setupSuppliersTitle,
      subtitle: l.setupSuppliersSubtitle,
      action: _MainButton(label: l.continueLabel, onPressed: setup.skip),
      children: [
        if (setup.suppliers.isEmpty)
          Text(l.setupSuppliersNone, style: LaMPType.body.copyWith(color: c.inkFaint))
        else
          LampCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final s in setup.suppliers)
                  LampRow(
                    icon: Icons.local_shipping_outlined,
                    title: s.name,
                    subtitle: l.supplierTerms(
                        _num(context, s.paymentDays), _num(context, s.returnCutoffDays)),
                    trailing: IconButton(
                      tooltip: l.supplierRemove(s.name),
                      icon: const Icon(Icons.delete_outline),
                      color: c.inkFaint,
                      onPressed: setup.busy ? null : () => setup.removeSupplier(s),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: Gap.md),
        OutlinedButton.icon(
          key: const ValueKey('add-supplier'),
          onPressed: setup.busy
              ? null
              : () async {
                  final s = await LumaSheet.show<Supplier>(
                    context: context,
                    title: l.setupAddSupplier,
                    fitContent: true,
                    builder: (_) => const _SupplierSheet(),
                  );
                  if (s != null) await setup.addSupplier(s);
                },
          icon: const Icon(Icons.add),
          label: Text(l.setupAddSupplier),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
      ],
    );
  }
}

class _SupplierSheet extends StatefulWidget {
  const _SupplierSheet();

  @override
  State<_SupplierSheet> createState() => _SupplierSheetState();
}

class _SupplierSheetState extends State<_SupplierSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _pay = TextEditingController(text: '${Supplier.defaultPaymentDays}');
  final _back = TextEditingController(text: '${Supplier.defaultReturnCutoffDays}');
  String? _error;

  @override
  void dispose() {
    for (final t in [_name, _phone, _pay, _back]) {
      t.dispose();
    }
    super.dispose();
  }

  void _save() {
    final l = L10n.of(context);
    final name = _name.text.trim();
    final pay = parseWhole(_pay.text);
    final back = parseWhole(_back.text);
    if (name.isEmpty) return setState(() => _error = l.supplierName);
    if (pay == null || back == null || pay > 365 || back > 365) {
      return setState(() => _error = l.setupWholeInvalid);
    }
    Navigator.of(context).pop(Supplier(
      name: name,
      // Phone numbers keep English digits (plan 5.4).
      phone: enDigits(_phone.text.trim()),
      paymentDays: pay,
      returnCutoffDays: back,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.lamp;
    final l = L10n.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _label(context, l.supplierName),
          TextField(
            key: const ValueKey('supplier-name'),
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
          ),
          _label(context, l.supplierPhone),
          TextField(
            key: const ValueKey('supplier-phone'),
            controller: _phone,
            keyboardType: TextInputType.phone,
            style: LaMPType.monoBody.copyWith(color: c.ink),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _label(context, l.supplierPaymentDays),
                    TextField(
                      key: const ValueKey('supplier-pay'),
                      controller: _pay,
                      keyboardType: TextInputType.number,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _label(context, l.supplierReturnDays),
                    TextField(
                      key: const ValueKey('supplier-back'),
                      controller: _back,
                      keyboardType: TextInputType.number,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: Gap.md),
              child: Text(_error!, style: LaMPType.body.copyWith(color: c.dispute)),
            ),
          const SizedBox(height: Gap.lg),
          ElevatedButton(
            key: const ValueKey('supplier-save'),
            onPressed: _save,
            style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: Text(l.setupSave),
          ),
        ],
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/* 3. Cash in the drawer                                                      */
/* -------------------------------------------------------------------------- */

class _CashStep extends StatefulWidget {
  const _CashStep();

  @override
  State<_CashStep> createState() => _CashStepState();
}

class _CashStepState extends State<_CashStep> {
  final _cash = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _cash.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = parseAmount(_cash.text);
    if (amount == null) {
      LumaHaptics.reject();
      setState(() => _error = L10n.of(context).setupAmountInvalid);
      return;
    }
    setState(() => _error = null);
    await context.read<SetupController>().saveCash(amount);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.lamp;
    final l = L10n.of(context);
    return _StepFrame(
      title: l.setupCashTitle,
      subtitle: l.setupCashSubtitle,
      error: _error,
      action: _MainButton(label: l.continueLabel, onPressed: _save),
      children: [
        _label(context, l.setupCashLabel),
        TextField(
          key: const ValueKey('cash'),
          controller: _cash,
          autofocus: true,
          keyboardType: _amountKeyboard,
          style: LaMPType.monoBody.copyWith(color: c.ink),
          onSubmitted: (_) => _save(),
          decoration: const InputDecoration(prefixText: '৳ '),
        ),
      ],
    );
  }
}

/* -------------------------------------------------------------------------- */
/* 4. Rent and salaries                                                       */
/* -------------------------------------------------------------------------- */

class _ExpensesStep extends StatefulWidget {
  const _ExpensesStep();

  @override
  State<_ExpensesStep> createState() => _ExpensesStepState();
}

class _ExpensesStepState extends State<_ExpensesStep> {
  final _rent = TextEditingController();
  final _rentDay = TextEditingController(text: '1');
  final _salaries = TextEditingController();
  final _salariesDay = TextEditingController(text: '1');
  String? _error;

  @override
  void dispose() {
    for (final t in [_rent, _rentDay, _salaries, _salariesDay]) {
      t.dispose();
    }
    super.dispose();
  }

  /// A blank amount means "none"; anything typed must read as money and a day.
  Future<void> _save() async {
    final l = L10n.of(context);
    final lines = <MonthlyExpense>[];
    for (final (category, amount, day) in [
      ('rent', _rent, _rentDay),
      ('salaries', _salaries, _salariesDay),
    ]) {
      if (amount.text.trim().isEmpty) continue;
      final a = parseAmount(amount.text);
      if (a == null) return setState(() => _error = l.setupAmountInvalid);
      final d = parseWhole(day.text);
      if (d == null || d < 1 || d > 31) return setState(() => _error = l.setupDayInvalid);
      lines.add(MonthlyExpense(category: category, amount: a, dayOfMonth: d));
    }
    setState(() => _error = null);
    await context.read<SetupController>().saveExpenses(lines);
  }

  Widget _row(BuildContext context, String label, String key,
      TextEditingController amount, TextEditingController day) {
    final c = context.lamp;
    final l = L10n.of(context);
    return LampCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: LaMPType.head.copyWith(color: c.ink)),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _label(context, l.expenseAmount),
                    TextField(
                      key: ValueKey('$key-amount'),
                      controller: amount,
                      keyboardType: _amountKeyboard,
                      style: LaMPType.monoBody.copyWith(color: c.ink),
                      decoration: const InputDecoration(prefixText: '৳ '),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _label(context, l.expenseDay),
                    TextField(
                      key: ValueKey('$key-day'),
                      controller: day,
                      keyboardType: TextInputType.number,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return _StepFrame(
      title: l.setupExpensesTitle,
      subtitle: l.setupExpensesSubtitle,
      error: _error,
      action: _MainButton(label: l.continueLabel, onPressed: _save),
      children: [
        _row(context, l.expenseRent, 'rent', _rent, _rentDay),
        const SizedBox(height: Gap.md),
        _row(context, l.expenseSalaries, 'salaries', _salaries, _salariesDay),
      ],
    );
  }
}

/* -------------------------------------------------------------------------- */
/* 5. Stock                                                                   */
/* -------------------------------------------------------------------------- */

class _StockStep extends StatelessWidget {
  const _StockStep();

  Future<void> _finish(BuildContext context, String then) async {
    final setup = context.read<SetupController>();
    final message = L10n.of(context).setupDone;
    if (!await setup.finish() || !context.mounted) return;
    LumaHaptics.confirm();
    LumaToast.show(context, message, icon: Icons.check_circle_outline);
    context.go(then);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.lamp;
    final l = L10n.of(context);
    final bn = _bangla(context);
    final setup = context.watch<SetupController>();
    return _StepFrame(
      title: l.setupStockTitle,
      subtitle: l.setupStockSubtitle,
      action: _MainButton(
        label: l.setupFinish,
        keyName: 'setup-finish',
        onPressed: () => _finish(context, '/today'),
      ),
      children: [
        ElevatedButton.icon(
          key: const ValueKey('setup-scan'),
          onPressed: setup.busy ? null : () => _finish(context, '/scan'),
          icon: const Icon(Icons.document_scanner_outlined),
          label: Text(l.setupScanBills),
          style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
        const SizedBox(height: Gap.md),
        OutlinedButton.icon(
          key: const ValueKey('add-stock'),
          onPressed: setup.busy
              ? null
              : () async {
                  final line = await LumaSheet.show<StockLine>(
                    context: context,
                    title: l.setupAddStock,
                    builder: (_) => _StockLineSheet(suppliers: setup.suppliers),
                  );
                  if (line != null) setup.addStockLine(line);
                },
          icon: const Icon(Icons.edit_note),
          label: Text(l.setupAddStock),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
        if (setup.stock.isNotEmpty) ...[
          const SizedBox(height: Gap.md),
          LampCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final s in setup.stock)
                  LampRow(
                    icon: Icons.medication_outlined,
                    // Strengths keep English digits, as printed on the box.
                    title: [s.product, s.strength].whereType<String>().where((x) => x.isNotEmpty).join(' '),
                    subtitle: l.stockLineSummary(
                        bn ? bnDigits('${s.qty}') : '${s.qty}', formatDay(s.expiryDate, bangla: bn)),
                    trailing: IconButton(
                      tooltip: l.removeLine,
                      icon: const Icon(Icons.delete_outline),
                      color: c.inkFaint,
                      onPressed: () => setup.removeStockLine(s),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _StockLineSheet extends StatefulWidget {
  const _StockLineSheet({required this.suppliers});

  final List<Supplier> suppliers;

  @override
  State<_StockLineSheet> createState() => _StockLineSheetState();
}

class _StockLineSheetState extends State<_StockLineSheet> {
  final _product = TextEditingController();
  final _strength = TextEditingController();
  final _batch = TextEditingController();
  final _qty = TextEditingController();
  final _cost = TextEditingController();
  DateTime? _expiry;
  String? _supplierId;
  String? _error;

  @override
  void dispose() {
    for (final t in [_product, _strength, _batch, _qty, _cost]) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _pickExpiry() async {
    final today = dhakaToday();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiry ?? DateTime(today.year + 1, today.month, 1),
      firstDate: DateTime(today.year - 1),
      lastDate: DateTime(today.year + 10),
    );
    if (picked != null) setState(() => _expiry = picked);
  }

  void _save() {
    final product = _product.text.trim();
    final batch = _batch.text.trim();
    final qty = parseWhole(_qty.text);
    final cost = parseAmount(_cost.text);
    if (product.isEmpty || batch.isEmpty || _expiry == null || qty == null || qty == 0 || cost == null) {
      return setState(() => _error = L10n.of(context).stockFieldsNeeded);
    }
    Navigator.of(context).pop(StockLine(
      product: product,
      strength: enDigits(_strength.text.trim()),
      batchNo: enDigits(batch),
      expiryDate: _expiry!,
      qty: qty,
      unitCost: cost,
      supplierId: _supplierId,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.lamp;
    final l = L10n.of(context);
    final expiry = _expiry;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _label(context, l.stockProduct),
          TextField(
            key: const ValueKey('stock-product'),
            controller: _product,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
          ),
          _label(context, l.stockStrength),
          TextField(key: const ValueKey('stock-strength'), controller: _strength),
          _label(context, l.stockBatch),
          TextField(
            key: const ValueKey('stock-batch'),
            controller: _batch,
            textCapitalization: TextCapitalization.characters,
            style: LaMPType.monoBody.copyWith(color: c.ink),
          ),
          _label(context, l.stockExpiry),
          OutlinedButton.icon(
            key: const ValueKey('stock-expiry'),
            onPressed: _pickExpiry,
            icon: const Icon(Icons.event_outlined),
            label: Text(expiry == null
                ? l.stockExpiryPick
                : formatDay(expiry, bangla: _bangla(context))),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _label(context, l.stockQty),
                    TextField(
                      key: const ValueKey('stock-qty'),
                      controller: _qty,
                      keyboardType: TextInputType.number,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _label(context, l.stockUnitCost),
                    TextField(
                      key: const ValueKey('stock-cost'),
                      controller: _cost,
                      keyboardType: _amountKeyboard,
                      style: LaMPType.monoBody.copyWith(color: c.ink),
                      decoration: const InputDecoration(prefixText: '৳ '),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (widget.suppliers.any((s) => s.id != null)) ...[
            _label(context, l.stockSupplier),
            DropdownButtonFormField<String?>(
              key: const ValueKey('stock-supplier'),
              initialValue: _supplierId,
              isExpanded: true,
              items: [
                DropdownMenuItem(value: null, child: Text(l.stockSupplierNone)),
                for (final s in widget.suppliers)
                  if (s.id != null) DropdownMenuItem(value: s.id, child: Text(s.name)),
              ],
              onChanged: (v) => setState(() => _supplierId = v),
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: Gap.md),
              child: Text(_error!, style: LaMPType.body.copyWith(color: c.dispute)),
            ),
          const SizedBox(height: Gap.lg),
          ElevatedButton(
            key: const ValueKey('stock-save'),
            onPressed: _save,
            style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: Text(l.setupSave),
          ),
        ],
      ),
    );
  }
}
