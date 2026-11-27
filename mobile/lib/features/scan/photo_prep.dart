
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Plan 5.5: the longest side a bill photo is sent at.
const maxPhotoSide = 1600;

/// The JPEG quality a bill photo is re-saved at.
const photoQuality = 80;

/// The bytes picked were not a photo the app can read.
class PhotoUnreadable implements Exception {
  const PhotoUnreadable();
}

/// Makes a photo ready to send (plan 5.5):
///
/// - its long side comes down to [maxPhotoSide], never up;
/// - it is turned upright first, because the camera's turn is an EXIF tag;
/// - it is re-saved as JPEG at [photoQuality] with no EXIF, which drops the
///   phone's location and make.
///
/// The server checks size, type and pixels again and re-encodes the image.
Uint8List shrinkPhoto(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const PhotoUnreadable();
  var image = img.bakeOrientation(decoded);
  final long = image.width > image.height ? image.width : image.height;
  if (long > maxPhotoSide) {
    image = image.width >= image.height
        ? img.copyResize(image, width: maxPhotoSide, interpolation: img.Interpolation.average)
        : img.copyResize(image, height: maxPhotoSide, interpolation: img.Interpolation.average);
  }
  image.exif.clear();
  return img.encodeJpg(image, quality: photoQuality);
}

/// How a photo is made ready; tests pass one that doesn't need an isolate.
typedef ShrinkPhoto = Future<Uint8List> Function(Uint8List bytes);

/// [shrinkPhoto] off the UI thread, so the screen keeps moving while a
/// 12-megapixel photo is decoded on a cheap phone.
Future<Uint8List> shrinkPhotoInBackground(Uint8List bytes) => compute(shrinkPhoto, bytes);
