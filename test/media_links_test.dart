import 'package:flutter_test/flutter_test.dart';
import 'package:luli_for_reddit/core/media_links.dart';
import 'package:luli_for_reddit/core/network/media_resolver.dart';

void main() {
  group('external video host detection', () {
    test('isExternalVideoHost recognizes redgifs / gfycat / streamable', () {
      expect(isExternalVideoHost(Uri.parse('https://www.redgifs.com/watch/abc')),
          isTrue);
      expect(isExternalVideoHost(Uri.parse('https://thumbs3.redgifs.com/Abc.mp4')),
          isTrue);
      expect(isExternalVideoHost(Uri.parse('https://gfycat.com/AbcDef')), isTrue);
      expect(isExternalVideoHost(Uri.parse('https://streamable.com/abcd12')),
          isTrue);
      expect(isExternalVideoHost(Uri.parse('https://v.redd.it/xyz')), isFalse);
      expect(isExternalVideoHost(Uri.parse('https://i.imgur.com/a.png')), isFalse);
    });

    test('isVideoUrl includes external hosts and direct mp4', () {
      expect(isVideoUrl(Uri.parse('https://www.redgifs.com/watch/abc')), isTrue);
      expect(isVideoUrl(Uri.parse('https://streamable.com/abcd12')), isTrue);
      expect(isVideoUrl(Uri.parse('https://example.com/v.mp4')), isTrue);
      expect(isVideoUrl(Uri.parse('https://example.com/pic.png')), isFalse);
    });

    test('resolveVideoUrl converts .gifv to .mp4', () {
      expect(resolveVideoUrl('https://i.imgur.com/x.gifv'),
          'https://i.imgur.com/x.mp4');
      expect(resolveVideoUrl('https://example.com/v.mp4'),
          'https://example.com/v.mp4');
    });
  });

  group('MediaResolver.redgifsId', () {
    test('parses watch / ifr / bare / CDN / gfycat URLs', () {
      expect(MediaResolver.redgifsId(Uri.parse('https://www.redgifs.com/watch/SqueakyHelplessWisent')),
          'squeakyhelplesswisent');
      expect(MediaResolver.redgifsId(Uri.parse('https://redgifs.com/ifr/SqueakyHelplessWisent')),
          'squeakyhelplesswisent');
      expect(MediaResolver.redgifsId(Uri.parse('https://redgifs.com/SqueakyHelplessWisent')),
          'squeakyhelplesswisent');
      expect(MediaResolver.redgifsId(Uri.parse('https://thumbs2.redgifs.com/SqueakyHelplessWisent-mobile.mp4')),
          'squeakyhelplesswisent');
      expect(MediaResolver.redgifsId(Uri.parse('https://gfycat.com/SqueakyHelplessWisent')),
          'squeakyhelplesswisent');
    });
  });
}
