import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../utils/constants/vr_world_constants.dart';
import '../models/vr_region_disk_cache_stats.dart';

typedef _DiskEntryRecord = ({
  File file,
  String key,
  DateTime lastUsed,
  int fileBytes,
  int payloadOffset,
  int payloadLength,
  int checksum,
});

/// Bounded native cache of encoded regions that can safely be downloaded again.
///
/// This is NOT storage for saves, session context, purchases, or user-created
/// content. Callers own encoding, download authorization and key construction;
/// include world, instance, geographic origin and content revision in the key.
final class VrRegionDiskCache {
  factory VrRegionDiskCache({
    required String directoryPath,
    int maxBytes = VrWorldConstants.defaultDiskCacheMaxBytes,
    int maxEntries = VrWorldConstants.defaultDiskCacheMaxEntries,
    int? maxEntryBytes,
    Duration idleTtl = const Duration(
      days: VrWorldConstants.defaultDiskCacheIdleDays,
    ),
    DateTime Function()? clock,
  }) {
    if (directoryPath.isEmpty) {
      throw ArgumentError.value(
        directoryPath,
        VrWorldConstants.paramDirectoryPath,
      );
    }
    if (maxBytes <= 0 || maxBytes > VrWorldConstants.maxDiskCacheBytesLimit) {
      throw ArgumentError.value(
        maxBytes,
        VrWorldConstants.paramMaxBytes,
        'Expected 1 byte–2 GiB.',
      );
    }
    if (maxEntries <= 0 ||
        maxEntries > VrWorldConstants.maxDiskCacheEntriesLimit) {
      throw ArgumentError.value(
        maxEntries,
        VrWorldConstants.paramMaxEntries,
        'Expected 1–100000.',
      );
    }
    final entryLimit =
        maxEntryBytes ??
        math.min(maxBytes, VrWorldConstants.defaultMaxDiskEntryBytes);
    if (entryLimit <= 0 || entryLimit > maxBytes) {
      throw ArgumentError.value(
        entryLimit,
        VrWorldConstants.paramMaxEntryBytes,
        'Expected a positive limit no larger than maxBytes.',
      );
    }
    if (idleTtl <= Duration.zero) {
      throw ArgumentError.value(
        idleTtl,
        VrWorldConstants.paramIdleTtl,
        'Expected a positive TTL.',
      );
    }
    return VrRegionDiskCache._(
      Directory(directoryPath).absolute,
      maxBytes,
      maxEntries,
      entryLimit,
      idleTtl,
      clock ?? DateTime.now,
    );
  }

  VrRegionDiskCache._(
    this._root,
    this.maxBytes,
    this.maxEntries,
    this.maxEntryBytes,
    this.idleTtl,
    this._clock,
  );

  final int maxBytes;
  final int maxEntries;
  final int maxEntryBytes;
  final Duration idleTtl;
  final Directory _root;
  final DateTime Function() _clock;
  Future<void> _pending = Future<void>.value();
  int _hits = 0;
  int _misses = 0;
  int _evictions = 0;
  int _nonce = 0;
  bool _hasPruned = false;

  static const _namespace = VrWorldConstants.diskCacheNamespace;
  static const _magic = VrWorldConstants.diskCacheMagic;
  static const _maxHeaderBytes = VrWorldConstants.maxDiskHeaderBytes;
  static final _entryName = RegExp(VrWorldConstants.diskEntryNamePattern);
  static final _pendingName = RegExp(VrWorldConstants.diskPendingNamePattern);

  Directory get _directory => Directory('${_root.path}/$_namespace');

  Future<Uint8List?> read(String key) {
    _validateKey(key);
    return _serial(() async {
      try {
        await _prepare();
        final now = _clock().toUtc();
        if (!_hasPruned) await _prune(now);
        final file = _fileFor(key);
        final entry = await _inspect(file, now);
        if (entry == null || entry.key != key) {
          _misses++;
          return null;
        }
        final bytes = await _readPayload(entry);
        if (bytes == null) {
          await _removeManaged(file);
          _misses++;
          return null;
        }
        await file.setLastModified(now);
        _hits++;
        return bytes;
      } on FileSystemException {
        _misses++;
        return null;
      }
    });
  }

