import 'package:material_ui/material_ui.dart';

import '../../core/constants/palette.dart';
import '../../widgets/lamp_mark.dart';

/// The moment between launch and knowing who is signed in.
class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: context.lamp.bg,
        body: const Center(child: LampMark(size: 72)),
      );
}
