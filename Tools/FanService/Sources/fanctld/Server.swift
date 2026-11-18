import Foundation
import FanCore

/// Minimal Unix-socket JSON-lines server. One thread per connection; requests
/// are tiny and infrequent (a menu bar app polling every couple of seconds).
final class SocketServer {
    private let path = geteuid() == 0
        ? FanControlConstants.socketPath
        : FanControlConstants.fallbackSocketPath
    private var listenFD: Int32 = -1
    private let handler: (DaemonRequest) -> DaemonResponse

    init(handler: @escaping (DaemonRequest) -> DaemonResponse) {
        self.handler = handler
    }

    func start() throws {
        unlink(path)

        listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            path.utf8CString.withUnsafeBytes { src in
                raw.copyMemory(from: UnsafeRawBufferPointer(rebasing: src.prefix(raw.count - 1)))
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(listenFD, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        // Any local user can read status; writes are gated by peer credentials below.
        chmod(path, 0o666)

        guard listen(listenFD, 16) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        let fd = listenFD
        let slots = DispatchSemaphore(value: 8)
        Thread.detachNewThread { [weak self] in
            while true {
                let client = accept(fd, nil, nil)
                if client < 0 {
                    if errno == EINTR { continue }
                    break
                }
                guard slots.wait(timeout: .now()) == .success else { close(client); continue }
                Thread.detachNewThread {
                    defer { slots.signal() }
                    self?.serve(client: client)
                }
            }
        }
        log("listening on \(path)")
    }

    func stop() {
        if listenFD >= 0 { close(listenFD) }
        unlink(path)
    }

    // MARK: Per-connection

    /// Mutating commands are only accepted from root or members of the admin group.
    private func peerMayControl(_ fd: Int32) -> Bool {
        var cred = xucred()
        var len = socklen_t(MemoryLayout<xucred>.size)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERCRED, &cred, &len) == 0 else {
            return false
        }
        if cred.cr_uid == 0 { return true }
        let adminGID: gid_t = 80
        let groupCount = min(Int(cred.cr_ngroups), 16)
        return withUnsafeBytes(of: cred.cr_groups) { raw in
            raw.bindMemory(to: gid_t.self).prefix(groupCount).contains(adminGID)
        }
    }

    private func serve(client: Int32) {
        defer { close(client) }

        var noSigpipe: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSigpipe, socklen_t(MemoryLayout<Int32>.size))

        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while buffer.count < 65536 {
            let n = read(client, &chunk, chunk.count)
            if n <= 0 { return }
            buffer.append(contentsOf: chunk[0..<n])
            if chunk[0..<n].contains(0x0A) { break }
        }
        guard let newline = buffer.firstIndex(of: 0x0A) else { return }

        var response: DaemonResponse
        do {
            let request = try JSONDecoder().decode(DaemonRequest.self, from: buffer[..<newline])
            if request.cmd == "set" && !peerMayControl(client) {
                response = DaemonResponse(ok: false, error: "permission denied (admin required)")
            } else {
                response = handler(request)
            }
        } catch {
            response = DaemonResponse(ok: false, error: "bad request: \(error)")
        }

        if var payload = try? JSONEncoder().encode(response) {
            payload.append(0x0A)
            payload.withUnsafeBytes { raw in
                _ = write(client, raw.baseAddress, raw.count)
            }
        }
    }
}
