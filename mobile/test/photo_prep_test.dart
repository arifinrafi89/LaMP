import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lamp_shop/features/scan/photo_prep.dart';

/// Plan 5.5: before upload a photo's long side is at most 1,600 px, it is
/// re-saved as JPEG at quality 80, and its EXIF (with the location) is gone.
void main() {
  Uint8List jpeg(int w, int h, {int? orientation, bool gps = false}) {
    final image = img.Image(width: w, height: h);
    img.fill(image, color: img.ColorRgb8(200, 180, 160));
    if (orientation != null) image.exif.imageIfd.orientation = orientation;
    if (gps) {
      image.exif.gpsIfd['GPSLatitudeRef'] = img.IfdValueAscii('N');
      image.exif.imageIfd['Make'] = img.IfdValueAscii('Walton');
    }
    return img.encodeJpg(image, quality: 95);
  }

  img.Image read(Uint8List bytes) => img.decodeJpg(bytes)!;

  test('a wide photo comes down to 1,600 px across', () {
    final out = read(shrinkPhoto(jpeg(4000, 3000)));
    expect(out.width, 1600);
    expect(out.height, 1200);
  });

  test('a tall photo comes down to 1,600 px high', () {
    final out = read(shrinkPhoto(jpeg(3000, 4000)));
    expect(out.width, 1200);
    expect(out.height, 1600);
  });

  test('a small photo is not blown up', () {
    final out = read(shrinkPhoto(jpeg(1200, 800)));
    expect(out.width, 1200);
    expect(out.height, 800);
  });

  test('the EXIF data, location included, is removed', () {
    final source = jpeg(2000, 1500, gps: true);
    expect(read(source).exif.isEmpty, isFalse, reason: 'the test photo must carry EXIF');
    final out = read(shrinkPhoto(source));
    expect(out.exif.isEmpty, isTrue);
  });

  test('a photo taken with the phone turned stays upright', () {
    // Orientation 6: the camera saved it sideways and asked viewers to turn
    // it. With the EXIF gone, the turn has to be done to the pixels.
    final out = read(shrinkPhoto(jpeg(400, 200, orientation: 6)));
    expect(out.width, 200);
    expect(out.height, 400);
  });

  test('it is a JPEG at quality 80, so smaller than the original', () {
    final source = jpeg(1600, 1200);
    final out = shrinkPhoto(source);
    expect(out[0], 0xFF);
    expect(out[1], 0xD8);
    expect(out.length, lessThan(source.length));
  });

  test('bytes that are not a photo say so', () {
    expect(() => shrinkPhoto(Uint8List.fromList([1, 2, 3])), throwsA(isA<PhotoUnreadable>()));
  });
}