  Future<bool> write(String key, Uint8List bytes) {
    _validateKey(key);
    if (bytes.length > maxEntryBytes) return Future<bool>.value(false);
    final owned = Uint8List.fromList(bytes);
    return _serial(() async {
      File? pendingFile;
      try {
        await _prepare();
        final now = _clock().toUtc();
        final header = utf8.encode(
          jsonEncode({
            'version': 1,
            'key': key,
            'payloadLength': owned.length,
            'checksum': _checksum(owned),
          }),
        );
        final size =
            VrWorldConstants.diskCachePrefixBytes +
            header.length +
            owned.length;
        if (header.length > _maxHeaderBytes || size > maxBytes) return false;
        final file = _fileFor(key);
        final type = await FileSystemEntity.type(file.path, followLinks: false);
        if (type != FileSystemEntityType.file &&
            type != FileSystemEntityType.notFound) {
          return false;
        }
        final prefix = Uint8List(VrWorldConstants.diskCachePrefixBytes);
        prefix.setRange(0, _magic.length, _magic);
        ByteData.sublistView(
          prefix,
        ).setUint32(VrWorldConstants.diskCacheLengthOffset, header.length);
        pendingFile = File(
          '${_directory.path}/.pending-${DateTime.now().microsecondsSinceEpoch}'
          '-${_nonce++}.tmp',
        );
        final handle = await pendingFile.open(mode: FileMode.writeOnly);
        try {
          await handle.writeFrom(prefix);
          await handle.writeFrom(header);
          await handle.writeFrom(owned);
          await handle.flush();
        } finally {
          await handle.close();
        }
        await pendingFile.setLastModified(now);
        await pendingFile.rename(file.path);
        pendingFile = null;
        final retained = await _prune(now, keepKey: key);
        return retained.any((entry) => entry.key == key);
      } on FileSystemException {
        return false;
      } finally {
        if (pendingFile != null) await _removeManaged(pendingFile);
      }
    });
  }

  Future<VrRegionDiskCacheStats> prune() => _serial(() async {
    await _prepare();
    return _snapshot(await _prune(_clock().toUtc()));
  });

