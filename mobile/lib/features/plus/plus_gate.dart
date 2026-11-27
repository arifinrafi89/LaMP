import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/constants/palette.dart';
import '../../core/constants/typography.dart';
import '../../core/state/me.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/ui/lamp_skeleton.dart';
import '../../widgets/ui/lamp_ui.dart';

/// A LaMP Plus screen (plan 5.2). On the free plan it shows what the screen
/// does and one "Start LaMP Plus" button, never an error, and reads nothing.
///
/// - While `/me` is on its way (and nothing is kept), a skeleton.
/// - If `/me` can't be read at all, the screen tries anyway; the server's
///   `plus_required` then shows the same lock ([PlusLocked]).
class PlusGate extends StatelessWidget {
  const PlusGate({
    super.key,
    required this.title,
    required this.what,
    required this.icon,
    required this.allowed,
    required this.child,
  });

  final String title;
  final String what;
  final IconData icon;
  final bool Function(Entitlements) allowed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final me = context.watch<MeController>();
    final info = me.me;
    if (info == null && me.loading) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: ListView(padding: const EdgeInsets.all(Gap.lg), children: const [LampSkeletonCard(lines: 3)]),
      );
    }
    if (info != null && !allowed(info.entitlements)) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: PlusLocked(title: title, what: what, icon: icon),
      );
    }
    return child;
  }
}

/// What a Plus screen does, its price, and the one way in.
class PlusLocked extends StatelessWidget {
  const PlusLocked({super.key, required this.title, required this.what, required this.icon});

  final String title;
  final String what;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final c = context.lamp;
    return ListView(
      padding: const EdgeInsets.all(Gap.lg),
      children: [
        LampEmpty(
          icon: icon,
          title: l.plusLockedTitle(title),
          message: what,
          action: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l.plusPrice,
                textAlign: TextAlign.center,
                style: LaMPType.caption.copyWith(color: c.inkMuted),
              ),
              const SizedBox(height: Gap.md),
              ElevatedButton.icon(
                key: const ValueKey('plus-start'),
                onPressed: () => context.go('/plus'),
                style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                icon: const Icon(Icons.workspace_premium_outlined),
                label: Text(l.plusStart),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
