import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/api/problem.dart';
import '../../core/constants/palette.dart';
import '../../core/constants/typography.dart';
import '../../core/state/me.dart';
import '../../core/state/shop_changes.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/ui/lamp_skeleton.dart';
import '../../widgets/ui/lamp_ui.dart';
import '../customers/customers_controller.dart';
import '../customers/customers_models.dart';
import 'keypad.dart';
import 'sms_phone_controller.dart';

/// The drawn basic phone (plan 5.7), for the demo video and the finale. It
/// texts 21213 through `/demo/sms`, so the demo shop's Customers screen
/// changes as a real family's would. Only when `/me` says `demo_tools`.
class SmsPhoneScreen extends StatelessWidget {
  const SmsPhoneScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final me = context.watch<MeController>();
    final Widget body;
    if (me.me == null && me.loading) {
      body = ListView(padding: const EdgeInsets.all(Gap.lg), children: const [LampSkeletonCard(lines: 6)]);
    } else if (me.me?.demoTools != true) {
      body = ListView(
        padding: const EdgeInsets.all(Gap.lg),
        children: [LampEmpty(icon: Icons.smartphone, title: l.phoneOnlyDemo, message: l.phoneOnlyDemoBody)],
      );
    } else {
      body = ChangeNotifierProvider(
        create: (context) => SmsPhoneController(
          context.read<ApiClient>(),
          onSent: context.read<ShopChanges>().saved,
          refreshOn: context.read<ShopChanges>(),
        ),
        child: const _Phone(),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l.navPhone)),
      body: body,
    );
  }
}

class _Phone extends StatefulWidget {
  const _Phone();

  @override
  State<_Phone> createState() => _PhoneState();
}

class _PhoneState extends State<_Phone> {
  final _keys = MultiTap();
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    final phone = context.read<SmsPhoneController>();
    phone.load();
    // Messages the owner triggers (a plan, a receipt) arrive while it's open.
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => phone.load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _press(String key) => setState(() => _keys.press(key, DateTime.now()));

