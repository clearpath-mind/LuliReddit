import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../core/network/media_resolver.dart';

/// A feed video that autoplays (muted, looping) while it's on screen and pauses
/// when scrolled away. Tap opens the full-screen viewer (with sound).
///
/// Pass either a directly-playable [url] or a [resolver] that turns an external
/// host's watch page (RedGIFs, Streamable, …) into a playable source; the
/// poster is shown while that resolution is in flight.
class InlineVideo extends StatefulWidget {
  const InlineVideo({
    super.key,
    this.url,
    this.resolver,
    required this.height,
    required this.onTap,
    this.poster,
  }) : assert(url != null || resolver != null,
            'InlineVideo needs either a url or a resolver');

  final String? url;
  final Future<ResolvedMedia> Function()? resolver;
  final double height;
  final VoidCallback onTap;
  final String? poster;

  @override
  State<InlineVideo> createState() => _InlineVideoState();
}

class _InlineVideoState extends State<InlineVideo> {
  VideoPlayerController? _c;
  bool _ready = false;
  bool _muted = true;
  bool _visible = false;
  String? _stillImage; // resolution produced a still image (RedGIFs type-2)

  @override
  void initState() {
    super.initState();
    final url = widget.url;
    if (url != null && url.isNotEmpty) {
      _initPlayer(url);
    } else {
      _initFromResolver();
    }
  }

  Future<void> _initFromResolver() async {
    try {
      final resolved = await widget.resolver!();
      if (!mounted) return;
      if (resolved.isImage) {
        setState(() => _stillImage = resolved.url);
        return;
      }
      _initPlayer(resolved.url);
    } catch (_) {/* poster stays up */}
  }

  void _initPlayer(String url) {
    final c = VideoPlayerController.networkUrl(Uri.parse(url));
    _c = c;
    c.setLooping(true);
    c.setVolume(0);
    c.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      if (_visible) c.play();
    }).catchError((_) {});
  }

  void _onVisibility(VisibilityInfo info) {
    final visible = info.visibleFraction > 0.6;
    if (visible == _visible) return;
    _visible = visible;
    final c = _c;
    if (c == null || !_ready) return;
    visible ? c.play() : c.pause();
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return VisibilityDetector(
      key: Key('inlinevid_${widget.url ?? widget.poster}'),
      onVisibilityChanged: _onVisibility,
      child: GestureDetector(
        onTap: widget.onTap,
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_ready && c != null)
                FittedBox(
                  fit: BoxFit.cover,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(
                    width: c.value.size.width,
                    height: c.value.size.height,
                    child: VideoPlayer(c),
                  ),
                )
              else if (_stillImage != null || widget.poster != null)
                CachedNetworkImage(
                    imageUrl: _stillImage ?? widget.poster!,
                    fit: BoxFit.cover)
              else
                const ColoredBox(color: Colors.black12),
              if (!_ready && _stillImage == null)
                const Center(
                    child: SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(strokeWidth: 2))),
              // Mute / unmute toggle.
              if (_ready)
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _muted = !_muted);
                      c?.setVolume(_muted ? 0 : 1);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _muted
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
