import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../../core/api/api_client.dart';
import '../../core/api/problem.dart';
import 'photo_prep.dart';
import 'photo_source.dart';
import 'scan_models.dart';

/// Where the owner is in a scan.
enum ScanStage { pick, preparing, preview, sending, review, saving, done }

/// The server's limit for one file (plan 2.2: 413 over 8 MB).
const maxUploadBytes = 8 * 1024 * 1024;

/// Drives Scan (plan 5.5): pick, shrink, preview, send, review, confirm.
///
/// - The photo gets one Idempotency-Key when it is picked, kept through
///   every send of it, so a slow network can't make a double scan or use up
///   two of the month's free scans. A new photo gets a new key.
/// - A failed send keeps the photo on screen; a failed save keeps the review.
class ScanController extends ChangeNotifier {
  ScanController(this._api, this._pid,
      {Future<Uint8List> Function(Uint8List)? shrink, VoidCallback? onSaved})
      : _shrink = shrink ?? shrinkPhotoInBackground,
        _onSaved = onSaved;

  final ApiClient _api;
  final String _pid;
  final Future<Uint8List> Function(Uint8List) _shrink;

  /// Told after a save, so other screens read their figures again.
  final VoidCallback? _onSaved;

  ScanStage _stage = ScanStage.pick;
  ScanStage get stage => _stage;

  /// What is being photographed. Chosen before the photo is taken.
  ScanKind kind = ScanKind.invoice;

  PickedFile? _file;

  /// The file as it will be sent: shrunk, for a photo.
  PickedFile? get file => _file;

  ScanReview? _review;
  ScanReview? get review => _review;

  ApiProblem? _problem;
  ApiProblem? get problem => _problem;

  int? _scansLeft;

  /// Free scans left this month; null on Plus, or when it couldn't be read.
  int? get scansLeft => _scansLeft;

  DateTime? _resetsOn;
  DateTime? get resetsOn => _resetsOn;

  String? _uploadKey;
  Future<PickedFile?> Function()? _lastPick;
  String? _confirmKey;
  bool _disposed = false;

  void setKind(ScanKind k) {
    kind = k;
    _notify();
  }

  /// Reads how many free scans are left. Failing is fine: the screen works
  /// without the count, and the server still enforces the limit.
  Future<void> loadUsage() async {
    try {
      final j = await _api.get('/pharmacies/$_pid/usage') as Map<String, dynamic>;
      final limit = j['scans_limit'];
      final used = j['scans_used'];
      _scansLeft = limit is num && used is num ? (limit - used).clamp(0, limit).toInt() : null;
      final r = j['resets_on'];
      _resetsOn = r is String ? DateTime.tryParse(r) : null;
    } on ApiProblem {
      _scansLeft = null;
    } on TypeError {
      _scansLeft = null;
    }
    _notify();
  }

  /// Picks a file with [pick] and gets it ready to send.
  Future<void> take(Future<PickedFile?> Function() pick) async {
    final before = _stage;
    _lastPick = pick;
    _stage = ScanStage.preparing;
    _problem = null;
    _notify();
    try {
      final picked = await pick();
      if (picked == null) {
        _stage = before == ScanStage.preparing ? ScanStage.pick : before;
        return;
      }
      final ready = picked.isPdf
          ? PickedFile(bytes: picked.bytes, name: 'bill.pdf', mime: 'application/pdf')
          : PickedFile(bytes: await _shrink(picked.bytes), name: 'bill.jpg', mime: 'image/jpeg');
      if (ready.bytes.length > maxUploadBytes) {
        _problem = const ApiProblem('too_large');
        _stage = ScanStage.pick;
        return;
      }
      _file = ready;
      _uploadKey = newUuid();
      _stage = ScanStage.preview;
    } on PhotoUnreadable {
      _problem = const ApiProblem('photo_unreadable');
      _stage = ScanStage.pick;
    } finally {
      _notify();
    }
  }

  /// Takes the photo again from where the last one came from.
  Future<void> retake() async {
    final pick = _lastPick;
    if (pick != null) await take(pick);
  }

  /// Sends the photo; the server reads it and sends back a draft.
  Future<void> send() async {
    final f = _file;
    if (f == null || _stage == ScanStage.sending) return;
    _stage = ScanStage.sending;
    _problem = null;
    _notify();
    try {
      final j = await _api.upload(
        '/pharmacies/$_pid/captures',
        fields: {'kind': kind.api},
        bytes: f.bytes,
        filename: f.name,
        contentType: f.mime,
        idempotencyKey: _uploadKey!,
      );
      final r = ScanReview.fromCapture(j as Map<String, dynamic>);
      _review = r;
      _confirmKey = newUuid();
      _stage = r.confirmed ? ScanStage.done : ScanStage.review;
    } on ApiProblem catch (p) {
      _problem = p;
      _stage = ScanStage.preview;
    } on Object catch (e) {
      // A draft the app can't read: keep the photo, say it plainly.
      debugPrint('LaMP: could not read the scan: $e');
      _problem = const ApiProblem('unknown');
      _stage = ScanStage.preview;
    } finally {
      _notify();
    }
  }

  void confirm(String path) {
    _review?.confirm(path);
    _notify();
  }

  void acknowledge(ReviewCheck c) {
    _review?.acknowledge(c);
    _notify();
  }

  /// The owner's correction. False when it doesn't fit the field.
  bool edit(String path, String typed) {
    final ok = _review?.edit(path, typed) ?? false;
    if (ok) _notify();
    return ok;
  }

  /// Saves the checked bill: stock, the supplier's bill and its due day.
  Future<bool> save() async {
    final r = _review;
    if (r == null || !r.canSave || _stage == ScanStage.saving) return false;
    _stage = ScanStage.saving;
    _problem = null;
    _notify();
    try {
      await _api.post('/pharmacies/$_pid/captures/${r.captureId}/confirm', r.toConfirmJson(),
          idempotencyKey: _confirmKey);
      _stage = ScanStage.done;
      _onSaved?.call();
      return true;
    } on ApiProblem catch (p) {
      _problem = p;
      _stage = ScanStage.review;
      return false;
    } finally {
      _notify();
    }
  }

  /// Back to the start, for the next bill or a retake.
  void startOver() {
    _stage = ScanStage.pick;
    _file = null;
    _review = null;
    _problem = null;
    _uploadKey = null;
    _confirmKey = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
