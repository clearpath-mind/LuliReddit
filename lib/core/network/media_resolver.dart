import 'package:dio/dio.dart';

import '../media_links.dart';

/// A resolved, directly-playable media source (mp4 URL or image) plus the
/// metadata viewers/feed cards need to render it well.
class ResolvedMedia {
  const ResolvedMedia({
    required this.url,
    this.poster,
    this.width,
    this.height,
    this.hasAudio = false,
    this.isImage = false,
    this.downloadUrl,
  });

  /// Directly playable video (mp4) URL, or the image URL when [isImage] is set.
  final String url;
  final String? poster;
  final int? width;
  final int? height;
  final bool hasAudio;

  /// True when the source is a still image (e.g. RedGIFs type-2 image posts).
  final bool isImage;

  /// Direct file for saving; defaults to [url] when null.
  final String? downloadUrl;

  String get saveUrl => downloadUrl ?? url;
}

/// Resolves external video URLs (RedGIFs, gfycat, Streamable, …) into
/// directly-playable mp4 sources using their public APIs.
///
/// RedGIFs requires a temporary token (bound to the User-Agent used to request
/// it) and a `Bearer` authorization header on every API call — same flow as the
/// Morphe "Fix Redgifs API" patches and yt-dlp's redgifs extractor.
class MediaResolver {
  MediaResolver({Dio? dio}) : _dio = dio ?? Dio();

  /// RedGIFs verifies that later requests use the User-Agent the token was
  /// issued to, so we keep one fixed value for all API/media calls.
  static const String userAgent =
      'Ilay for Reddit/1.0.36 (Android; com.bennybar.luli_for_reddit)';
  static const String _redgifsApiHost = 'https://api.redgifs.com';

  final Dio _dio;
  final Map<String, ResolvedMedia> _cache = {};

  // RedGIFs temporary token, cached for ~23h (they expire after 24h).
  String? _redgifsToken;
  DateTime? _redgifsTokenExpiry;
  static const Duration _tokenTtl = Duration(hours: 23);

  static bool isRedgifsUrl(Uri u) {
    final h = u.host.toLowerCase();
    return h == 'redgifs.com' || h.endsWith('.redgifs.com');
  }

  static bool isGfycatUrl(Uri u) {
    final h = u.host.toLowerCase();
    return h == 'gfycat.com' || h.endsWith('.gfycat.com');
  }

  static bool isStreamableUrl(Uri u) {
    final h = u.host.toLowerCase();
    return h == 'streamable.com' || h.endsWith('.streamable.com');
  }

  /// Resolves [url] to a playable source. Already-direct URLs (`.mp4`, `.gifv`,
  /// v.redd.it, …) are normalized and returned as-is. Results are cached in
  /// memory per URL. On any provider failure the original URL is returned so
  /// callers degrade to the existing behavior (viewer error + browser fallback).
  Future<ResolvedMedia> resolve(String url) async {
    final cached = _cache[url];
    if (cached != null) return cached;
    final uri = Uri.tryParse(url);
    if (uri == null) return ResolvedMedia(url: url);

    ResolvedMedia result;
    if (isRedgifsUrl(uri) || isGfycatUrl(uri)) {
      result = await _resolveRedgifs(uri);
    } else if (isStreamableUrl(uri)) {
      result = await _resolveStreamable(uri);
    } else {
      result = ResolvedMedia(url: resolveVideoUrl(url));
    }
    _cache[url] = result;
    return result;
  }

  /// Extracts the RedGIFs/gfycat id from any of their URL shapes:
  ///   redgifs.com/watch/{id} · redgifs.com/ifr/{id} · redgifs.com/{id}
  ///   thumbs2/3/4.redgifs.com/{id}.mp4 · gfycat.com/{id}
  static String? redgifsId(Uri u) {
    final segments = u.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return null;
    var id = segments.last;
    // CDN links carry a file extension: {Name}.mp4
    final dot = id.lastIndexOf('.');
    if (dot > 0) id = id.substring(0, dot);
    // RedGIFs/gfycat sometimes append a mobile variant suffix.
    if (id.toLowerCase().endsWith('-mobile')) {
      id = id.substring(0, id.length - '-mobile'.length);
    }
    if (id.isEmpty) return null;
    return id.toLowerCase();
  }

