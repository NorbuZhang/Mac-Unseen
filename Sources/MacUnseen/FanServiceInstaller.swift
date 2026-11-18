import CryptoKit
import Foundation

enum FanServiceInstallError: LocalizedError {
    case invalidPackage, cancelled, failed(String), starting

    var errorDescription: String? {
        switch self {
        case .invalidPackage: tr("风扇组件缺失或校验失败，请重新解压完整的应用包。")
        case .cancelled: tr("已取消风扇服务授权。")
        case .failed(let message): message
        case .starting: tr("安装已完成，正在等待风扇服务响应。")
        }
    }
}

enum FanServiceInstaller {
    static func install() throws {
        guard let package = Bundle.main.url(forResource: "FanService", withExtension: "pkg"),
              let expected = Bundle.main.object(forInfoDictionaryKey: "FanServiceSHA256") as? String else {
            throw FanServiceInstallError.invalidPackage
        }
        let data = try Data(contentsOf: package)
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == expected else { throw FanServiceInstallError.invalidPackage }

        let stage = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: stage) }
        let source = stage.appendingPathComponent("FanService.pkg")
        try data.write(to: source, options: .atomic)

        // The authorized process checks its own private copy before invoking Installer.
        // Only the package whose digest is sealed into this app may be installed.
        let script = #"""
        on run argv
            set sourceFile to quoted form of item 1 of argv
            set checksum to quoted form of item 2 of argv
            set installCommand to "set -eu; umask 077; dir=$(/usr/bin/mktemp -d /private/tmp/MacUnseenFan.XXXXXXXX); trap '/bin/rm -rf \"$dir\"' EXIT; /bin/cp " & sourceFile & " \"$dir/service.pkg\"; cd \"$dir\"; /usr/bin/printf '%s  service.pkg\\n' " & checksum & " | /usr/bin/shasum -a 256 -c -; /usr/sbin/installer -pkg service.pkg -target /"
            do shell script installCommand with administrator privileges
        end run
        """#
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.currentDirectoryURL = URL(fileURLWithPath: "/")
        process.arguments = ["-e", script, source.path, actual]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            if message.contains("(-128)") { throw FanServiceInstallError.cancelled }
            throw FanServiceInstallError.failed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
