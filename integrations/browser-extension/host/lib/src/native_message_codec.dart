import 'dart:async';
import 'dart:convert';

/// The Native Messaging framing: each message is a 4-byte
/// little-endian length followed by UTF-8 JSON. Messages are capped
/// at 1 MiB; a longer message is reported as a StateError and ends
/// the stream. A malformed JSON body is reported as a
/// FormatException on the stream and decoding continues with the
/// next message.
class NativeMessageCodec {
  static const int maxMessageBytes = 1024 * 1024;

  static List<int> encode(Map<String, Object?> message) {
    final body = utf8.encode(jsonEncode(message));
    if (body.length > maxMessageBytes) {
      throw StateError('Native message exceeds 1 MiB');
    }
    return [
      body.length & 0xFF,
      (body.length >> 8) & 0xFF,
      (body.length >> 16) & 0xFF,
      (body.length >> 24) & 0xFF,
      ...body,
    ];
  }

  static Stream<Map<String, Object?>> decode(Stream<List<int>> input) {
    final controller = StreamController<Map<String, Object?>>();
    final buffer = <int>[];
    var closed = false;
    late final StreamSubscription<List<int>> subscription;

    void close() {
      if (closed) {
        return;
      }
      closed = true;
      unawaited(subscription.cancel());
      unawaited(controller.close());
    }

    void pump() {
      while (!closed && buffer.length >= 4) {
        final length =
            buffer[0] |
            (buffer[1] << 8) |
            (buffer[2] << 16) |
            (buffer[3] << 24);
        if (length > maxMessageBytes) {
          controller.addError(
            StateError('Native message exceeds 1 MiB ($length bytes)'),
          );
          close();
          return;
        }
        if (buffer.length < 4 + length) {
          return;
        }
        final body = buffer.sublist(4, 4 + length);
        buffer.removeRange(0, 4 + length);
        try {
          final decoded = jsonDecode(utf8.decode(body));
          if (decoded is Map<String, Object?>) {
            controller.add(decoded);
          }
        } on FormatException catch (e) {
          controller.addError(e);
        }
      }
    }

    subscription = input.listen(
      (chunk) {
        buffer.addAll(chunk);
        pump();
      },
      onError: controller.addError,
      onDone: () {
        if (buffer.isNotEmpty) {
          controller.addError(
            const FormatException('Truncated native message'),
          );
        }
        close();
      },
      cancelOnError: false,
    );
    return controller.stream;
  }
}