  Future<void> _send(SmsPhoneController phone) async {
    if (await phone.send(_keys.text) && mounted) setState(_keys.clear);
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final c = context.lamp;
    final phone = context.watch<SmsPhoneController>();
    final people = context.watch<CustomersController>().customers?.items ?? const [];
    final width = MediaQuery.sizeOf(context).width;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Gap.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: SizedBox(
              width: (width - Gap.lg * 2).clamp(0.0, 340.0),
              child: CustomPaint(
                painter: _BodyPainter(c.phoneBody, c.phoneScreen),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.xxl, Gap.lg, Gap.xl),
                  child: Column(
                    children: [
                      _Screen(phone: phone, typed: _keys.text, letters: _keys.letters),
                      const SizedBox(height: Gap.lg),
                      _Keypad(onKey: _press, onSend: phone.sending ? null : () => _send(phone)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (phone.problem != null) LampErrorText(problemMessage(l, phone.problem!)),
          const SizedBox(height: Gap.md),
          Text(l.phoneHowTo, style: LaMPType.caption.copyWith(color: c.inkMuted)),
          if (people.isNotEmpty) ...[
            const SizedBox(height: Gap.lg),
            LampSectionHeader(title: l.phoneFillTitle),
            Wrap(
              spacing: Gap.sm,
              runSpacing: Gap.sm,
              children: [
                for (final p in people)
                  ActionChip(
                    key: ValueKey('phone-fill-${p.code}'),
                    label: Text(p.join.text, style: LaMPType.monoCaption),
                    onPressed: () => setState(() => _keys.fill(p.join.text)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The monochrome screen: the thread with 21213, then what is being typed.
class _Screen extends StatelessWidget {
  const _Screen({required this.phone, required this.typed, required this.letters});

  final SmsPhoneController phone;
  final String typed;
  final bool letters;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final c = context.lamp;
    final ink = c.phoneInk;
    final thread = phone.thread;
    return Container(
      height: 220,
      padding: const EdgeInsets.all(Gap.sm),
      decoration: BoxDecoration(color: c.phoneScreen, borderRadius: BorderRadius.circular(LaMPRadius.control)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(shortCode, style: LaMPType.monoCaption.copyWith(color: ink)),
          Divider(height: Gap.sm, color: ink),
          Expanded(
            child: thread.isEmpty
                ? Center(
                    child: Text(
                      phone.loaded ? l.phoneEmptyThread : '…',
                      style: LaMPType.monoCaption.copyWith(color: ink),
                    ),
                  )
                : ListView(
                    reverse: true,
                    children: [
                      for (final m in thread.reversed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Gap.xs),
                          child: Text(
                            m.text,
                            textAlign: m.fromPhone ? TextAlign.right : TextAlign.left,
                            style: LaMPType.monoCaption.copyWith(color: ink),
                          ),
                        ),
                    ],
                  ),
          ),
          Divider(height: Gap.sm, color: ink),
          Row(
            children: [
              Expanded(
                child: Text(
                  typed,
                  key: const ValueKey('phone-typed'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: LaMPType.monoBody.copyWith(color: ink),
                ),
              ),
              Text(letters ? 'ABC' : '123', style: LaMPType.monoMicro.copyWith(color: ink)),
            ],
          ),
        ],
      ),
    );
  }
}

const _layout = [
  ['1', '2', '3'],
  ['4', '5', '6'],
  ['7', '8', '9'],
  ['*', '0', '#'],
];

class _Keypad extends StatelessWidget {
  const _Keypad({required this.onKey, required this.onSend});

  final void Function(String key) onKey;
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final c = context.lamp;
    return Column(
      children: [
        _Key(
          keyName: 'send',
          label: l.phoneSend,
          letters: '',
          background: c.brand,
          ink: c.onBrand,
          onTap: onSend,
          wide: true,
        ),
        const SizedBox(height: Gap.sm),
        for (final row in _layout) ...[
          Row(
            children: [
              for (final k in row) ...[
                if (k != row.first) const SizedBox(width: Gap.sm),
                Expanded(
                  child: _Key(
                    keyName: 'key-$k',
                    label: k,
                    letters: switch (k) {
                      '*' => '⌫',
                      '#' => 'ABC/123',
                      '0' => '␣',
                      '1' => '-',
                      _ => (keyLetters[k] ?? '').replaceAll(RegExp('[0-9]'), ''),
                    },
                    background: c.phoneScreen,
                    ink: c.phoneInk,
                    onTap: () => onKey(k),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: Gap.sm),
        ],
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    required this.keyName,
    required this.label,
    required this.letters,
    required this.background,
    required this.ink,
    required this.onTap,
    this.wide = false,
  });

  final String keyName;
  final String label;
  final String letters;
  final Color background;
  final Color ink;
  final VoidCallback? onTap;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: ValueKey('phone-$keyName'),
      color: background,
      borderRadius: BorderRadius.circular(LaMPRadius.control),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(LaMPRadius.control),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          width: wide ? double.infinity : null,
          padding: const EdgeInsets.symmetric(vertical: Gap.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label, style: LaMPType.sub.copyWith(color: ink)),
              if (letters.isNotEmpty) Text(letters, style: LaMPType.monoMicro.copyWith(color: ink)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The candy-bar body: rounded, with the earpiece slot above the screen.
class _BodyPainter extends CustomPainter {
  const _BodyPainter(this.body, this.slot);

  final Color body;
  final Color slot;

  @override
  void paint(Canvas canvas, Size size) {
    final outline = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(36));
    canvas.drawRRect(outline, Paint()..color = body);
    final earpiece = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(size.width / 2, Gap.lg), width: size.width * 0.22, height: 6),
      const Radius.circular(3),
    );
    canvas.drawRRect(earpiece, Paint()..color = slot.withValues(alpha: 0.5));
  }

  @override
  bool shouldRepaint(_BodyPainter old) => old.body != body || old.slot != slot;
}