  Future<ResolvedMedia> _resolveRedgifs(Uri u) async {
    final id = redgifsId(u);
    if (id == null) return ResolvedMedia(url: u.toString());
    try {
      final token = await _redgifsAccessToken();
      final data = await _redgifsApi('/v2/gifs/$id', token,
          query: {'views': 'yes'});
      final gif = _asMap(data['gif']);
      if (gif.isEmpty) return ResolvedMedia(url: u.toString());
      final urls = _asMap(gif['urls']);
      final poster = urls['poster'] is String ? urls['poster'] as String : null;

      // type 2 = image post (single image, or a gallery of images).
      if (gif['type'] == 2) {
        final img = urls['hd'] ?? urls['poster'];
        return ResolvedMedia(
          url: img is String ? img : u.toString(),
          poster: poster,
          isImage: true,
          width: (gif['width'] as num?)?.toInt(),
          height: (gif['height'] as num?)?.toInt(),
        );
      }

      final hd = urls['hd'];
      final sd = urls['sd'];
      final video =
          (hd is String && hd.isNotEmpty) ? hd : (sd is String ? sd : null);
      if (video == null || video.isEmpty) return ResolvedMedia(url: u.toString());
      return ResolvedMedia(
        url: video,
        poster: poster,
        width: (gif['width'] as num?)?.toInt(),
        height: (gif['height'] as num?)?.toInt(),
        hasAudio: gif['hasAudio'] == true || gif['has_audio'] == true,
        downloadUrl: video,
      );
    } on DioException {
      return ResolvedMedia(url: u.toString());
    }
  }

  Future<ResolvedMedia> _resolveStreamable(Uri u) async {
    final segments = u.pathSegments.where((s) => s.isNotEmpty).toList();
    final id = segments.isEmpty ? null : segments.last;
    if (id == null) return ResolvedMedia(url: u.toString());
    try {
      final res = await _dio.get<dynamic>(
        'https://api.streamable.com/videos/$id',
        options: Options(headers: {'User-Agent': userAgent}),
      );
      final data = res.data;
      final map = _asMap(data);
      if (map.isEmpty) return ResolvedMedia(url: u.toString());
      final mp4 = _asMap(_asMap(map['files'])['mp4']);
      final video = mp4['url'];
      if (video is! String || video.isEmpty) return ResolvedMedia(url: u.toString());
      final thumb = map['thumbnail_url'];
      return ResolvedMedia(
        url: video,
        poster: thumb is String ? thumb : null,
        width: (mp4['width'] as num?)?.toInt(),
        height: (mp4['height'] as num?)?.toInt(),
        hasAudio: true,
        downloadUrl: video,
      );
    } on DioException {
      return ResolvedMedia(url: u.toString());
    }
  }

  /// Fetches (and caches) a RedGIFs temporary access token.
  Future<String> _redgifsAccessToken() async {
    final now = DateTime.now();
    if (_redgifsToken != null &&
        _redgifsTokenExpiry != null &&
        now.isBefore(_redgifsTokenExpiry!)) {
      return _redgifsToken!;
    }
    final res = await _dio.get<dynamic>(
      '$_redgifsApiHost/v2/auth/temporary',
      options: Options(headers: {
        'User-Agent': userAgent,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      }),
    );
    final token = _asMap(res.data)['token'];
    if (token is! String || token.isEmpty) {
      throw DioException(
        requestOptions: res.requestOptions,
        type: DioExceptionType.badResponse,
        error: 'Unable to retrieve a RedGIFs token',
      );
    }
    _redgifsToken = token;
    _redgifsTokenExpiry = now.add(_tokenTtl);
    return token;
  }

  /// Calls a RedGIFs API endpoint with the Bearer token, refreshing the token
  /// once when it comes back invalid (401).
  Future<Map<String, dynamic>> _redgifsApi(
    String path,
    String token, {
    Map<String, dynamic>? query,
  }) async {
    var attempts = 0;
    while (true) {
      try {
        final res = await _dio.get<dynamic>(
          '$_redgifsApiHost$path',
          queryParameters: query,
          options: Options(headers: {
            'Authorization': 'Bearer $token',
            'User-Agent': userAgent,
            'Referer': 'https://www.redgifs.com/',
            'Origin': 'https://www.redgifs.com',
            'Accept': 'application/json',
          }),
        );
        final map = _asMap(res.data);
        if (map.isEmpty) {
          throw DioException(
            requestOptions: res.requestOptions,
            type: DioExceptionType.badResponse,
            error: 'Unexpected RedGIFs response',
          );
        }
        return map;
      } on DioException catch (e) {
        if (attempts == 0 && e.response?.statusCode == 401) {
          // Token expired/invalidated — drop it and fetch a fresh one.
          attempts++;
          _redgifsToken = null;
          _redgifsTokenExpiry = null;
          token = await _redgifsAccessToken();
          continue;
        }
        rethrow;
      }
    }
  }

  static Map<String, dynamic> _asMap(dynamic v) => v is Map<String, dynamic>
      ? v
      : (v is Map ? Map<String, dynamic>.from(v) : const {});
}
