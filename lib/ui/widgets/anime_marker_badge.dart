import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../data/repositories/anime_marker_repository.dart';
import '../../l10n/app_localizations.dart';

/// Debug Pill to see what it resposnds for each epsiode.
const bool kAnimeMarkerDebug = false;

/// A badge for an episode card, shown only when there is something worth warning about:
/// filler, mixed canon/filler, or a recap. Everything else renders nothing at all, so a
/// mixed library of anime and ordinary shows is untouched outside the anime that matched.
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
  bool _pending = false;
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
      _pending = false;
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
      _pending = repository.isPending(seriesId);
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
      if (repository.isPending(seriesId)) {
        setState(() => _pending = true);
      }
      return;
    }

    setState(() => _marker = resolved);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scale = widget.scale;
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

      // The server knows this show but has not fetched its table yet, so markers really are
      // on the way. A series that matched nothing is not pending and stays silent.
      if (_pending) {
        return Padding(
          padding: widget.padding,
          child: _Pill(
            label: l10n.animeMarkerPending,
            color: const Color(0xFF8B949E),
            scale: scale,
          ),
        );
      }

      return const SizedBox.shrink();
    }

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
            // Both canon kinds are not noteworthy, so neither gets a pill. They stay
            // reachable because the episode may still be a recap or carry a dub.
            AnimeEpisodeKind.animeCanon ||
            AnimeEpisodeKind.mangaCanon => const SizedBox.shrink(),
            // The show is not on AnimeFillerList; only the audio verdict applies.
            null => const SizedBox.shrink(),
          },
          if (marker.recap)
            _Pill(
              label: l10n.animeMarkerRecap,
              color: const Color(0xFFFFA726),
              scale: scale,
            ),
          if (marker.audio case final audio?) animeAudioPill(l10n, audio, scale),
        ],
      ),
    );
  }
}

/// The subbed/dubbed pill, shared by the episode badge and the season badge.
Widget animeAudioPill(AppLocalizations l10n, AnimeAudioKind audio, double scale) {
  return switch (audio) {
    AnimeAudioKind.subbed => _Pill(
      label: l10n.animeMarkerSubbed,
      color: const Color(0xFF58A6FF),
      scale: scale,
    ),
    AnimeAudioKind.dubbed => _Pill(
      label: l10n.animeMarkerDubbed,
      color: const Color(0xFF3FB950),
      scale: scale,
    ),
  };
}

/// A subbed/dubbed pill for a whole season, for the season list.
///
/// Shows nothing unless every episode in the season agreed, so a season holding both a dub
/// and a sub stays blank.
class AnimeSeasonAudioBadge extends StatefulWidget {
  final String? seriesId;
  final String seasonId;
  final double scale;
  final EdgeInsetsGeometry padding;

  const AnimeSeasonAudioBadge({
    super.key,
    required this.seriesId,
    required this.seasonId,
    this.scale = 1.0,
    this.padding = EdgeInsets.zero,
  });

  @override
  State<AnimeSeasonAudioBadge> createState() => _AnimeSeasonAudioBadgeState();
}

class _AnimeSeasonAudioBadgeState extends State<AnimeSeasonAudioBadge> {
  AnimeAudioKind? _audio;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(AnimeSeasonAudioBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seasonId != widget.seasonId ||
        oldWidget.seriesId != widget.seriesId) {
      _audio = null;
      _load();
    }
  }

  Future<void> _load() async {
    final seriesId = widget.seriesId;
    if (seriesId == null || seriesId.isEmpty) return;
    if (!GetIt.instance.isRegistered<AnimeMarkerRepository>()) return;

    final repository = GetIt.instance<AnimeMarkerRepository>();

    final cached = repository.peekSeason(
      seriesId: seriesId,
      seasonId: widget.seasonId,
    );
    if (cached != null) {
      _audio = cached;
      return;
    }

    if (repository.isResolved(seriesId)) return;

    await repository.getForSeries(seriesId);
    if (!mounted) return;

    final resolved = repository.peekSeason(
      seriesId: seriesId,
      seasonId: widget.seasonId,
    );
    if (resolved == null) return;

    setState(() => _audio = resolved);
  }

  @override
  Widget build(BuildContext context) {
    final audio = _audio;
    if (audio == null) return const SizedBox.shrink();

    return Padding(
      padding: widget.padding,
      child: animeAudioPill(AppLocalizations.of(context), audio, widget.scale),
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