  Future<VrRegionDiskCacheStats> stats() => prune();

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = Completer<T>();
    _pending = _pending.then((_) async {
      try {
        result.complete(await action());
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  Future<void> _prepare() async {
    for (final directory in [_root, _directory]) {
      final type = await FileSystemEntity.type(
        directory.path,
        followLinks: false,
      );
      if (type == FileSystemEntityType.notFound) {
        await directory.create(recursive: true);
      } else if (type != FileSystemEntityType.directory) {
        throw FileSystemException(
          'Cache path is not a directory',
          directory.path,
        );
      }
      if (await FileSystemEntity.type(directory.path, followLinks: false) !=
          FileSystemEntityType.directory) {
        throw FileSystemException('Cache path was replaced', directory.path);
      }
    }
  }

  File _fileFor(String key) =>
      File('${_directory.path}/r-${_fingerprint(utf8.encode(key))}.vrregion');

  Future<List<_DiskEntryRecord>> _prune(DateTime now, {String? keepKey}) async {
    final entries = <_DiskEntryRecord>[];
    await for (final child in _directory.list(followLinks: false)) {
      if (child is! File) continue;
      final name = child.uri.pathSegments.last;
      if (_pendingName.hasMatch(name)) {
        await _removeManaged(child);
      } else if (_entryName.hasMatch(name)) {
        final entry = await _inspect(child, now);
        if (entry != null) entries.add(entry);
      }
    }
    entries.sort((a, b) {
      if (a.key == keepKey && b.key != keepKey) return 1;
      if (b.key == keepKey && a.key != keepKey) return -1;
      final compared = a.lastUsed.compareTo(b.lastUsed);
      return compared != 0 ? compared : a.file.path.compareTo(b.file.path);
    });
    var total = entries.fold<int>(0, (sum, entry) => sum + entry.fileBytes);
    var count = entries.length;
    var removeCount = 0;
    for (final entry in entries) {
      if (count <= maxEntries && total <= maxBytes) break;
      await _removeManaged(entry.file);
      count--;
      total -= entry.fileBytes;
      removeCount++;
    }
    _hasPruned = true;
    return entries.sublist(removeCount);
  }

  Future<_DiskEntryRecord?> _inspect(File file, DateTime now) async {
    RandomAccessFile? handle;
    try {
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        return null;
      }
      final stat = await file.stat();
      if (now.difference(stat.modified) >= idleTtl ||
          stat.size < VrWorldConstants.diskCachePrefixBytes ||
          stat.size > maxBytes ||
          stat.size >
              maxEntryBytes +
                  _maxHeaderBytes +
                  VrWorldConstants.diskCachePrefixBytes) {
        await _removeManaged(file);
        return null;
      }
      handle = await file.open();
      final prefix = await handle.read(VrWorldConstants.diskCachePrefixBytes);
      if (prefix.length != VrWorldConstants.diskCachePrefixBytes ||
          !List<int>.generate(
            _magic.length,
            (i) => i,
          ).every((i) => prefix[i] == _magic[i])) {
        throw const FormatException('Invalid region cache magic');
      }
      final headerLength = ByteData.sublistView(
        prefix,
      ).getUint32(VrWorldConstants.diskCacheLengthOffset);
      if (headerLength == 0 || headerLength > _maxHeaderBytes) {
        throw const FormatException('Invalid region cache header length');
      }
      final headerBytes = await handle.read(headerLength);
      if (headerBytes.length != headerLength) {
        throw const FormatException('Truncated region cache header');
      }
      final header = jsonDecode(utf8.decode(headerBytes));
      if (header is! Map<String, dynamic> ||
          header['version'] != 1 ||
          header['key'] is! String ||
          header['payloadLength'] is! int ||
          header['checksum'] is! int) {
        throw const FormatException('Invalid region cache metadata');
      }
      final key = header['key'] as String;
      final payloadLength = header['payloadLength'] as int;
      final checksum = header['checksum'] as int;
      _validateKey(key);
      if (_fileFor(key).path != file.path ||
          payloadLength < 0 ||
          payloadLength > maxEntryBytes ||
          checksum < 0 ||
          checksum > 0xffffffff ||
          stat.size !=
              VrWorldConstants.diskCachePrefixBytes +
                  headerLength +
                  payloadLength) {
        throw const FormatException('Mismatched region cache metadata');
      }
      return (
        file: file,
        key: key,
        lastUsed: stat.modified,
        fileBytes: stat.size,
        payloadOffset: VrWorldConstants.diskCachePrefixBytes + headerLength,
        payloadLength: payloadLength,
        checksum: checksum,
      );
    } on FormatException {
      if (handle != null) {
        await handle.close();
        handle = null;
      }
      await _removeManaged(file);
      return null;
    } on ArgumentError {
      if (handle != null) {
        await handle.close();
        handle = null;
      }
      await _removeManaged(file);
      return null;
    } on FileSystemException {
      return null;
    } finally {
      await handle?.close();
    }
  }

  Future<Uint8List?> _readPayload(_DiskEntryRecord entry) async {
    if (await FileSystemEntity.type(entry.file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      return null;
    }
    final handle = await entry.file.open();
    try {
      if (await handle.length() != entry.fileBytes) return null;
      await handle.setPosition(entry.payloadOffset);
      final bytes = await handle.read(entry.payloadLength);
      if (bytes.length != entry.payloadLength ||
          _checksum(bytes) != entry.checksum) {
        return null;
      }
      return bytes;
    } finally {
      await handle.close();
    }
  }

  Future<void> _removeManaged(File file) async {
    try {
      final name = file.uri.pathSegments.last;
      if (file.parent.path == _directory.path &&
          (_entryName.hasMatch(name) || _pendingName.hasMatch(name)) &&
          await FileSystemEntity.type(file.path, followLinks: false) ==
              FileSystemEntityType.file) {
        await file.delete();
        if (_entryName.hasMatch(name)) _evictions++;
      }
    } on FileSystemException {
      // A disappearing/inaccessible disposable entry must not affect the host.
    }
  }

  VrRegionDiskCacheStats _snapshot(List<_DiskEntryRecord> entries) =>
      VrRegionDiskCacheStats(
        entryCount: entries.length,
        totalBytes: entries.fold(0, (sum, entry) => sum + entry.fileBytes),
        hits: _hits,
        misses: _misses,
        evictions: _evictions,
      );

  static void _validateKey(String key) {
    if (key.isEmpty ||
        utf8.encode(key).length > VrWorldConstants.maxDiskKeyUtf8Bytes) {
      throw ArgumentError.value(
        key,
        VrWorldConstants.paramKey,
        'Expected 1–4096 UTF-8 bytes.',
      );
    }
  }

  static String _fingerprint(List<int> bytes) {
    final hashes = [0x811c9dc5, 0x9e3779b9, 0x85ebca6b, 0xc2b2ae35];
    const primes = [16777619, 2246822519, 3266489917, 668265263];
    for (final byte in bytes) {
      for (var i = 0; i < hashes.length; i++) {
        hashes[i] = ((hashes[i] ^ byte) * primes[i]) & 0xffffffff;
      }
    }
    return hashes
        .map((value) => value.toRadixString(16).padLeft(8, '0'))
        .join();
  }

  static final _crcTable = List<int>.generate(256, (value) {
    var crc = value;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) == 0 ? crc >> 1 : 0xedb88320 ^ (crc >> 1);
    }
    return crc;
  });

  static int _checksum(List<int> bytes) {
    var crc = 0xffffffff;
    for (final byte in bytes) {
      crc = _crcTable[(crc ^ byte) & 0xff] ^ (crc >> 8);
    }
    return (crc ^ 0xffffffff) & 0xffffffff;
  }
}
