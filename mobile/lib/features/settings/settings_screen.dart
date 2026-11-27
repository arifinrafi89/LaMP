import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_config.dart';
import '../../core/api/problem.dart';
import '../../core/constants/palette.dart';
import '../../core/constants/typography.dart';
import '../../core/design/luma_sheet.dart';
import '../../core/design/luma_toast.dart';
import '../../core/l10n/digits.dart';
import '../../core/links.dart';
import '../../core/offline/cache_store.dart';
import '../../core/state/locale_controller.dart';
import '../../core/state/session_controller.dart';
import '../../core/state/theme_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/ui/lamp_skeleton.dart';
import '../../widgets/ui/lamp_ui.dart';
import 'settings_controller.dart';

/// Settings (plan 15.1, 13.3): language, theme, signed-in phones, the
/// owner's data out, and deleting the account.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => DevicesController(api, context.read<CacheStore>())..load()),
        ChangeNotifierProvider(create: (context) => LegalController(api, context.read<CacheStore>())..load()),
        ChangeNotifierProvider(create: (_) => ExportController(api)),
        Provider(create: (_) => SettingsActions(api)),
      ],
      child: const _SettingsView(),
    );
  }
}

class _SettingsView extends StatelessWidget {
  const _SettingsView();

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.navSettings)),
      // Not lazy: one fixed page, and every part of it is there to find.
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(Gap.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LampSectionHeader(title: l.settingsLook),
            const _Look(),
            const SizedBox(height: Gap.lg),
            LampSectionHeader(title: l.settingsDevices),
            const _Devices(),
            const SizedBox(height: Gap.lg),
            LampSectionHeader(title: l.settingsYourData),
            const _Export(),
            const SizedBox(height: Gap.sm),
            const _Delete(),
            const SizedBox(height: Gap.lg),
            LampSectionHeader(title: l.settingsLegal),
            const _Legal(),
            const SizedBox(height: Gap.lg),
            const _SignOut(),
            const SizedBox(height: Gap.lg),
            Center(
              child: Text(
                l.settingsVersion(lampAppVersion),
                style: LaMPType.monoCaption.copyWith(color: context.lamp.inkFaint),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Look extends StatefulWidget {
  const _Look();

  @override
  State<_Look> createState() => _LookState();
}

class _LookState extends State<_Look> {
  bool _notSent = false;

  Future<void> _language(String code) async {
    final actions = context.read<SettingsActions>();
    // The phone's choice first: the app switches at once, online or not.
    await context.read<LocaleController>().set(Locale(code));
    try {
      await actions.setLanguage(code);
      if (mounted) setState(() => _notSent = false);
    } on ApiProblem {
      if (mounted) setState(() => _notSent = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final c = context.lamp;
    final lang = context.watch<LocaleController>().languageFor(context);
    final theme = context.watch<ThemeController>();
    final mode = theme.mode == ThemeMode.dark ? ThemeMode.dark : ThemeMode.light;
    return LampCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.languageLabel, style: LaMPType.caption.copyWith(color: c.inkFaint)),
          const SizedBox(height: Gap.xs),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(
                value: 'bn',
                label: Text(l.languageBangla, key: const ValueKey('lang-bn')),
              ),
              ButtonSegment(
                value: 'en',
                label: Text(l.languageEnglish, key: const ValueKey('lang-en')),
              ),
            ],
            selected: {lang},
            onSelectionChanged: (s) => _language(s.first),
          ),
          Text(
            _notSent ? l.settingsLanguageNotSent : l.settingsLanguageNote,
            style: LaMPType.caption.copyWith(color: _notSent ? c.pending : c.inkMuted),
          ),
          const SizedBox(height: Gap.md),
          Text(l.settingsTheme, style: LaMPType.caption.copyWith(color: c.inkFaint)),
          const SizedBox(height: Gap.xs),
          SegmentedButton<ThemeMode>(
            segments: [
              ButtonSegment(
                value: ThemeMode.light,
                label: Text(l.themeLight, key: const ValueKey('theme-light')),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                label: Text(l.themeDark, key: const ValueKey('theme-dark')),
              ),
            ],
            selected: {mode},
            onSelectionChanged: (s) => theme.set(s.first),
          ),
        ],
      ),
    );
  }
}

