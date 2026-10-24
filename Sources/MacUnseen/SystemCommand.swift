import Foundation
import Darwin

/// One command per job. Cancellation stops the child as well as its awaiting Task.
/// The blocking read belongs on a utility executor, never the main actor.
final class SystemCommand: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return process?.isRunning == true
    }

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled else { return }
        cancelled = true
        guard let process, process.isRunning else { return }
        process.terminate()
        // A stuck reader must not survive a page switch until the old timeout.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) { [weak process] in
            if let process, process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }

    func run(executable: String, arguments: [String], timeout: TimeInterval) -> Data? {
        let child = Process()
        let output = Pipe()
        child.executableURL = URL(fileURLWithPath: executable)
        child.arguments = arguments
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = output
        child.standardError = FileHandle.nullDevice
        defer {
            try? output.fileHandleForReading.close()
            try? output.fileHandleForWriting.close()
        }
        lock.lock()
        guard !cancelled, process == nil else { lock.unlock(); return nil }
        process = child
        do { try child.run() }
        catch { process = nil; lock.unlock(); return nil }
        lock.unlock()
        let deadline = DispatchWorkItem { [weak self] in self?.cancel() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: deadline)
        defer {
            deadline.cancel()
            lock.lock(); process = nil; lock.unlock()
        }
        // Drain while the command runs, so output larger than the pipe cannot deadlock.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        child.waitUntilExit()
        lock.lock(); let wasCancelled = cancelled; lock.unlock()
        return !wasCancelled && child.terminationStatus == 0 ? data : nil
    }
}
