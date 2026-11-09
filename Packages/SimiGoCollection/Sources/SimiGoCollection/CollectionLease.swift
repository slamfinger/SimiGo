import Darwin
import Foundation

/// Process-level exclusive ownership of one collection state directory.
///
/// The inbox serializes transactions, but that alone cannot stop a second
/// runner from committing an older in-memory cursor snapshot over a newer one,
/// because both snapshots are individually valid writes. A non-blocking
/// `flock` on `<stateDirectory>/collector.lock` admits one runner at a time
/// across threads and processes; the kernel drops the lock when the owner
/// exits, so a crash does not leave a stale lease behind.
final class CollectionLease {
    static let lockFileName = "collector.lock"

    let fileURL: URL
    private let descriptor: Int32

    private init(fileURL: URL, descriptor: Int32) {
        self.fileURL = fileURL
        self.descriptor = descriptor
    }

    static func acquire(directoryURL: URL) throws -> CollectionLease {
        // Refuse a state-directory entry that is itself a symlink. The lock
        // is then opened relative to a verified directory descriptor, so a
        // parent-path substitution cannot redirect this child open.
        var rootInfo = stat()
        if lstat(directoryURL.path, &rootInfo) == 0 {
            guard (rootInfo.st_mode & S_IFMT) == S_IFDIR else {
                throw CollectionStateFailure.unreadableState(
                    path: directoryURL.path, detail: "state directory must not be a symlink")
            }
        } else {
            let code = errno
            guard code == ENOENT else {
                throw CollectionStateFailure.unreadableState(
                    path: directoryURL.path, detail: String(cString: strerror(code)))
            }
            do {
                try FileManager.default.createDirectory(
                    at: directoryURL, withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700])
            } catch {
                throw CollectionStateFailure.unreadableState(
                    path: directoryURL.path, detail: String(describing: error))
            }
            guard lstat(directoryURL.path, &rootInfo) == 0,
                  (rootInfo.st_mode & S_IFMT) == S_IFDIR else {
                throw CollectionStateFailure.unreadableState(
                    path: directoryURL.path, detail: "state directory is not a real directory")
            }
        }
        let directoryFD = open(
            directoryURL.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard directoryFD >= 0 else {
            throw CollectionStateFailure.unreadableState(
                path: directoryURL.path, detail: String(cString: strerror(errno)))
        }
        defer { close(directoryFD) }
        var openedRootInfo = stat()
        guard fstat(directoryFD, &openedRootInfo) == 0,
              (openedRootInfo.st_mode & S_IFMT) == S_IFDIR,
              openedRootInfo.st_dev == rootInfo.st_dev,
              openedRootInfo.st_ino == rootInfo.st_ino,
              openedRootInfo.st_uid == geteuid(),
              (openedRootInfo.st_mode & (S_IWGRP | S_IWOTH)) == 0,
              fchmod(directoryFD, 0o700) == 0 else {
            throw CollectionStateFailure.unreadableState(
                path: directoryURL.path,
                detail: "state directory changed or could not be secured while opening its descriptor")
        }

        let fileURL = directoryURL.appendingPathComponent(lockFileName)
        // O_NONBLOCK matters only for a non-regular entry planted at the lock
        // name: a FIFO must fail the post-open type check, never block.
        let descriptor = openat(
            directoryFD, lockFileName,
            O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK, 0o600)
        guard descriptor >= 0 else {
            throw CollectionStateFailure.unreadableState(
                path: fileURL.path, detail: String(cString: strerror(errno)))
        }
        var fileInfo = stat()
        guard fstat(descriptor, &fileInfo) == 0,
              (fileInfo.st_mode & S_IFMT) == S_IFREG,
              fileInfo.st_uid == geteuid(),
              fileInfo.st_nlink == 1,
              (fileInfo.st_mode & (S_IWGRP | S_IWOTH)) == 0 else {
            close(descriptor)
            throw CollectionStateFailure.unreadableState(
                path: fileURL.path, detail: "lease must be a regular, non-symlink file")
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            // Read the diagnostic PID from the exact inode whose lock attempt
            // failed. Re-opening fileURL after closing this descriptor would
            // re-resolve a mutable path and could follow a swapped symlink.
            let holderPID = code == EWOULDBLOCK ? holder(of: descriptor) : nil
            close(descriptor)
            guard code == EWOULDBLOCK else {
                throw CollectionStateFailure.unreadableState(
                    path: fileURL.path, detail: String(cString: strerror(code)))
            }
            throw CollectionStateFailure.stateAlreadyOwned(
                path: fileURL.path,
                detail: holderPID.map { "held by pid \($0)" }
                    ?? "held by another runner")
        }
        let pid = Data("\(getpid())\n".utf8)
        _ = ftruncate(descriptor, 0)
        pid.withUnsafeBytes { buffer in
            _ = write(descriptor, buffer.baseAddress, buffer.count)
        }
        return CollectionLease(fileURL: fileURL, descriptor: descriptor)
    }

    /// Best-effort diagnostic only; the lock, not the contents, is the truth.
    /// Read through the already-validated descriptor so diagnostics cannot
    /// follow a path substitution after the lock attempt.
    private static func holder(of descriptor: Int32) -> String? {
        var bytes = [UInt8](repeating: 0, count: 64)
        let count = bytes.withUnsafeMutableBytes { raw -> Int in
            guard let base = raw.baseAddress else { return -1 }
            return Darwin.pread(descriptor, base, raw.count, 0)
        }
        guard count > 0,
              let text = String(bytes: bytes.prefix(count), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text
    }

    deinit {
        close(descriptor)
    }
}
