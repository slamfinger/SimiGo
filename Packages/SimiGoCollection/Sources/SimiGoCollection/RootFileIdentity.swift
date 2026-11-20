import Darwin

/// The shared identity floor for hardened descriptor opens in this package:
/// fstat succeeds, the entry is a regular file, it is owned by the expected
/// user, and its link count is one (no hard-link aliasing). Call sites keep
/// their own additional predicates (size bounds, inode expectation, permission
/// bits, fchmod) and their own error surfaces.
enum RootFileIdentity {
    static func privateRegularFileInfo(
        fd: Int32, expectedOwner: uid_t = getuid()
    ) -> stat? {
        var info = stat()
        guard fstat(fd, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == expectedOwner,
              info.st_nlink == 1 else {
            return nil
        }
        return info
    }
}