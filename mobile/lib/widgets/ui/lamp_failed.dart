import 'package:material_ui/material_ui.dart';

import '../../core/api/problem.dart';
import '../../core/constants/palette.dart';
import '../../core/constants/typography.dart';
import '../../l10n/app_localizations.dart';

/// A screen with nothing to show because its read failed: the problem in
/// plain words, and a way to try again. Never a spinner forever, never a raw
/// error (plan 5.6).
class LampFailed extends StatelessWidget {
  const LampFailed({super.key, required this.problem, required this.onRetry});

  final ApiProblem problem;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.lamp;
    final l = L10n.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Gap.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(problem.code == ApiProblem.offline ? Icons.cloud_off_outlined : Icons.error_outline,
                size: IconSize.xl, color: c.inkMuted),
            const SizedBox(height: Gap.md),
            Text(problemMessage(l, problem),
                textAlign: TextAlign.center, style: LaMPType.body.copyWith(color: c.ink)),
            const SizedBox(height: Gap.lg),
            OutlinedButton(onPressed: onRetry, child: Text(l.retry)),
          ],
        ),
      ),
    );
  }
}
