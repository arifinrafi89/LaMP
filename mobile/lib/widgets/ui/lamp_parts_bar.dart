import 'package:material_ui/material_ui.dart';

import '../../core/constants/palette.dart';

/// One segment per part of a payment plan, paid ones filled (adapted from
/// lamp-flutter's `LampTickBar`). A count of real parts, never a percentage.
/// The words beside it carry the meaning; the colour only repeats it.
class LampPartsBar extends StatelessWidget {
  const LampPartsBar({super.key, required this.parts, required this.paid});

  final int parts;
  final int paid;

  @override
  Widget build(BuildContext context) {
    final c = context.lamp;
    return Row(
      children: [
        for (var i = 0; i < parts; i++) ...[
          if (i > 0) const SizedBox(width: 2),
          Expanded(
            child: Container(
              height: 12,
              decoration: BoxDecoration(
                color: i < paid ? c.verified : c.surfaceSunken,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
