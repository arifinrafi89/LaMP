import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import 'photo_prep.dart';

/// A photo or PDF the owner picked, read into memory.
class PickedFile {
  const PickedFile({required this.bytes, required this.name, required this.mime});

  final Uint8List bytes;
  final String name;

  /// `image/jpeg`, `image/png`, `application/pdf`, …
  final String mime;

  bool get isPdf => mime == 'application/pdf';
}

/// Where a bill comes from (plan 5.5). Tests give their own.
abstract class PhotoSource {
  /// Null when the owner backs out.
  Future<PickedFile?> camera();
  Future<PickedFile?> gallery();
  Future<PickedFile?> pdf();
}

/// The phone's camera and gallery (`image_picker`) and its files
/// (`file_picker`). On web the camera opens the browser's own picker.
class DevicePhotoSource implements PhotoSource {
  DevicePhotoSource([ImagePicker? picker]) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  // The picker resizes natively first, so a cheap phone never decodes all
  // 12 megapixels in Dart; shrinkPhoto then strips EXIF and sets quality.
  Future<PickedFile?> _image(ImageSource source) async {
    final x = await _picker.pickImage(
      source: source,
      maxWidth: maxPhotoSide.toDouble(),
      maxHeight: maxPhotoSide.toDouble(),
      imageQuality: 95,
      requestFullMetadata: false,
    );
    if (x == null) return null;
    return PickedFile(bytes: await x.readAsBytes(), name: x.name, mime: x.mimeType ?? 'image/jpeg');
  }

  @override
  Future<PickedFile?> camera() => _image(ImageSource.camera);

  @override
  Future<PickedFile?> gallery() => _image(ImageSource.gallery);

  @override
  Future<PickedFile?> pdf() async {
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf']);
    if (files.isEmpty) return null;
    final f = files.first;
    return PickedFile(bytes: await f.readAsBytes(), name: f.name, mime: 'application/pdf');
  }
}
