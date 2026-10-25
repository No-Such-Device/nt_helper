import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Darwin primitives missing from dart:io: inode identity, per-open-description
/// flock (not process-wide fcntl locks), exclusive creation and directory fsync.
/// This file is used only by the macOS storage boundary.
final class MacosStorageIo {
  static final _lib = DynamicLibrary.process();
  static final _open = _lib
      .lookupFunction<
        Int32 Function(Pointer<Utf8>, Int32, VarArgs<(Int32,)>),
        int Function(Pointer<Utf8>, int, int)
      >('open');
  static final _close = _lib
      .lookupFunction<Int32 Function(Int32), int Function(int)>('close');
  static final _flock = _lib
      .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
        'flock',
      );
  static final _fsync = _lib
      .lookupFunction<Int32 Function(Int32), int Function(int)>('fsync');
  static final _fullSync = _lib
      .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
        'fcntl',
      );
  // Intel Darwin retains the legacy 32-bit-inode ABI under the bare symbols.
  // Our 144-byte buffers and offsets require stat64, including birth time.
  // C callers get this symbol remapping from sys/stat.h; FFI callers do not.
  static final _stat = _lib
      .lookupFunction<
        Int32 Function(Pointer<Utf8>, Pointer<Uint8>),
        int Function(Pointer<Utf8>, Pointer<Uint8>)
      >(Abi.current() == Abi.macosX64 ? r'lstat$INODE64' : 'lstat');
  static final _fstat = _lib
      .lookupFunction<
        Int32 Function(Int32, Pointer<Uint8>),
        int Function(int, Pointer<Uint8>)
      >(Abi.current() == Abi.macosX64 ? r'fstat$INODE64' : 'fstat');
  static final _pread = _lib
      .lookupFunction<
        IntPtr Function(Int32, Pointer<Uint8>, IntPtr, Int64),
        int Function(int, Pointer<Uint8>, int, int)
      >('pread');
  static final _write = _lib
      .lookupFunction<
        IntPtr Function(Int32, Pointer<Uint8>, IntPtr),
        int Function(int, Pointer<Uint8>, int)
      >('write');
  static final _mkdir = _lib
      .lookupFunction<
        Int32 Function(Pointer<Utf8>, Uint16),
        int Function(Pointer<Utf8>, int)
      >('mkdir');
  static final _link = _lib
      .lookupFunction<
        Int32 Function(Pointer<Utf8>, Pointer<Utf8>),
        int Function(Pointer<Utf8>, Pointer<Utf8>)
      >('link');
  static final _errno = _lib
      .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
        '__error',
      );

  static Never _error(String operation, String path) =>
      throw FileSystemException(
        operation,
        path,
        OSError('Darwin storage operation failed', _errno().value),
      );

  static T _path<T>(String path, T Function(Pointer<Utf8>) action) {
    final native = path.toNativeUtf8();
    try {
      return action(native);
    } finally {
      calloc.free(native);
    }
  }

  /// Null is returned only for ENOENT, never for denied/inconclusive inventory.
  static String? identity(String path) => _path(path, (native) {
    final buffer = calloc<Uint8>(144); // Darwin struct stat, arm64 and x86_64.
    try {
      if (_stat(native, buffer) != 0) {
        if (_errno().value == 2) return null;
        _error('Cannot inventory storage', path);
      }
      final data = ByteData.sublistView(buffer.asTypedList(144));
      final kind = data.getUint16(4, Endian.host) & 0xf000;
      if (kind != 0x8000 && kind != 0x4000) {
        throw FileSystemException(
          'Unsupported storage entity (including symlink)',
          path,
        );
      }
      return '$kind:${data.getInt32(0, Endian.host)}:${data.getUint64(8, Endian.host)}:'
          '${data.getInt64(80, Endian.host)}:${data.getInt64(88, Endian.host)}';
    } finally {
      calloc.free(buffer);
    }
  });

  static MacosStorageRead openRead(String path) => _path(path, (native) {
    final fd = _open(native, 0x100, 0); // O_RDONLY | O_NOFOLLOW
    if (fd < 0) _error('Cannot retain source read access', path);
    return MacosStorageRead._(fd, path);
  });

  static void reserveDirectory(String path) => _path(path, (native) {
    if (_mkdir(native, 0x1c0) != 0) {
      // 0700, fail rather than adopt EEXIST.
      _error(
        'Cannot exclusively reserve work; existing work is retained',
        path,
      );
    }
  });

  static void requireFile(String path) {
    final id = identity(path);
    if (id == null || !id.startsWith('32768:')) {
      throw FileSystemException(
        'Required regular storage file unavailable',
        path,
      );
    }
  }

  static void sync(String path) => _path(path, (native) {
    final fd = _open(native, 0x100 /* O_NOFOLLOW */, 0);
    if (fd < 0) _error('Cannot open for durability', path);
    try {
      if (_fsync(fd) != 0) _error('Cannot sync storage', path);
      if (identity(path)!.startsWith('32768:') && _fullSync(fd, 51) != 0) {
        _error(
          'Filesystem does not support durable storage (F_FULLFSYNC)',
          path,
        );
      }
    } finally {
      _close(fd);
    }
  });

  /// The final name becomes visible only with complete, flushed contents. link
  /// is no-replace, unlike rename. A killed writer leaves only a retained temp.
  static Future<void> publish(
    String temporary,
    String destination,
    List<int> bytes,
    Future<void> Function(String) checkpoint,
  ) async {
    await checkpoint('before:create');
    final fd = _path(
      temporary,
      (native) => _open(native, 0x100 | 0x200 | 0x800 | 1, 0x180),
    ); // NOFOLLOW|CREAT|EXCL|WRONLY, 0600
    if (fd < 0) _error('Cannot reserve storage record', temporary);
    final data = calloc<Uint8>(bytes.length);
    try {
      await checkpoint('after:create');
      data.asTypedList(bytes.length).setAll(0, bytes);
      await checkpoint('before:write');
      var offset = 0;
      while (offset < bytes.length) {
        final remaining = bytes.length - offset;
        final count = _write(
          fd,
          data + offset,
          offset == 0 ? (remaining + 1) ~/ 2 : remaining,
        );
        if (count <= 0) _error('Cannot write storage record', temporary);
        offset += count;
        if (offset < bytes.length) await checkpoint('during:write');
      }
      await checkpoint('after:write');
      await checkpoint('before:sync');
      if (_fsync(fd) != 0 || _fullSync(fd, 51) != 0) {
        _error('Cannot durably sync storage record', temporary);
      }
      await checkpoint('after:sync');
    } finally {
      calloc.free(data);
      _close(fd);
    }
    // The retained witness must itself be durable before the final name can
    // survive a torn namespace update. File fsync alone does not persist it.
    await checkpoint('before:witness-sync');
    sync(File(temporary).parent.path);
    await checkpoint('after:witness-sync');
    await checkpoint('before:publish');
    _path(
      temporary,
      (native) => _path(destination, (target) {
        if (_link(native, target) != 0) {
          _error(
            'Cannot publish storage record without replacement',
            destination,
          );
        }
      }),
    );
    await checkpoint('after:publish');
    await checkpoint('before:directory-sync');
    sync(File(destination).parent.path);
    await checkpoint('after:directory-sync');
  }

  static MacosStorageLease lock(String path) => _path(path, (native) {
    final fd = _open(native, 0x100 | 0x200 | 2, 0x180); // NOFOLLOW|CREAT|RDWR
    if (fd < 0) _error('Cannot open storage coordination lock', path);
    if (_flock(fd, 2 | 4) != 0) {
      // LOCK_EX | LOCK_NB
      _close(fd);
      throw FileSystemException(
        'Storage selection is busy; Retry after the other attempt settles',
        path,
      );
    }
    return MacosStorageLease._(fd);
  });
}

