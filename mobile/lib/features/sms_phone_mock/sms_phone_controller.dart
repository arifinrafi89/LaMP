import 'package:material_ui/material_ui.dart';

import '../../core/api/api_client.dart';
import '../../core/api/problem.dart';

/// One SMS between the drawn phone and 21213.
class DemoMessage {
  const DemoMessage({required this.fromPhone, required this.text, this.at});

  /// Texted from the phone; otherwise LaMP's message to it.
  final bool fromPhone;
  final String text;
  final DateTime? at;

  /// Read tolerantly: `from` (`phone` or `lamp`) or `direction` (`in` is the
  /// phone's text, as Applink calls an incoming SMS).
  factory DemoMessage.fromJson(Map<String, dynamic> j) {
    final from = j['from'] ?? j['direction'];
    return DemoMessage(
      fromPhone: from == 'phone' || from == 'family' || from == 'in' || from == 'mo',
      text: (j['text'] as String?) ?? '',
      at: DateTime.tryParse((j['at'] as String?) ?? ''),
    );
  }
}

/// The drawn phone (plan 5.7): `POST /demo/sms` runs Arifin's real SMS
/// command code against the demo shop; `GET /demo/sms/thread` lists every
/// message to and from the phone, including what the owner triggers.
class SmsPhoneController extends ChangeNotifier {
  SmsPhoneController(this._api, {VoidCallback? onSent, Listenable? refreshOn})
    : _onSent = onSent,
      _refreshOn = refreshOn {
    _refreshOn?.addListener(load);
  }

  final ApiClient _api;
  final VoidCallback? _onSent;

  /// The owner's own changes (a plan, a payment) send SMS here too.
  final Listenable? _refreshOn;

  List<DemoMessage> _thread = const [];
  List<DemoMessage> get thread => _thread;

  bool _loaded = false;
  bool get loaded => _loaded;

  bool _sending = false;
  bool get sending => _sending;

  ApiProblem? _problem;
  ApiProblem? get problem => _problem;

  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    try {
      final j = await _api.get('/demo/sms/thread');
      final list = j is Map ? j['messages'] : j;
      _thread = [for (final m in (list as List?) ?? const []) DemoMessage.fromJson(m as Map<String, dynamic>)];
      _loaded = true;
      _problem = null;
    } on ApiProblem catch (p) {
      _problem = p;
    } on Object catch (e) {
      debugPrint('LaMP phone: could not read the thread: $e');
    }
    _notify();
  }

  /// Sends [text] as if texted to 21213; true when it went.
  Future<bool> send(String text) async {
    final t = text.trim();
    if (t.isEmpty || _sending) return false;
    _sending = true;
    _problem = null;
    _notify();
    try {
      final j = await _api.post('/demo/sms', {'text': t});
      final replies = j is Map ? (j['replies'] as List?) ?? const [] : const [];
      _thread = [
        ..._thread,
        DemoMessage(fromPhone: true, text: t),
        for (final r in replies) DemoMessage(fromPhone: false, text: r is Map ? (r['text'] as String? ?? '') : '$r'),
      ];
      _sending = false;
      _notify();
      // The Customers screen shows "Joining" or a new plan at once.
      _onSent?.call();
      return true;
    } on ApiProblem catch (p) {
      _problem = p;
      _sending = false;
      _notify();
      return false;
    }
  }

  @override
  void dispose() {
    _refreshOn?.removeListener(load);
    _disposed = true;
    super.dispose();
  }
}
