import 'dart:async';
import 'dart:convert';

import 'package:pdm_native_host/src/native_message_codec.dart';
import 'package:test/test.dart';

List<int> frame(List<int> body) {
  return [
    body.length & 0xFF,
    (body.length >> 8) & 0xFF,
    (body.length >> 16) & 0xFF,
    (body.length >> 24) & 0xFF,
    ...body,
  ];
}

void main() {
  group('NativeMessageCodec', () {
    test('encode/decode round-trips a message', () async {
      const message = {
        'type': 'download.create',
        'id': 'r1',
        'url': 'http://example.com/f.zip',
      };
      final bytes = NativeMessageCodec.encode(message);
      final decoded = await NativeMessageCodec.decode(
        Stream.value(bytes),
      ).toList();
      expect(decoded, [message]);
    });

    test('a message split across chunks decodes', () async {
      const message = {'type': 'download.create', 'id': 'r2'};
      final bytes = NativeMessageCodec.encode(message);
      final controller = StreamController<List<int>>();
      final future = NativeMessageCodec.decode(controller.stream).toList();
      controller.add(bytes.sublist(0, 3));
      controller.add(bytes.sublist(3, 10));
      controller.add(bytes.sublist(10));
      await controller.close();
      expect(await future, [message]);
    });

    test('two messages in one chunk both decode', () async {
      const first = {'type': 'download.create', 'id': 'r1'};
      const second = {'type': 'download.create', 'id': 'r2'};
      final bytes = [
        ...NativeMessageCodec.encode(first),
        ...NativeMessageCodec.encode(second),
      ];
      final decoded = await NativeMessageCodec.decode(
        Stream.value(bytes),
      ).toList();
      expect(decoded, [first, second]);
    });

    test('a message over 1 MiB is rejected and ends the stream', () async {
      final header = [0x01, 0x00, 0x10, 0x00]; // 0x100001 = 1048577
      final errors = <Object>[];
      var done = false;
      final doneCompleter = Completer<void>();
      NativeMessageCodec.decode(Stream.value(header)).listen(
        (_) {},
        onError: errors.add,
        onDone: () {
          done = true;
          doneCompleter.complete();
        },
      );
      // NB: StreamSubscription.asFuture() rethrows stream errors even
      // when onError is set, so wait on the done completer instead.
      await doneCompleter.future;
      expect(errors, hasLength(1));
      expect(errors.single, isA<StateError>());
      expect(done, isTrue);
    });

    test('a malformed message is dropped and decoding continues', () async {
      const first = {'type': 'download.create', 'id': 'r1'};
      const second = {'type': 'download.create', 'id': 'r2'};
      final bytes = [
        ...NativeMessageCodec.encode(first),
        ...frame(utf8.encode('{not json')),
        ...NativeMessageCodec.encode(second),
      ];
      final values = <Map<String, Object?>>[];
      final errors = <Object>[];
      var done = false;
      final doneCompleter = Completer<void>();
      NativeMessageCodec.decode(Stream.value(bytes)).listen(
        values.add,
        onError: errors.add,
        onDone: () {
          done = true;
          doneCompleter.complete();
        },
      );
      await doneCompleter.future;
      expect(values, [first, second]);
      expect(errors, hasLength(1));
      expect(errors.single, isA<FormatException>());
      expect(done, isTrue);
    });
  });
}
