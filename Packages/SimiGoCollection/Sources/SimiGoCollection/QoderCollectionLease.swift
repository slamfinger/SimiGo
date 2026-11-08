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
final class QoderCollectionLease {
    static let lockFileName = "collector.lock"

    let fileURL: URL
    private let descriptor: Int32

    private init(fileURL: URL, descriptor: Int32) {
        self.fileURL = fileURL
        self.descriptor = descriptor
    }

    static func acquire(directoryURL: URL) throws -> QoderCollectionLease {
        try FileManager.default.createDirectory(
            at: directoryURL, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let directoryDescriptor = open(
            directoryURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directoryDescriptor >= 0 else {
            throw QoderCollectionStateError.unreadableState(
                path: directoryURL.path, detail: "state directory is linked or unreadable")
        }
        defer { close(directoryDescriptor) }
        var directoryInfo = stat()
        guard fstat(directoryDescriptor, &directoryInfo) == 0,
              (directoryInfo.st_mode & S_IFMT) == S_IFDIR,
              directoryInfo.st_uid == getuid(),
              fchmod(directoryDescriptor, 0o700) == 0
        else {
            throw QoderCollectionStateError.unreadableState(
                path: directoryURL.path, detail: "state directory is not a private owned directory")
        }
        let fileURL = directoryURL.appendingPathComponent(lockFileName)
        // Anchor the lock open to the validated directory descriptor and open
        // it non-blocking: a planted FIFO at this name must fail the open or
        // the post-open regular-file check, never block the runner. Resolving
        // fileURL by path here would race a directory swap between the
        // directory validation above and this open.
        let descriptor = openat(
            directoryDescriptor, lockFileName,
            O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK, 0o600)
        guard descriptor >= 0 else {
            throw QoderCollectionStateError.unreadableState(
                path: fileURL.path, detail: String(cString: strerror(errno)))
        }
        var lockInfo = stat()
        guard fstat(descriptor, &lockInfo) == 0,
              (lockInfo.st_mode & S_IFMT) == S_IFREG,
              lockInfo.st_uid == getuid(),
              lockInfo.st_nlink == 1,
              (lockInfo.st_mode & (S_IWGRP | S_IWOTH)) == 0,
              fchmod(descriptor, 0o600) == 0
        else {
            close(descriptor)
            throw QoderCollectionStateError.unreadableState(
                path: fileURL.path, detail: "lock entry is not a regular owned file")
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            // Read the diagnostic PID from the exact inode whose lock attempt
            // failed. Re-opening fileURL after closing this descriptor would
            // re-resolve a mutable path and could follow a swapped symlink.
            let holderPID = code == EWOULDBLOCK ? holder(of: descriptor) : nil
            close(descriptor)
            guard code == EWOULDBLOCK else {
                throw QoderCollectionStateError.unreadableState(
                    path: fileURL.path, detail: String(cString: strerror(code)))
            }
            throw QoderCollectionStateError.stateAlreadyOwned(
                path: fileURL.path,
                detail: holderPID.map { "held by pid \($0)" }
                    ?? "held by another runner")
        }
        let pid = Data("\(getpid())\n".utf8)
        _ = ftruncate(descriptor, 0)
        pid.withUnsafeBytes { buffer in
            _ = write(descriptor, buffer.baseAddress, buffer.count)
        }
        return QoderCollectionLease(fileURL: fileURL, descriptor: descriptor)
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
