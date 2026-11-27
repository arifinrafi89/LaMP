import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/constants/palette.dart';
import '../../core/constants/typography.dart';
import '../../core/links.dart';
import '../../core/state/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/ui/lamp_ui.dart';

/// Around every screen (plan 13.5): below the minimum version a full-screen
/// "Update LaMP"; below the latest a banner the owner can put off; during
/// maintenance a plain screen. On web the newest build is a reload away.
class UpdateGate extends StatelessWidget {
  const UpdateGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final c = context.lamp;
    final cfg = context.watch<AppConfigController>();
    final open = context.read<OpenLink>();
    final play = cfg.playUrl;

    Widget update(String key) => ElevatedButton.icon(
      key: ValueKey(key),
      onPressed: play == null ? null : () => open(Uri.parse(play)),
      style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      icon: const Icon(Icons.system_update),
      label: Text(l.updateButton),
    );

    switch (cfg.state) {
      case UpdateState.ok:
        return child;
      case UpdateState.required:
        return _Blocking(
          icon: Icons.system_update,
          title: l.updateTitle,
          body: kIsWeb ? l.updateWeb : l.updateBody,
          action: kIsWeb ? null : update('update-play'),
        );
      case UpdateState.maintenance:
        return _Blocking(
          icon: Icons.build_outlined,
          title: l.maintenanceTitle,
          body: l.maintenanceBody,
          action: OutlinedButton(
            key: const ValueKey('maintenance-retry'),
            onPressed: cfg.load,
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: Text(l.retry),
          ),
        );
      case UpdateState.available:
        return Column(
          children: [
            Material(
              color: c.brandSoft,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.sm, Gap.sm),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(kIsWeb ? l.updateWeb : l.updateBanner, style: LaMPType.body.copyWith(color: c.ink)),
                      ),
                      if (!kIsWeb && play != null)
                        TextButton(
                          key: const ValueKey('update-banner-play'),
                          onPressed: () => open(Uri.parse(play)),
                          child: Text(l.updateButton),
                        ),
                      TextButton(key: const ValueKey('update-later'), onPressed: cfg.later, child: Text(l.updateLater)),
                    ],
                  ),
                ),
              ),
            ),
            // The banner takes the top inset; the app below doesn't add it again.
            Expanded(
              child: MediaQuery.removePadding(context: context, removeTop: true, child: child),
            ),
          ],
        );
    }
  }
}

class _Blocking extends StatelessWidget {
  const _Blocking({required this.icon, required this.title, required this.body, required this.action});

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Gap.xl),
          children: [
            const SizedBox(height: Gap.xl),
            LampEmpty(icon: icon, title: title, message: body, action: action),
          ],
        ),
      ),
    );
  }
}
