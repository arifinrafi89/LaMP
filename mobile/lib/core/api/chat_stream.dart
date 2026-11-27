import 'dart:async';
import 'dart:convert';

/// What `POST /chat` streams back (plan 5.3): the Vercel AI SDK UI message
/// stream, `data: {json}` events ending with `data: [DONE]`.
sealed class ChatEvent {
  const ChatEvent();
}

/// A piece of the answer's text.
class ChatText extends ChatEvent {
  const ChatText(this.delta);
  final String delta;
}

/// LaMP started looking something up (a tool), named by the server.
class ChatToolStarted extends ChatEvent {
  const ChatToolStarted(this.id, this.name);
  final String id;
  final String name;
}

class ChatToolDone extends ChatEvent {
  const ChatToolDone(this.id, this.output);
  final String id;
  final Object? output;
}

/// The money-figure guard's verdict on the answer.
class ChatTrace extends ChatEvent {
  const ChatTrace(this.traced, this.total, this.blocked);
  final int traced;
  final int total;

  /// A figure didn't match the books: the server sent its safe reply instead.
  final bool blocked;
}

class ChatFinished extends ChatEvent {
  const ChatFinished();
}

class ChatFailed extends ChatEvent {
  const ChatFailed(this.text);
  final String? text;
}

/// Reads server-sent events from [bytes], however they are split.
///
/// - Only `data:` lines count; comments (`: keepalive`) and other fields are
///   skipped, as are unknown event types and lines that aren't JSON.
/// - A tool is announced once, at `tool-input-start`, or at
///   `tool-input-available` if the start wasn't sent.
/// - Nothing after `[DONE]` is read.
Stream<ChatEvent> parseChatStream(Stream<List<int>> bytes) async* {
  final announced = <String>{};
  final data = StringBuffer();
  await for (final raw in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
    final line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
    if (line.isNotEmpty) {
      if (line.startsWith('data:')) {
        if (data.isNotEmpty) data.write('\n');
        data.write(line.substring(5).trimLeft());
      }
      continue;
    }
    // A blank line ends one event.
    final payload = data.toString();
    data.clear();
    if (payload.isEmpty) continue;
    if (payload == '[DONE]') return;
    final event = _read(payload, announced);
    if (event != null) yield event;
  }
  // A last event without its blank line.
  final payload = data.toString();
  if (payload.isNotEmpty && payload != '[DONE]') {
    final event = _read(payload, announced);
    if (event != null) yield event;
  }
}

ChatEvent? _read(String payload, Set<String> announced) {
  final Object? j;
  try {
    j = jsonDecode(payload);
  } on FormatException {
    return null;
  }
  if (j is! Map<String, dynamic>) return null;
  switch (j['type']) {
    case 'text-delta':
      final d = j['delta'];
      return d is String ? ChatText(d) : null;
    case 'tool-input-start' || 'tool-input-available':
      final id = (j['toolCallId'] as String?) ?? '';
      if (!announced.add(id)) return null;
      return ChatToolStarted(id, (j['toolName'] as String?) ?? '');
    case 'tool-output-available':
      return ChatToolDone((j['toolCallId'] as String?) ?? '', j['output']);
    case 'data-trace':
      final d = j['data'];
      if (d is! Map) return null;
      return ChatTrace((d['traced'] as num?)?.toInt() ?? 0, (d['total'] as num?)?.toInt() ?? 0, d['blocked'] == true);
    case 'finish':
      return const ChatFinished();
    case 'error':
      return ChatFailed(j['errorText'] as String?);
    default:
      return null;
  }
}
