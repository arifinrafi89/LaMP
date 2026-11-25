# What `mobile/` took from lamp-flutter

The LaMP shop app in `mobile/` was started on 25 Nov 2026 during AppQuest 2.0.
Its design system comes from the team's earlier Flutter app,
[`ishmam259/lamp-flutter`](https://github.com/ishmam259/lamp-flutter) at
commit `cf5d520`. That repository is a reference only: nothing was pushed to it.

## Copied once, unchanged

Apart from one mechanical edit (below), these files are byte-for-byte copies.

| In `mobile/` | What it is |
|---|---|
| `lib/core/constants/palette.dart`, `typography.dart` | Colour tokens (`LampPalette`, `context.lamp`, `Gap`, `IconSize`, `LampWorld`) and the type scale (`LaMPType`, `LaMPRadius`) |
| `lib/core/constants/app_theme.dart`, `formatters.dart`, `app_mode.dart` | Theme, number and date formats, demo-tools switch (to be adapted, see the build plan 5.1) |
| `lib/core/design/luma_*.dart` (8 files) | Auto grid, container query, elevation, frost, motion, press, sheet, toast |
| `lib/core/state/theme_controller.dart` | Light/dark/system theme choice |
| `lib/widgets/lamp_mark.dart`, `theme_toggle.dart` | Logo mark, theme switch |
| `lib/widgets/ui/lamp_ui.dart`, `lamp_skeleton.dart` | Cards, rows, chips, stats, empty states, loading skeletons |
| `test/design_lint_test.dart`, `test/luma_design_test.dart` | Design-system guards |
| `analysis_options.yaml` | Lint settings |
| `assets/fonts/` | Anek Latin, Anek Bangla, IBM Plex Mono (SIL Open Font Licence, `Anek-OFL.txt`) |
| `assets/images/logo-*.png`, `assets/app_icon/` | Logo and launcher-icon masters |
| `docs/luma-ui.md` | Design-layer reference |

## Edits made while copying

- Flutter 3.50 deprecates `package:flutter/material.dart` in favour of the
  `material_ui` package, so every copied `import 'package:flutter/material.dart'`
  became `import 'package:material_ui/material_ui.dart'`. Nothing else changed.
- `analysis_options.yaml`: the `design_handoff_*` exclude was dropped (those
  folders were not copied), and `prefer_initializing_formals` is off so
  `luma_auto_grid.dart` stays as written.

## Left behind

The ledger, world, invoice and Firebase code, the old role screens, their
tests, and the ledger photos. The full list is in the build plan, section 5.1.

Everything else in `mobile/` is new work.
