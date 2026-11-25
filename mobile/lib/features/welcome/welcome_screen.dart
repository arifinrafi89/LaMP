import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/api/problem.dart';
import '../../core/auth/auth_service.dart';
import '../../core/auth/phone_number.dart';
import '../../core/constants/palette.dart';
import '../../core/constants/typography.dart';
import '../../core/design/luma_press.dart';
import '../../core/l10n/digits.dart';
import '../../core/state/locale_controller.dart';
import '../../core/state/session_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/lamp_mark.dart';

/// Welcome, number and code (adapted from lamp-flutter's sign_in_screen).
///
/// The welcome, number and code steps and the resend timer keep their look.
/// Google, the seat picker and registration are gone; a language choice and
/// the terms consent are new. On success the router moves on by itself:
/// to Setup for a new shop, to Today for a returning owner.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

enum _Step { welcome, phone, code }

class _WelcomeScreenState extends State<WelcomeScreen> {
  static const _codeLength = 6;

  _Step _step = _Step.welcome;
  bool _agreed = false;
  final _phone = TextEditingController();
  final _code = TextEditingController();
  OtpChallenge? _challenge;

  bool _busy = false;
  String? _error;

  DateTime? _canResendAt;
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  void _go(_Step step) => setState(() {
        _step = step;
        _error = null;
        _code.clear();
      });