/// Never close an auxiliary source descriptor while SQLite exclusion is held:
/// POSIX close(any fd for an inode) releases that process's fcntl locks on it.
final class MacosStorageRead {
  MacosStorageRead._(this._fd, this.path);
  final String path;
  int? _fd;

  Uint8List read() {
    final fd = _fd!;
    final stat = calloc<Uint8>(144);
    try {
      if (MacosStorageIo._fstat(fd, stat) != 0) {
        MacosStorageIo._error(
          'Cannot inspect retained source descriptor',
          path,
        );
      }
      final size = ByteData.sublistView(
        stat.asTypedList(144),
      ).getInt64(96, Endian.host);
      if (size == 0) return Uint8List(0);
      final data = calloc<Uint8>(size);
      try {
        var offset = 0;
        while (offset < size) {
          final count = MacosStorageIo._pread(
            fd,
            data + offset,
            size - offset,
            offset,
          );
          if (count <= 0) {
            MacosStorageIo._error('Source changed or could not be read', path);
          }
          offset += count;
        }
        return Uint8List.fromList(data.asTypedList(size));
      } finally {
        calloc.free(data);
      }
    } finally {
      calloc.free(stat);
    }
  }

  void close() {
    final fd = _fd;
    if (fd == null) return;
    _fd = null;
    MacosStorageIo._close(fd);
  }
}

final class MacosStorageLease {
  MacosStorageLease._(this._fd);
  int? _fd;
  void close() {
    final fd = _fd;
    if (fd == null) return;
    _fd = null;
    MacosStorageIo._close(fd); // OS also releases this lease on process death.
  }
}
