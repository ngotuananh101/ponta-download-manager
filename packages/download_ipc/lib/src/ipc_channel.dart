import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'protocol.dart';

/// One side of a newline-delimited JSON connection (§4.2). Transport
/// independent: it only knows a byte stream in and a byte sink out.
/// Lines are `\n`-terminated; `\r\n` is tolerated. A malformed line
/// is answered with an `invalid-message` error and the connection
/// stays open; a line over [maxLineBytes] is answered the same way
/// and the connection is closed, so a peer cannot grow memory
/// unboundedly. Sending a message over [maxLineBytes] throws an
/// [ArgumentError] and writes nothing.
class IpcChannel {
  IpcChannel(
    Stream<List<int>> input,
    StreamSink<List<int>> output, {
    this.maxLineBytes = 1024 * 1024,
  }) : _output = output {
    _subscription = input.listen(
      _onData,
      onError: (_) => _close(),
      onDone: _close,
    );
    // A write to a peer that went away fails with a broken pipe.
    // The socket reports it through its `done` future; without a
    // handler that error surfaces as an unhandled async error.
    // Handling it here also closes the channel, so later sends are
    // skipped instead of writing to the dead peer again.
    final out = _output;
    if (out is IOSink) {
      unawaited(
        out.done.catchError((_) {
          _close();
        }),
      );
    }
  }

  final int maxLineBytes;
  final StreamSink<List<int>> _output;
  final _incoming = StreamController<Map<String, Object?>>();
  final _buffer = <int>[];
  late final StreamSubscription<List<int>> _subscription;
  var _closed = false;

  Stream<Map<String, Object?>> get messages => _incoming.stream;

  bool get isClosed => _closed;

  Future<void> send(Map<String, Object?> message) async {
    if (_closed) {
      throw StateError('IpcChannel is closed');
    }
    final encoded = utf8.encode(jsonEncode(message));
    if (encoded.length > maxLineBytes) {
      throw ArgumentError('Message exceeds $maxLineBytes bytes');
    }
    try {
      _output.add([...encoded, 0x0A]);
    } catch (_) {
      // The peer is gone; close the channel so the server drops
      // this client instead of writing to it again.
      await close();
      rethrow;
    }
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _subscription.cancel();
    // Do not await the controller closes: a StreamController's
    // close() future only completes once a listener consumes the
    // done event, and by now the listener is gone (or never existed
    // on the output side), so awaiting would hang forever. A real
    // socket (IOSink) close does complete, so await that one.
    unawaited(_incoming.close());
    if (_output is IOSink) {
      await _output.close();
    } else {
      unawaited(_output.close());
    }
  }

  void _onData(List<int> chunk) {
    var offset = 0;
    while (offset < chunk.length && !_closed) {
      final newline = chunk.indexOf(0x0A, offset);
      if (newline == -1) {
        _buffer.addAll(chunk.sublist(offset));
        if (_buffer.length > maxLineBytes) {
          _sendErrorAndClose(
            IpcErrorCode.invalidMessage,
            'Line exceeds $maxLineBytes bytes',
          );
        }
        return;
      }
      _buffer.addAll(chunk.sublist(offset, newline));
      if (_buffer.length > maxLineBytes) {
        // A single chunk can carry a whole over-cap line: the cap
        // must be checked here too, not only on the no-newline path.
        _buffer.clear();
        _sendErrorAndClose(
          IpcErrorCode.invalidMessage,
          'Line exceeds $maxLineBytes bytes',
        );
        return;
      }
      offset = newline + 1;
      _emitLine();
    }
  }

  void _emitLine() {
    var bytes = _buffer.toList();
    _buffer.clear();
    if (bytes.length > maxLineBytes) {
      _sendErrorAndClose(
        IpcErrorCode.invalidMessage,
        'Line exceeds $maxLineBytes bytes',
      );
      return;
    }
    if (bytes.isNotEmpty && bytes.last == 0x0D) {
      bytes = bytes.sublist(0, bytes.length - 1);
    }
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is Map<String, Object?>) {
        if (!_closed) {
          _incoming.add(decoded);
        }
      } else {
        _sendError(
          IpcErrorCode.invalidMessage,
          'Message is not a JSON object',
        );
      }
    } on FormatException catch (e) {
      _sendError(IpcErrorCode.invalidMessage, e.message);
    }
  }

  void _sendError(String code, String message) {
    if (_closed) {
      return;
    }
    try {
      _output.add(
        utf8.encode('${jsonEncode(ipcErrorMessage(code, message))}\n'),
      );
    } catch (_) {
      // The peer is gone; closing the channel is enough.
    }
  }

  Future<void> _sendErrorAndClose(String code, String message) async {
    _sendError(code, message);
    await close();
  }

  void _close() {
    if (_closed) {
      return;
    }
    _closed = true;
    unawaited(_subscription.cancel());
    unawaited(_incoming.close());
    // The peer went away: half-close our side too. Fire-and-forget
    // for the same reason as in close().
    unawaited(_output.close());
  }
}
