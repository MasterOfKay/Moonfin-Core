import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../data/repositories/anime_filler_repository.dart';
import '../../l10n/app_localizations.dart';

/// Small pill marking an anime episode as filler or recap.
class FillerBadge extends StatelessWidget {
  final EpisodeFillerFlags flags;

  /// Scales with the surrounding card so the badge does not take the full space on TV.
  final double scale;

  const FillerBadge({super.key, required this.flags, this.scale = 1.0});

  @override
  Widget build(BuildContext context) {
    if (!flags.hasAny) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);

    return Wrap(
      spacing: 4 * scale,
      runSpacing: 2 * scale,
      children: [
        if (flags.filler)
          _Pill(
            label: l10n.fillerBadge,
            color: const Color(0xFFE53935),
            scale: scale,
          ),
        if (flags.recap)
          _Pill(
            label: l10n.recapBadge,
            color: const Color(0xFFFFA726),
            scale: scale,
          ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  final double scale;

  const _Pill({required this.label, required this.color, required this.scale});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 2 * scale),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: AppRadius.circular(4 * scale),
        border: Border.all(color: color.withValues(alpha: 0.7), width: 1),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10 * scale,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