class _Devices extends StatelessWidget {
  const _Devices();

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final c = context.lamp;
    final bn = isBangla(context);
    final ctrl = context.watch<DevicesController>();
    final list = ctrl.devices;
    if (list == null) {
      return LampCard(
        child: ctrl.problem == null
            ? const Center(child: LampBusy())
            : Text(problemMessage(l, ctrl.problem!), style: LaMPType.body.copyWith(color: c.inkMuted)),
      );
    }
    return LampCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (final d in list)
            LampRow(
              icon: d.os == 'web' ? Icons.language : Icons.phone_android,
              title: d.thisDevice ? l.settingsThisDevice : d.name,
              subtitle: d.thisDevice
                  ? d.name
                  : d.lastUsedAt == null
                  ? null
                  : l.settingsLastUsed(formatDay(dhakaToday(d.lastUsedAt), bangla: bn)),
              trailing: d.thisDevice
                  ? null
                  : TextButton(
                      key: ValueKey('device-signout-${d.id}'),
                      onPressed: () async {
                        try {
                          await context.read<SettingsActions>().signOutDevice(d.id);
                          if (context.mounted) LumaToast.show(context, l.settingsSignedOutDevice(d.name));
                          await ctrl.load();
                        } on ApiProblem catch (p) {
                          if (context.mounted) {
                            LumaToast.show(context, problemMessage(l, p), tone: LumaToastTone.pending);
                          }
                        }
                      },
                      child: Text(l.settingsSignOutDevice),
                    ),
            ),
        ],
      ),
    );
  }
}

class _Export extends StatelessWidget {
  const _Export();

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final c = context.lamp;
    final e = context.watch<ExportController>();
    final open = context.read<OpenLink>();
    final List<Widget> state = switch (e.stage) {
      ExportStage.idle => [],
      ExportStage.building => [
        Row(
          children: [
            const LampBusy(),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Text(l.settingsExportBuilding, style: LaMPType.body.copyWith(color: c.ink)),
            ),
          ],
        ),
      ],
      ExportStage.ready => [
        Text(l.settingsExportReady, style: LaMPType.body.copyWith(color: c.ink)),
        const SizedBox(height: Gap.sm),
        ElevatedButton.icon(
          key: const ValueKey('settings-export-open'),
          onPressed: () => open(Uri.parse(e.url!)),
          style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          icon: const Icon(Icons.download),
          label: Text(l.settingsExportOpen),
        ),
      ],
      ExportStage.waiting => [
        Text(l.settingsExportWaiting, style: LaMPType.body.copyWith(color: c.ink)),
        const SizedBox(height: Gap.sm),
        OutlinedButton(
          key: const ValueKey('settings-export-check'),
          onPressed: e.checkAgain,
          child: Text(l.checkAgain),
        ),
      ],
      ExportStage.failed => [
        Text(
          e.problem == null ? l.settingsExportFailed : problemMessage(l, e.problem!),
          style: LaMPType.body.copyWith(color: c.dispute),
        ),
      ],
    };
    return LampCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.settingsExport, style: LaMPType.sub.copyWith(color: c.ink)),
          Text(l.settingsExportBody, style: LaMPType.caption.copyWith(color: c.inkMuted)),
          const SizedBox(height: Gap.md),
          ...state,
          if (e.stage == ExportStage.idle || e.stage == ExportStage.failed)
            OutlinedButton.icon(
              key: const ValueKey('settings-export'),
              onPressed: e.start,
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              icon: const Icon(Icons.archive_outlined),
              label: Text(l.settingsExport),
            ),
        ],
      ),
    );
  }
}

class _Delete extends StatelessWidget {
  const _Delete();

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final c = context.lamp;
    return LampCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.settingsDelete, style: LaMPType.sub.copyWith(color: c.ink)),
          Text(l.settingsDeleteBody, style: LaMPType.caption.copyWith(color: c.inkMuted)),
          const SizedBox(height: Gap.md),
          OutlinedButton(
            key: const ValueKey('settings-delete'),
            onPressed: () => _confirmDelete(context),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), foregroundColor: c.dispute),
            child: Text(l.settingsDelete),
          ),
        ],
      ),
    );
  }
}

