import 'package:material_ui/material_ui.dart';

import '../../core/api/problem.dart';
import '../../core/constants/palette.dart';
import '../../core/constants/typography.dart';
import '../../core/l10n/digits.dart';
import '../../l10n/app_localizations.dart';

/// How fresh the screen is (plan 5.6): "Updated 10:42", or
/// "Offline · updated 10:42" when it is showing what the phone kept.
/// Times are Dhaka's; an earlier day shows the day instead.
class LampSyncPip extends StatelessWidget {
  const LampSyncPip({super.key, required this.savedAt, this.problem, this.now});

  final DateTime savedAt;

  /// Why the last refresh failed, if it did.
  final ApiProblem? problem;

  /// For tests; the phone's clock otherwise.
  final DateTime? now;

  static DateTime _dhaka(DateTime t) => t.toUtc().add(const Duration(hours: 6));

  String _when(bool bn) {
    final at = _dhaka(savedAt);
    final today = dhakaToday(now);
    if (at.year != today.year || at.month != today.month || at.day != today.day) {
      return formatDay(DateTime(at.year, at.month, at.day), bangla: bn);
    }
    final hm = '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    return bn ? bnDigits(hm) : hm;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.lamp;
    final l = L10n.of(context);
    final when = _when(isBangla(context));
    final p = problem;
    final offline = p?.code == ApiProblem.offline;
    final text = p == null
        ? l.syncUpdated(when)
        : offline
            ? l.syncOffline(when)
            : l.syncStale(when);
    final color = p == null ? c.inkFaint : c.pending;
    return Semantics(
      liveRegion: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(p == null ? Icons.check_circle_outline : offline ? Icons.cloud_off_outlined : Icons.sync_problem,
              size: IconSize.sm, color: color),
          const SizedBox(width: Gap.xs),
          Flexible(child: Text(text, style: LaMPType.caption.copyWith(color: color))),
        ],
      ),
    );
  }
}
