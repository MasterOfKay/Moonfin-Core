import 'dart:async';

import 'package:dio/dio.dart';
import 'package:server_core/server_core.dart';

/// Filler and recap markers for a single episode.
class EpisodeFillerFlags {
  final bool filler;
  final bool recap;

  const EpisodeFillerFlags({required this.filler, required this.recap});

  bool get hasAny => filler || recap;
}

/// Fetches anime filler/recap markers from the Moonbase plugin.
class AnimeFillerRepository {
  static const _maxCacheEntries = 32;

  /// Failed lookups are remembered briefly so a list of episode cards cannot
  /// overflood the plugin while nothing can succeed.
  static const _negativeCacheTtl = Duration(minutes: 3);

  /// A 404 means the route is missing (plugin absent, or older than this
  /// feature).
  static const _unavailableRetryWindow = Duration(minutes: 10);

  final MediaServerClient _client;
  final _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 60),
    ),
  );

  final _cache = <String, Map<String, EpisodeFillerFlags>>{};
  final _pending = <String, Completer<Map<String, EpisodeFillerFlags>?>>{};
  final _negativeCache = <String, DateTime>{};
  DateTime? _unavailableSince;

  AnimeFillerRepository(this._client);

  /// Returns the flags for a single episode if they are already cached, or null
  /// if they are not. This is useful for cards that want to a peeka boo at the flags
  /// without triggering a network request.
  EpisodeFillerFlags? peek({
    required String seriesId,
    required String episodeId,
  }) {
    return _cache[seriesId]?[episodeId.toLowerCase()];
  }

  /// True once a series has been looked up, successfully or not, so a card can
  /// tell "no markers" apart from "not asked yet".
  bool isResolved(String seriesId) =>
      _cache.containsKey(seriesId) ||
      _negativeCache.containsKey(seriesId) ||
      _unavailableSince != null;

  Future<Map<String, EpisodeFillerFlags>?> getForSeries(String seriesId) async {
    if (seriesId.isEmpty) return null;

    if (_unavailableSince != null) {
      if (DateTime.now().difference(_unavailableSince!) <
          _unavailableRetryWindow) {
        return null;
      }
      _unavailableSince = null;
    }

    final cached = _takeCached(seriesId);
    if (cached != null) return cached;

    final negativeAt = _negativeCache[seriesId];
    if (negativeAt != null) {
      if (DateTime.now().difference(negativeAt) < _negativeCacheTtl) {
        return null;
      }
      _negativeCache.remove(seriesId);
    }

    final existing = _pending[seriesId];
    if (existing != null) return existing.future;

    final completer = Completer<Map<String, EpisodeFillerFlags>?>();
    _pending[seriesId] = completer;

    Map<String, EpisodeFillerFlags>? completeWith(
      Map<String, EpisodeFillerFlags>? value,
    ) {
      completer.complete(value);
      _pending.remove(seriesId);
      return value;
    }

    try {
      final token = _client.accessToken;
      if (token == null) return completeWith(null);

      final response = await _dio.get(
        '${_client.baseUrl}/Moonfin/AnimeFiller/Series',
        queryParameters: {'seriesId': seriesId},
        options: Options(
          headers: {'Authorization': 'MediaBrowser Token="$token"'},
        ),
      );

      final data = response.data;
      if (data is! Map<String, dynamic>) {
        _negativeCache[seriesId] = DateTime.now();
        return completeWith(null);
      }

      // The admin can switch the feature off server-wide. Cache the empty
      // result so cards stop asking rather than retrying every series.
      if (data['enabled'] != true) {
        _storeCacheEntry(seriesId, const {});
        return completeWith(const {});
      }

      final rawEpisodes = data['episodes'];
      final flags = <String, EpisodeFillerFlags>{};

      if (rawEpisodes is Map) {
        rawEpisodes.forEach((key, value) {
          if (key is! String || value is! Map) return;
          final filler = value['filler'] == true;
          final recap = value['recap'] == true;
          if (!filler && !recap) return;
          flags[key.toLowerCase()] = EpisodeFillerFlags(
            filler: filler,
            recap: recap,
          );
        });
      }

      _storeCacheEntry(seriesId, flags);
      return completeWith(flags);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        // A 404 means the plugin is not present or does not support this feature.
        final body = e.response?.data;
        final answeredByPlugin = body is Map && body['error'] != null;

        if (answeredByPlugin) {
          _negativeCache[seriesId] = DateTime.now();
        } else {
          _unavailableSince = DateTime.now();
        }
      } else {
        _negativeCache[seriesId] = DateTime.now();
      }
      return completeWith(null);
    } catch (_) {
      _negativeCache[seriesId] = DateTime.now();
      return completeWith(null);
    }
  }

  void clearCache() {
    _cache.clear();
    _negativeCache.clear();
    _unavailableSince = null;
  }

  void dispose() {
    clearCache();
    _dio.close(force: true);
  }

  Map<String, EpisodeFillerFlags>? _takeCached(String seriesId) {
    final cached = _cache.remove(seriesId);
    if (cached != null) {
      // Re-inserting keeps the map in least-recently-used order.
      _cache[seriesId] = cached;
    }
    return cached;
  }

  void _storeCacheEntry(String seriesId, Map<String, EpisodeFillerFlags> flags) {
    _cache.remove(seriesId);
    _cache[seriesId] = flags;
    while (_cache.length > _maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
  }
}
