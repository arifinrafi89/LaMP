import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/api/api_client.dart';
import '../../core/api/chat_stream.dart';
import '../../core/api/problem.dart';

/// How an answer ended.
enum AskEnd {
  streaming,
  done,

  /// The server said it couldn't answer, or refused (budget, Plus).
  failed,

  /// The stream stopped before its finish, or went silent: never passed
  /// off as an answer (plan 9.7, "Lost connection; ask again").
  lost,
}

/// One turn: the owner's question, or LaMP's answer to it.
class AskTurn {
  AskTurn.question(this.text) : mine = true, question = text;
  AskTurn.answer(this.question) : mine = false, text = '';

  final bool mine;

  /// For an answer, what it answers (Ask again sends it again).
  final String question;
  String text;

  /// The server's names for what LaMP looked up, in order (`get_forecast`).
  final List<String> tools = [];

  AskEnd end = AskEnd.streaming;
  ApiProblem? problem;

  /// Every money figure was traced to the books (the guard's data-trace).
  bool checked = false;

  /// The guard held the answer back; the text is its safe reply.
  bool held = false;

  /// LaMP put a step in Approvals.
  bool proposed = false;
}

/// Ask (plan 5.3): `POST /chat` with the conversation so far, read as it
/// streams. One question at a time. Kept in memory only: the conversation
/// may hold the shop's figures.
class AskController extends ChangeNotifier {
  AskController(
    this._api, {
    required String Function() language,
    VoidCallback? onProposed,
    this.silence = const Duration(seconds: 60),
  }) : _language = language,
       _onProposed = onProposed;

  final ApiClient _api;
  final String Function() _language;
  final VoidCallback? _onProposed;

  /// No bytes for this long: the connection is taken as lost.
  final Duration silence;

  final String _chatId = newUuid();
  final List<AskTurn> _turns = [];
  List<AskTurn> get turns => List.unmodifiable(_turns);

  bool _busy = false;
  bool get busy => _busy;

  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// The conversation the server sees: questions and the answers that
  /// finished. A question whose answer failed or was lost is left out.
  List<Map<String, Object?>> _history() {
    final out = <Map<String, Object?>>[];
    for (var i = 0; i + 1 < _turns.length; i += 2) {
      final q = _turns[i], a = _turns[i + 1];
      if (a.end != AskEnd.done) continue;
      out
        ..add(_message('user', q.text))
        ..add(_message('assistant', a.text));
    }
    return out;
  }

  static Map<String, Object?> _message(String role, String text) => {
    'id': newUuid(),
    'role': role,
    'parts': [
      {'type': 'text', 'text': text},
    ],
  };

  Future<void> ask(String question) async {
    final q = question.trim();
    if (q.isEmpty || _busy) return;
    final body = {
      'trigger': 'submit-message',
      'id': _chatId,
      'messages': [..._history(), _message('user', q)],
      'lang': _language(),
    };
    final answer = AskTurn.answer(q);
    _turns
      ..add(AskTurn.question(q))
      ..add(answer);
    _busy = true;
    _notify();
    try {
      final bytes = await _api.stream('/chat', body);
      await for (final e in parseChatStream(bytes.timeout(silence))) {
        switch (e) {
          case ChatText(:final delta):
            answer.text += delta;
          case ChatToolStarted(:final name):
            answer.tools.add(name);
            if (name == 'propose_action') answer.proposed = true;
          case ChatToolDone():
            break;
          case ChatTrace(:final traced, :final blocked):
            answer.held = blocked;
            answer.checked = !blocked && traced > 0;
          case ChatFinished():
            answer.end = AskEnd.done;
          case ChatFailed():
            answer.end = AskEnd.failed;
        }
        _notify();
      }
      if (answer.end == AskEnd.streaming) answer.end = AskEnd.lost;
    } on ApiProblem catch (p) {
      answer
        ..problem = p
        ..end = p.code == ApiProblem.offline ? AskEnd.lost : AskEnd.failed;
    } on TimeoutException {
      answer.end = AskEnd.lost;
    } on Object catch (e) {
      // A connection dropped mid-answer surfaces here as a client error.
      debugPrint('LaMP ask: $e');
      answer.end = AskEnd.lost;
    } finally {
      _busy = false;
      _notify();
    }
    if (answer.proposed && answer.end == AskEnd.done) _onProposed?.call();
  }

  /// Sends the last question again, in place of its failed answer.
  Future<void> askAgain() async {
    if (_busy || _turns.length < 2 || _turns.last.end == AskEnd.done) return;
    final q = _turns.last.question;
    _turns.removeRange(_turns.length - 2, _turns.length);
    await ask(q);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
