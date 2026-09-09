import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../data/repositories/anime_marker_repository.dart';
import '../../l10n/app_localizations.dart';

/// Pill rendering for a epsiode card.
const bool kAnimeMarkerDebug = true;

/// A badge for an episode card that shows whether the episode is filler, recap, or anime canon.
class AnimeMarkerBadge extends StatefulWidget {
  final String? seriesId;
  final String episodeId;

  /// Scales with the surrounding card so the pills do not dominate on TV.
  final double scale;

  /// Applied only when a pill actually renders, so an episode with no marker.
  final EdgeInsetsGeometry padding;

  const AnimeMarkerBadge({
    super.key,
    required this.seriesId,
    required this.episodeId,
    this.scale = 1.0,
    this.padding = EdgeInsets.zero,
  });

  @override
  State<AnimeMarkerBadge> createState() => _AnimeMarkerBadgeState();
}

class _AnimeMarkerBadgeState extends State<AnimeMarkerBadge> {
  AnimeEpisodeMarker? _marker;
  String? _debugReason;

  void _note(String reason) {
    if (!kAnimeMarkerDebug) return;

    _debugReason = reason;
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(AnimeMarkerBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Episode cards are recycled while scrolling, so a new episode in the same
    // widget slot has to drop the previous episode's pill.
    if (oldWidget.episodeId != widget.episodeId ||
        oldWidget.seriesId != widget.seriesId) {
      _marker = null;
      _load();
    }
  }

  Future<void> _load() async {
    final seriesId = widget.seriesId;
    if (seriesId == null || seriesId.isEmpty) {
      _note('no-seriesId');
      return;
    }

    if (!GetIt.instance.isRegistered<AnimeMarkerRepository>()) {
      _note('no-repo');
      return;
    }
    final repository = GetIt.instance<AnimeMarkerRepository>();

    final cached = repository.peek(
      seriesId: seriesId,
      episodeId: widget.episodeId,
    );
    if (cached != null) {
      _marker = cached;
      return;
    }

    // Already looked up and this episode carries no marker, or the plugin is unavailable.
    if (repository.isResolved(seriesId)) {
      _note('resolved:${repository.lastDiagnostic ?? "no-marker"}');
      return;
    }

    await repository.getForSeries(seriesId);
    if (!mounted) return;

    // Read back through peek so id normalisation stays in the repository.
    final resolved = repository.peek(
      seriesId: seriesId,
      episodeId: widget.episodeId,
    );
    if (resolved == null) {
      _note(repository.lastDiagnostic ?? 'no-marker');
      return;
    }

    setState(() => _marker = resolved);
  }

  @override
  Widget build(BuildContext context) {
    final marker = _marker;
    if (marker == null || !marker.isNoteworthy) {
      if (kAnimeMarkerDebug && _debugReason != null) {
        return Padding(
          padding: widget.padding,
          child: _Pill(
            label: _debugReason!,
            color: const Color(0xFF8B949E),
            scale: widget.scale,
          ),
        );
      }
      return const SizedBox.shrink();
    }

    final l10n = AppLocalizations.of(context);
    final scale = widget.scale;

    return Padding(
      padding: widget.padding,
      child: Wrap(
        spacing: 4 * scale,
        runSpacing: 2 * scale,
        children: [
          switch (marker.kind) {
            AnimeEpisodeKind.filler => _Pill(
              label: l10n.animeMarkerFiller,
              color: const Color(0xFFE53935),
              scale: scale,
            ),
            AnimeEpisodeKind.mixed => _Pill(
              label: l10n.animeMarkerMixed,
              color: const Color(0xFFD29922),
              scale: scale,
            ),
            AnimeEpisodeKind.animeCanon => _Pill(
              label: l10n.animeMarkerAnimeCanon,
              color: const Color(0xFF3FB950),
              scale: scale,
            ),
            // Manga canon is the ordinary case and is filtered out by
            // isNoteworthy, but a recap can still carry it here.
            AnimeEpisodeKind.mangaCanon => const SizedBox.shrink(),
          },
          if (marker.recap)
            _Pill(
              label: l10n.animeMarkerRecap,
              color: const Color(0xFFFFA726),
              scale: scale,
            ),
        ],
      ),
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