Future<void> _confirmDelete(BuildContext context) async {
  final l = L10n.of(context);
  final actions = context.read<SettingsActions>();
  final session = context.read<SessionController>();
  final eraseOn = await LumaSheet.show<DateTime>(
    context: context,
    title: l.settingsDelete,
    fitContent: true,
    builder: (_) => _DeleteSheet(actions: actions),
  );
  if (eraseOn == null || !context.mounted) return;
  final bn = isBangla(context);
  await LumaSheet.show<void>(
    context: context,
    title: l.settingsDelete,
    fitContent: true,
    dismissible: false,
    builder: (sheet) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l.settingsDeleted(formatDay(eraseOn, bangla: bn)),
          style: LaMPType.body.copyWith(color: sheet.lamp.ink),
        ),
        const SizedBox(height: Gap.lg),
        ElevatedButton(
          key: const ValueKey('delete-done'),
          onPressed: () => Navigator.of(sheet).pop(),
          style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: Text(l.continueLabel),
        ),
      ],
    ),
  );
  // The server has ended every session; this phone forgets it too.
  await session.signOut();
}

class _DeleteSheet extends StatefulWidget {
  const _DeleteSheet({required this.actions});

  final SettingsActions actions;

  @override
  State<_DeleteSheet> createState() => _DeleteSheetState();
}

class _DeleteSheetState extends State<_DeleteSheet> {
  final _word = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _word.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    final l = L10n.of(context);
    if (_word.text.trim() != 'DELETE') return setState(() => _error = l.settingsDeleteNeedsWord);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final eraseOn = await widget.actions.deleteAccount();
      if (mounted) Navigator.of(context).pop(eraseOn);
    } on ApiProblem catch (p) {
      if (mounted) setState(() => _error = problemMessage(l, p));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final c = context.lamp;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.settingsDeleteBody, style: LaMPType.body.copyWith(color: c.ink)),
        const SizedBox(height: Gap.md),
        TextField(
          key: const ValueKey('delete-word'),
          controller: _word,
          autocorrect: false,
          style: LaMPType.monoBody,
          decoration: InputDecoration(labelText: l.settingsDeleteType),
        ),
        LampErrorText(_error),
        const SizedBox(height: Gap.md),
        ElevatedButton(
          key: const ValueKey('delete-confirm'),
          onPressed: _busy ? null : _delete,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            backgroundColor: c.dispute,
            foregroundColor: c.onBrand,
          ),
          child: _busy ? const LampBusy() : Text(l.settingsDeleteConfirm),
        ),
      ],
    );
  }
}

class _Legal extends StatelessWidget {
  const _Legal();

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final legal = context.watch<LegalController>().legal;
    final open = context.read<OpenLink>();
    return LampCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          LampRow(
            key: const ValueKey('settings-terms'),
            icon: Icons.description_outlined,
            title: l.settingsTerms,
            trailing: const Icon(Icons.open_in_new),
            onTap: legal == null ? null : () => open(Uri.parse(legal.termsUrl)),
          ),
          LampRow(
            key: const ValueKey('settings-privacy'),
            icon: Icons.privacy_tip_outlined,
            title: l.settingsPrivacy,
            trailing: const Icon(Icons.open_in_new),
            onTap: legal == null ? null : () => open(Uri.parse(legal.privacyUrl)),
          ),
        ],
      ),
    );
  }
}

class _SignOut extends StatelessWidget {
  const _SignOut();

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final c = context.lamp;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          key: const ValueKey('settings-signout'),
          onPressed: () => context.read<SessionController>().signOut(),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          icon: const Icon(Icons.logout),
          label: Text(l.settingsSignOut),
        ),
        const SizedBox(height: Gap.xs),
        Text(
          l.settingsSignOutBody,
          textAlign: TextAlign.center,
          style: LaMPType.caption.copyWith(color: c.inkMuted),
        ),
      ],
    );
  }
}
