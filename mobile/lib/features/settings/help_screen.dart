import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_config.dart';
import '../../core/api/problem.dart';
import '../../core/constants/palette.dart';
import '../../core/constants/typography.dart';
import '../../core/design/luma_sheet.dart';
import '../../core/design/luma_toast.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/ui/lamp_skeleton.dart';
import '../../widgets/ui/lamp_ui.dart';

/// Help (plan 15.1): plain answers to what owners ask, and Report a problem.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final c = context.lamp;
    final faq = [
      (l.helpQ1, l.helpA1),
      (l.helpQ2, l.helpA2),
      (l.helpQ3, l.helpA3),
      (l.helpQ4, l.helpA4),
      (l.helpQ5, l.helpA5),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(l.navHelp)),
      body: ListView(
        padding: const EdgeInsets.all(Gap.lg),
        children: [
          LampSectionHeader(title: l.helpTitle),
          LampCard(
            padding: EdgeInsets.zero,
            // Its own Material, so the tiles' ink shows on the card.
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                children: [
                  for (final (i, (q, a)) in faq.indexed)
                    ExpansionTile(
                      key: ValueKey('help-q-$i'),
                      title: Text(q, style: LaMPType.sub.copyWith(color: c.ink)),
                      childrenPadding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.md),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      children: [Text(a, style: LaMPType.body.copyWith(color: c.inkMuted))],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Gap.lg),
          LampCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l.reportTitle, style: LaMPType.sub.copyWith(color: c.ink)),
                Text(l.reportBody, style: LaMPType.caption.copyWith(color: c.inkMuted)),
                const SizedBox(height: Gap.md),
                ElevatedButton.icon(
                  key: const ValueKey('help-report'),
                  onPressed: () => reportProblem(context, screen: 'help'),
                  style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  icon: const Icon(Icons.flag_outlined),
                  label: Text(l.reportTitle),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Report a problem (`POST /support/reports`), from Help or any screen that
/// names itself in [screen].
Future<void> reportProblem(BuildContext context, {required String screen}) async {
  final l = L10n.of(context);
  final api = context.read<ApiClient>();
  final sent = await LumaSheet.show<bool>(
    context: context,
    title: l.reportTitle,
    builder: (_) => _ReportSheet(api: api, screen: screen),
  );
  if (sent == true && context.mounted) {
    LumaToast.show(context, l.reportSent, icon: Icons.check, tone: LumaToastTone.verified);
  }
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({required this.api, required this.screen});

  final ApiClient api;
  final String screen;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  final _message = TextEditingController();
  String _category = 'bug';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final l = L10n.of(context);
    final text = _message.text.trim();
    if (text.isEmpty) return setState(() => _error = l.reportNeeded);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.post('/support/reports', {
        'category': _category,
        'message': text,
        'screen': widget.screen,
        'app_version': lampAppVersion,
      });
      if (mounted) Navigator.of(context).pop(true);
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
    final kinds = [
      ('bug', l.reportBug),
      ('question', l.reportQuestion),
      ('idea', l.reportIdea),
      ('other', l.reportOther),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.reportBody, style: LaMPType.body.copyWith(color: c.inkMuted)),
        const SizedBox(height: Gap.md),
        Text(l.reportKind, style: LaMPType.caption.copyWith(color: c.inkFaint)),
        const SizedBox(height: Gap.xs),
        Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          children: [
            for (final (value, label) in kinds)
              ChoiceChip(
                key: ValueKey('report-$value'),
                label: Text(label),
                selected: _category == value,
                onSelected: (_) => setState(() => _category = value),
              ),
          ],
        ),
        const SizedBox(height: Gap.md),
        TextField(
          key: const ValueKey('report-message'),
          controller: _message,
          minLines: 3,
          maxLines: 6,
          maxLength: 2000,
          decoration: InputDecoration(labelText: l.reportMessage, counterText: ''),
        ),
        LampErrorText(_error),
        const SizedBox(height: Gap.md),
        ElevatedButton(
          key: const ValueKey('report-send'),
          onPressed: _busy ? null : _send,
          style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: _busy ? const LampBusy() : Text(l.reportSend),
        ),
      ],
    );
  }
}
