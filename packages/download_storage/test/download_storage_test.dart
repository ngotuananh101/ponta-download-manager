import 'dart:io';

import 'package:download_api/download_api.dart';
import 'package:download_storage/download_storage.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pdm-storage-test-');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  List<int> bytesOf(int length, [int seed = 0]) =>
      List<int>.generate(length, (i) => (i + seed) % 256);

  group('FileChunkSink', () {
    test('writes bytes at offsets out of order', () async {
      final sink = await FileChunkSink.create(
        directory: p.join(tempDir.path, 'nested', 'deep'),
        fileName: 'out-of-order.bin',
      );
      final data = bytesOf(1024);
      await Future.wait([
        sink.write(512, data.sublist(512, 768)),
        sink.write(0, data.sublist(0, 256)),
        sink.write(256, data.sublist(256, 512)),
        sink.write(768, data.sublist(768, 1024)),
      ]);
      await sink.close();
      expect(await File(sink.partialPath).readAsBytes(), data);
    });

    test('concurrent writes from many workers produce exact content', () async {
      final sink = await FileChunkSink.create(
        directory: tempDir.path,
        fileName: 'concurrent.bin',
      );
      final data = bytesOf(400 * 1024);
      final writes = <Future<void>>[];
      for (var w = 0; w < 8; w++) {
        for (var c = 0; c < 50; c++) {
          final offset = (w * 50 + c) * 1024;
          writes.add(sink.write(offset, data.sublist(offset, offset + 1024)));
        }
      }
      await Future.wait(writes);
      await sink.close();
      expect(await File(sink.partialPath).readAsBytes(), data);
    });

    test('create fails when the destination already exists', () async {
      final existing = File(p.join(tempDir.path, 'taken.bin'));
      await existing.writeAsBytes(bytesOf(10));
      await expectLater(
        FileChunkSink.create(directory: tempDir.path, fileName: 'taken.bin'),
        throwsA(
          isA<DownloadError>().having((e) => e.code, 'code', 'file-exists'),
        ),
      );
    });

    test('create with overwrite proceeds when the destination exists',
        () async {
      final existing = File(p.join(tempDir.path, 'taken.bin'));
      await existing.writeAsBytes(bytesOf(10));
      final sink = await FileChunkSink.create(
        directory: tempDir.path,
        fileName: 'taken.bin',
        overwrite: true,
      );
      final data = bytesOf(100);
      await sink.write(0, data);
      final finalFile = await sink.finish();
      expect(await finalFile.readAsBytes(), data);
    });

    test('create fails when a partial file already exists', () async {
      final first = await FileChunkSink.create(
        directory: tempDir.path,
        fileName: 'twice.bin',
      );
      await first.write(0, bytesOf(10));
      await first.close();
      await expectLater(
        FileChunkSink.create(directory: tempDir.path, fileName: 'twice.bin'),
        throwsA(
          isA<DownloadError>().having((e) => e.code, 'code', 'file-exists'),
        ),
      );
    });

    test('openExisting resumes a partial file', () async {
      final data = bytesOf(1024);
      final first = await FileChunkSink.create(
        directory: tempDir.path,
        fileName: 'resume.bin',
      );
      await first.write(0, data.sublist(0, 512));
      await first.close();
      final second = await FileChunkSink.openExisting(
        partialPath: first.partialPath,
        filePath: first.filePath,
      );
      await second.write(512, data.sublist(512));
      await second.close();
      expect(await File(first.partialPath).readAsBytes(), data);
    });

    test('finish renames the partial file to the final path', () async {
      final sink = await FileChunkSink.create(
        directory: tempDir.path,
        fileName: 'done.bin',
      );
      final data = bytesOf(100);
      await sink.write(0, data);
      final finalFile = await sink.finish();
      expect(finalFile.path, sink.filePath);
      expect(await finalFile.readAsBytes(), data);
      expect(await File(sink.partialPath).exists(), isFalse);
    });

    test('discard deletes the partial file', () async {
      final sink = await FileChunkSink.create(
        directory: tempDir.path,
        fileName: 'gone.bin',
      );
      await sink.write(0, bytesOf(10));
      await sink.discard();
      expect(await File(sink.partialPath).exists(), isFalse);
    });

    test('write after close throws', () async {
      final sink = await FileChunkSink.create(
        directory: tempDir.path,
        fileName: 'closed.bin',
      );
      await sink.close();
      await expectLater(sink.write(0, [1]), throwsStateError);
    });

    test('close is idempotent', () async {
      final sink = await FileChunkSink.create(
        directory: tempDir.path,
        fileName: 'twice-close.bin',
      );
      await sink.write(0, bytesOf(10));
      await sink.close();
      await sink.close();
    });

    test('filePath is the final destination', () async {
      final sink = await FileChunkSink.create(
        directory: tempDir.path,
        fileName: 'names.bin',
      );
      expect(sink.filePath, p.join(tempDir.path, 'names.bin'));
      expect(sink.partialPath, p.join(tempDir.path, 'names.bin.partial'));
      await sink.close();
    });

    test('length reports written bytes including a sparse gap', () async {
      final sink = await FileChunkSink.create(
        directory: tempDir.path,
        fileName: 'sparse.bin',
      );
      await sink.write(0, bytesOf(100));
      await sink.write(500, bytesOf(100, 7));
      expect(await sink.length, 600);
      final content = await File(sink.partialPath).readAsBytes();
      expect(content.sublist(0, 100), bytesOf(100));
      expect(content.sublist(100, 500), List<int>.filled(400, 0));
      expect(content.sublist(500, 600), bytesOf(100, 7));
      await sink.close();
    });
  });
}