  /// Runs one action with progress shown, and plain words if it fails.
  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on ApiProblem catch (p) {
      if (!mounted) return;
      LumaHaptics.reject();
      setState(() => _error = problemMessage(L10n.of(context), p));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() async {
    final l = L10n.of(context);
    final check = checkBanglalink(_phone.text);
    switch (check.result) {
      case PhoneResult.invalid:
        setState(() => _error = l.phoneInvalid);
        return;
      case PhoneResult.notBanglalink:
        setState(() => _error = l.errNotBanglalink);
        return;
      case PhoneResult.ok:
        break;
    }
    final session = context.read<SessionController>();
    final language = context.read<LocaleController>().languageFor(context);
    await _run(() async {
      final c = await session.requestCode(check.e164!, language);
      if (!mounted) return;
      _challenge = c;
      _startCooldown(c.resendAfter);
      _go(_Step.code);
    });
  }

  Future<void> _confirmCode() async {
    final challenge = _challenge;
    if (challenge == null || _code.text.length != _codeLength) return;
    final session = context.read<SessionController>();
    await _run(() => session.verifyCode(challenge, _code.text, agreedToTerms: _agreed));
    if (mounted && _error != null) _code.clear();
  }

  void _startCooldown(Duration wait) {
    _canResendAt = DateTime.now().add(wait);
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() {});
      if (_resendRemaining == null) t.cancel();
    });
  }

  Duration? get _resendRemaining {
    final at = _canResendAt;
    if (at == null) return null;
    final left = at.difference(DateTime.now());
    return left.isNegative ? null : left;
  }

  bool get _bangla => Localizations.localeOf(context).languageCode == 'bn';

  @override
  Widget build(BuildContext context) {
    final c = context.lamp;
    final body = switch (_step) {
      _Step.welcome => _welcome(context),
      _Step.phone => _phoneStep(context),
      _Step.code => _codeStep(context),
    };
    return PopScope(
      canPop: _step == _Step.welcome,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _go(_step == _Step.code ? _Step.phone : _Step.welcome);
      },
      child: Scaffold(
        backgroundColor: c.bg,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              // Phone-width on a desktop browser too.
              constraints: const BoxConstraints(maxWidth: 480),
              child: AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: body),
            ),
          ),
        ),
      ),
    );
  }

  Widget _welcome(BuildContext context) {
    final c = context.lamp;
    final l = L10n.of(context);
    final locale = context.watch<LocaleController>();
    final current = locale.languageFor(context);
    return ListView(
      key: const ValueKey('welcome'),
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.xxl, Gap.lg, Gap.xl),
      children: [
        const Center(child: LampMark(size: 72)),
        const SizedBox(height: Gap.lg),
        Text(l.welcomeTitle,
            textAlign: TextAlign.center, style: LaMPType.title.copyWith(color: c.ink)),
        const SizedBox(height: Gap.xs),
        Text(l.welcomeSubtitle,
            textAlign: TextAlign.center, style: LaMPType.body.copyWith(color: c.inkMuted)),
        const SizedBox(height: Gap.xxl),
        Text(l.languageLabel, style: LaMPType.meta.copyWith(color: c.inkMuted)),
        const SizedBox(height: Gap.sm),
        SegmentedButton<String>(
          key: const ValueKey('language'),
          segments: [
            ButtonSegment(value: 'bn', label: Text(l.languageBangla)),
            ButtonSegment(value: 'en', label: Text(l.languageEnglish)),
          ],
          selected: {current},
          showSelectedIcon: false,
          onSelectionChanged: (s) => locale.set(Locale(s.single)),
        ),
        const SizedBox(height: Gap.xl),
        CheckboxListTile(
          key: const ValueKey('agree-terms'),
          value: _agreed,
          onChanged: (v) => setState(() => _agreed = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: Text(l.termsAgree, style: LaMPType.body.copyWith(color: c.ink)),
        ),
        const SizedBox(height: Gap.lg),
        ElevatedButton.icon(
          key: const ValueKey('continue-phone'),
          onPressed: _agreed && !_busy ? () => _go(_Step.phone) : null,
          icon: const Icon(Icons.smartphone_outlined, size: IconSize.md),
          label: Text(l.welcomeContinue),
          style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
      ],
    );
  }

  Widget _phoneStep(BuildContext context) {
    final c = context.lamp;
    final l = L10n.of(context);
    return ListView(
      key: const ValueKey('phone'),
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.xl),
      children: [
        _backButton(context, () => _go(_Step.welcome)),
        const SizedBox(height: Gap.lg),
        Text(l.phoneTitle, style: LaMPType.title.copyWith(color: c.ink)),
        const SizedBox(height: Gap.xs),
        Text(l.phoneSubtitle, style: LaMPType.body.copyWith(color: c.inkMuted)),
        const SizedBox(height: Gap.xl),
        Text(l.phoneLabel, style: LaMPType.meta.copyWith(color: c.inkMuted)),
        const SizedBox(height: Gap.sm),
        TextField(
          key: const ValueKey('phone-field'),
          controller: _phone,
          autofocus: true,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          // Phone numbers keep English digits in both languages (plan 5.4).
          style: LaMPType.monoBody.copyWith(color: c.ink),
          decoration: const InputDecoration(
            hintText: '01912 345678',
            prefixIcon: Icon(Icons.phone_outlined),
          ),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onSubmitted: (_) => _busy ? null : _sendCode(),
        ),
        _errorText(context),
        const SizedBox(height: Gap.xl),
        ElevatedButton(
          key: const ValueKey('send-code'),
          onPressed: _busy ? null : _sendCode,
          style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          child: Text(_busy ? l.sending : l.sendCode),
        ),
      ],
    );
  }

  Widget _codeStep(BuildContext context) {
    final c = context.lamp;
    final l = L10n.of(context);
    final left = _resendRemaining;
    final seconds = '${(left?.inSeconds ?? 0) + 1}';
    return ListView(
      key: const ValueKey('code'),
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.xl),
      children: [
        _backButton(context, () => _go(_Step.phone)),
        const SizedBox(height: Gap.lg),
        Text(l.codeTitle, style: LaMPType.title.copyWith(color: c.ink)),
        const SizedBox(height: Gap.xs),
        Text(l.codeSentTo(formatPhone(_challenge?.phone ?? '')),
            style: LaMPType.body.copyWith(color: c.inkMuted)),
        const SizedBox(height: Gap.xl),
        TextField(
          key: const ValueKey('code-field'),
          controller: _code,
          autofocus: true,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: _codeLength,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: LaMPType.displayFigure.copyWith(color: c.ink),
          decoration: const InputDecoration(counterText: '', hintText: '••••••'),
          onChanged: (v) {
            setState(() => _error = null);
            if (v.length == _codeLength && !_busy) _confirmCode();
          },
        ),
        _errorText(context),
        const SizedBox(height: Gap.xl),
        ElevatedButton(
          key: const ValueKey('confirm-code'),
          onPressed: _busy || _code.text.length != _codeLength ? null : _confirmCode,
          style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          child: Text(_busy ? l.checking : l.continueLabel),
        ),
        const SizedBox(height: Gap.md),
        TextButton(
          key: const ValueKey('resend'),
          onPressed: _busy || left != null ? null : _sendCode,
          child: Text(left == null
              ? l.resendCode
              : l.resendIn(_bangla ? bnDigits(seconds) : seconds)),
        ),
      ],
    );
  }

  Widget _backButton(BuildContext context, VoidCallback onTap) => Align(
        alignment: Alignment.centerLeft,
        child: IconButton(
          key: const ValueKey('back'),
          tooltip: L10n.of(context).back,
          onPressed: _busy ? null : onTap,
          icon: const Icon(Icons.arrow_back),
        ),
      );

  Widget _errorText(BuildContext context) {
    final e = _error;
    if (e == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: Gap.md),
      child: Text(e, style: LaMPType.body.copyWith(color: context.lamp.dispute)),
    );
  }
}
