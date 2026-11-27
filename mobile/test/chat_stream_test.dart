import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lamp_shop/core/api/chat_stream.dart';

/// Plan 5.3: `chat_stream.dart` reads the server-sent events from POST /chat
/// (the Vercel AI SDK UI message stream, as LaMP.ai's server sends it).
void main() {
  String fixture(String name) => File('test/fixtures/$name.txt').readAsStringSync();

  Future<List<ChatEvent>> parse(String text, {int chunk = 0}) {
    final bytes = utf8.encode(text);
    final pieces = chunk == 0
        ? [bytes]
        : [for (var i = 0; i < bytes.length; i += chunk) bytes.sublist(i, (i + chunk).clamp(0, bytes.length))];
    return parseChatStream(Stream.fromIterable(pieces)).toList();
  }

  test('a tool step, the answer in pieces, the check, then finish', () async {
    final ev = await parse(fixture('chat_answer'));
    expect(ev.whereType<ChatToolStarted>().map((e) => e.name), ['get_forecast']);
    expect(ev.whereType<ChatToolDone>().single.id, 't1');
    expect(
      ev.whereType<ChatText>().map((e) => e.delta).join(),
      "You will be short BDT 19,000 on 26 Oct, when Supplier A's order is due.",
    );
    final trace = ev.whereType<ChatTrace>().single;
    expect((trace.traced, trace.total, trace.blocked), (1, 1, false));
    expect(ev.last, isA<ChatFinished>());
  });

  test('a tool is announced once, at its start, not again when its input is ready', () async {
    final ev = await parse(fixture('chat_answer'));
    expect(ev.whereType<ChatToolStarted>(), hasLength(1));
  });

  test('split anywhere, even inside a Bangla letter, it reads the same', () async {
    final text = fixture('chat_answer').replaceFirst('You will be short ', 'আপনার কম পড়বে ');
    final whole = await parse(text);
    for (final size in [1, 3, 7, 64]) {
      final split = await parse(text, chunk: size);
      expect(
        split.whereType<ChatText>().map((e) => e.delta).join(),
        whole.whereType<ChatText>().map((e) => e.delta).join(),
        reason: 'chunks of $size',
      );
      expect(split.length, whole.length);
    }
  });

  test('the guard held the answer back', () async {
    final ev = await parse(fixture('chat_held'));
    expect(ev.whereType<ChatTrace>().single.blocked, isTrue);
    expect(ev.whereType<ChatText>().single.delta, startsWith('I held that answer back'));
  });

  test('an error event', () async {
    final ev = await parse(fixture('chat_error'));
    expect(ev.last, isA<ChatFailed>());
    expect((ev.last as ChatFailed).text, 'model timeout');
  });

  test('a stream cut off before finish has no finish', () async {
    final ev = await parse(fixture('chat_dropped'));
    expect(ev.whereType<ChatFinished>(), isEmpty);
  });

  test('a step proposed for Approvals', () async {
    final ev = await parse(fixture('chat_propose'));
    expect(ev.whereType<ChatToolStarted>().single.name, 'propose_action');
  });

  test('comments, keep-alives, other fields, unknown types and bad JSON are skipped', () async {
    final ev = await parse(
      ': keepalive\n\n'
      'event: message\nid: 7\ndata: {"type":"text-delta","id":"a","delta":"Hi"}\n\n'
      'data: {"type":"reasoning-delta","delta":"thinking"}\n\n'
      'data: {not json}\n\n'
      'data: {"type":"finish"}\n\n'
      'data: [DONE]\n\n'
      'data: {"type":"text-delta","id":"a","delta":"after done"}\n\n',
    );
    expect(ev.whereType<ChatText>().map((e) => e.delta), ['Hi']);
    expect(ev.last, isA<ChatFinished>());
  });

  test('Windows line ends are read too', () async {
    final ev = await parse('data: {"type":"text-delta","id":"a","delta":"Hi"}\r\n\r\ndata: {"type":"finish"}\r\n\r\n');
    expect(ev.whereType<ChatText>().single.delta, 'Hi');
    expect(ev.last, isA<ChatFinished>());
  });
}
