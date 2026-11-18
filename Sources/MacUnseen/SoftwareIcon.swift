import AppKit
import SwiftUI

/// Resolve icons only for software records, without opening arbitrary reported paths.
struct SoftwareIcon: View {
    let name: String
    var path: String?
    var identifier: String?
    var pid: pid_t?
    var apple = false
    var lookupByName = false

    init(process: ProcessReading) {
        name = process.application?.name ?? process.name
        path = process.application?.bundlePath ?? process.executablePath
        pid = process.id.pid
        apple = process.id.pid == 0
    }

    init(record: SystemReportNode) {
        func field(_ names: String...) -> String? {
            record.children?.first { names.contains($0.label) }?.value
        }
        name = record.label
        path = field("Location", "Path", "Full Path")
        identifier = field("Bundle ID", "Bundle Identifier", "Identifier")
        apple = field("Source", "Obtained from") == "Apple" || field("Developer", "Manufacturer") == "Apple Inc."
        lookupByName = true
    }

    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 512
        return cache
    }()

    static func systemPath(_ path: String) -> Bool {
        ["/System/", "/usr/libexec/", "/usr/bin/", "/usr/sbin/", "/usr/lib/", "/bin/", "/sbin/",
         "/Library/Apple/"].contains { path.hasPrefix($0) }
    }

    private func icon() -> NSImage {
        let key = [name, path ?? "", identifier ?? "", String(apple), String(lookupByName)].joined(separator: "\u{0}") as NSString
        if let cached = Self.cache.object(forKey: key) { return cached }
        let workspace = NSWorkspace.shared
        let fallback = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
        let appleIcon = NSImage(systemSymbolName: "apple.logo", accessibilityDescription: nil) ?? fallback
        var result = fallback
        if apple || identifier?.hasPrefix("com.apple.") == true || path.map(Self.systemPath) == true {
            result = appleIcon
        } else {
            let roots = ["/Applications/", NSHomeDirectory() + "/Applications/"]
            var candidate = path.flatMap(ProcessApplication.bundlePath)
            if candidate == nil, let identifier {
                candidate = workspace.urlForApplication(withBundleIdentifier: identifier)?.path
            }
            if candidate == nil, lookupByName, !name.contains("/"), !name.isEmpty {
                let filename = name.hasSuffix(".app") ? name : name + ".app"
                candidate = (roots + ["/System/Applications/", "/System/Applications/Utilities/"])
                    .map { $0 + filename }.first { FileManager.default.fileExists(atPath: $0) }
            }
            if let candidate, Self.systemPath(candidate) {
                result = appleIcon
            } else if let candidate, roots.contains(where: { candidate.hasPrefix($0) }) {
                let url = URL(fileURLWithPath: candidate).resolvingSymlinksInPath().standardizedFileURL
                if roots.contains(where: { url.path.hasPrefix($0) }), let bundle = Bundle(url: url) {
                    result = bundle.bundleIdentifier?.hasPrefix("com.apple.") == true ? appleIcon : workspace.icon(forFile: url.path)
                }
            } else if let pid, let running = NSRunningApplication(processIdentifier: pid),
                      let url = running.bundleURL, url.path == candidate {
                result = running.bundleIdentifier?.hasPrefix("com.apple.") == true ? appleIcon : running.icon ?? fallback
            }
        }
        Self.cache.setObject(result, forKey: key)
        return result
    }

    var body: some View {
        Image(nsImage: icon()).resizable().scaledToFit()
            .frame(width: 17, height: 17).accessibilityHidden(true)
    }
}
