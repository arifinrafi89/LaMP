import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lamp_shop/core/api/api_client.dart';
import 'package:lamp_shop/features/ask/ask_controller.dart';

/// Ask (plan 5.3, Plus): one question at a time, the answer as it streams,
/// LaMP's steps in plain words, and every ending said plainly.
void main() {
  String fixture(String name) => File('test/fixtures/$name.txt').readAsStringSync();
  late List<Map<String, dynamic>> bodies;
  late Stream<List<int>> Function() answer;
  late int status;
  late String errorBody;
  late int proposed;

  ApiClient api() => ApiClient(
    baseUrl: 'https://api.test/api/v1',
    appVersion: '0.1.0+1',
    language: () => 'en',
    accessToken: () => 'tok',
    refresh: () async => false,
    http: MockClient.streaming((req, body) async {
      bodies.add(jsonDecode(utf8.decode(await body.toBytes())) as Map<String, dynamic>);
      if (status != 200) return http.StreamedResponse(Stream.value(utf8.encode(errorBody)), status);
      return http.StreamedResponse(answer(), 200, headers: {'content-type': 'text/event-stream'});
    }),
    backoff: (_) => Duration.zero,
  );

  Stream<List<int>> chunked(String text, [int size = 40]) {
    final b = utf8.encode(text);
    return Stream.fromIterable([for (var i = 0; i < b.length; i += size) b.sublist(i, (i + size).clamp(0, b.length))]);
  }

  AskController ask({String lang = 'en', Duration silence = const Duration(seconds: 60)}) =>
      AskController(api(), language: () => lang, onProposed: () => proposed++, silence: silence);

  setUp(() {
    bodies = [];
    status = 200;
    errorBody = '';
    proposed = 0;
    answer = () => chunked(fixture('chat_answer'));
  });

  test('asks with the chat\'s id, the question as a text part, and the language', () async {
    final a = ask(lang: 'bn');
    await a.ask('Can I pay Supplier A next week?');
    final b = bodies.single;
    expect(b['trigger'], 'submit-message');
    expect(b['id'], isNotEmpty);
    expect(b['lang'], 'bn');
    final m = (b['messages'] as List).single as Map;
    expect(m['role'], 'user');
    expect(m['parts'], [
      {'type': 'text', 'text': 'Can I pay Supplier A next week?'},
    ]);
  });

  test('the answer, the step LaMP took, and the check on its figures', () async {
    final a = ask();
    await a.ask('Can I pay Supplier A next week?');
    expect(a.turns, hasLength(2));
    final r = a.turns.last;
    expect(r.mine, isFalse);
    expect(r.text, "You will be short BDT 19,000 on 26 Oct, when Supplier A's order is due.");
    expect(r.tools, ['get_forecast']);
    expect(r.end, AskEnd.done);
    expect(r.checked, isTrue);
    expect(r.held, isFalse);
    expect(a.busy, isFalse);
  });

  test('while it streams: busy, and the step it is on', () async {
    final c = StreamController<List<int>>();
    answer = () => c.stream;
    final a = ask();
    final done = a.ask('How did we do?');
    await pumpEventQueue();
    expect(a.busy, isTrue);
    c.add(utf8.encode('data: {"type":"tool-input-start","toolCallId":"t1","toolName":"get_accounts"}\n\n'));
    await pumpEventQueue();
    expect(a.turns.last.tools, ['get_accounts']);
    expect(a.turns.last.end, AskEnd.streaming);
    c.add(utf8.encode('data: {"type":"finish"}\n\n'));
    await c.close();
    await done;
    expect(a.busy, isFalse);
  });

  test('one question at a time', () async {
    final c = StreamController<List<int>>();
    answer = () => c.stream;
    final a = ask();
    final first = a.ask('One');
    await pumpEventQueue();
    await a.ask('Two');
    expect(bodies, hasLength(1));
    await c.close();
    await first;
  });

  test('the next question carries the conversation so far', () async {
    final a = ask();
    await a.ask('First?');
    await a.ask('Second?');
    final msgs = (bodies.last['messages'] as List).cast<Map>();
    expect(msgs.map((m) => m['role']), ['user', 'assistant', 'user']);
    expect(((msgs[1]['parts'] as List).single as Map)['text'], startsWith('You will be short'));
    expect(bodies.last['id'], bodies.first['id'], reason: 'one chat');
  });

  test('held back by the guard', () async {
    answer = () => chunked(fixture('chat_held'));
    final a = ask();
    await a.ask('Q');
    expect(a.turns.last.held, isTrue);
    expect(a.turns.last.checked, isFalse);
    expect(a.turns.last.text, startsWith('I held that answer back'));
  });

  test('an error from the server mid-answer: failed', () async {
    answer = () => chunked(fixture('chat_error'));
    final a = ask();
    await a.ask('Q');
    expect(a.turns.last.end, AskEnd.failed);
  });

  test('a stream cut off before finish: lost, never passed off as an answer', () async {
    answer = () => chunked(fixture('chat_dropped'));
    final a = ask();
    await a.ask('Q');
    expect(a.turns.last.end, AskEnd.lost);
  });

  test('silence for too long: lost', () async {
    answer = () => StreamController<List<int>>().stream;
    final a = ask(silence: const Duration(milliseconds: 50));
    await a.ask('Q');
    expect(a.turns.last.end, AskEnd.lost);
  });

  test('the budget used up: the server\'s code, in the turn', () async {
    status = 402;
    errorBody = '{"detail":"Budget used","code":"ai_budget_reached"}';
    final a = ask();
    await a.ask('Q');
    expect(a.turns.last.end, AskEnd.failed);
    expect(a.turns.last.problem!.code, 'ai_budget_reached');
  });

  test('a failed question is left out of what is sent next', () async {
    answer = () => chunked(fixture('chat_dropped'));
    final a = ask();
    await a.ask('Lost one');
    answer = () => chunked(fixture('chat_answer'));
    await a.ask('Next');
    final msgs = (bodies.last['messages'] as List).cast<Map>();
    expect(msgs, hasLength(1));
    expect(((msgs.single['parts'] as List).single as Map)['text'], 'Next');
  });

  test('ask again: the same question, the failed answer replaced', () async {
    answer = () => chunked(fixture('chat_dropped'));
    final a = ask();
    await a.ask('Can I pay?');
    answer = () => chunked(fixture('chat_answer'));
    await a.askAgain();
    expect(a.turns.map((t) => t.mine), [true, false]);
    expect(a.turns.first.text, 'Can I pay?');
    expect(a.turns.last.end, AskEnd.done);
  });

  test('a step proposed for Approvals: said, and Approvals reads again once', () async {
    answer = () => chunked(fixture('chat_propose'));
    final a = ask();
    await a.ask('Ask Supplier A for more days');
    expect(a.turns.last.proposed, isTrue);
    expect(proposed, 1);
  });

  test('a blank question is not sent', () async {
    final a = ask();
    await a.ask('   ');
    expect(bodies, isEmpty);
    expect(a.turns, isEmpty);
  });
}
