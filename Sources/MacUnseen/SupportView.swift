import AppKit
import SwiftUI

enum SupportMethod: String, CaseIterable, Identifiable {
    case wechat, alipay, paypal
    var id: String { rawValue }
    var title: String {
        switch self { case .wechat: "微信"; case .alipay: "支付宝"; case .paypal: "PayPal" }
    }
}

struct SupportConfiguration: Decodable {
    var wechatQRCode: String?
    var alipayQRCode: String?
    var paypalURL: String?

    static func load(bundle: Bundle = .main) -> Self {
        guard let url = bundle.url(forResource: "payment-methods", withExtension: "json", subdirectory: "Support"),
              let data = try? Data(contentsOf: url),
              let configuration = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return configuration
    }

    var paypalLink: URL? {
        guard let paypalURL, let url = URL(string: paypalURL), url.scheme == "https",
              let host = url.host?.lowercased(),
              ["paypal.me", "www.paypal.me", "paypal.com", "www.paypal.com"].contains(host),
              url.user == nil, url.password == nil, url.port == nil,
              url.path != "", url.path != "/" else { return nil }
        return url
    }

    func qrCodeURL(for method: SupportMethod, resourceDirectory: URL?) -> URL? {
        let filename: String? = switch method { case .wechat: wechatQRCode; case .alipay: alipayQRCode; case .paypal: nil }
        guard let filename, !filename.isEmpty, let resourceDirectory,
              filename == (filename as NSString).lastPathComponent,
              !filename.contains("\\"),
              ["png", "jpg", "jpeg"].contains((filename as NSString).pathExtension.lowercased()) else { return nil }
        return resourceDirectory.appendingPathComponent("Support", isDirectory: true).appendingPathComponent(filename)
    }
}

struct SupportView: View {
    @EnvironmentObject private var languageSettings: LanguageSettings

    var body: some View {
        Page(title: "请我喝杯奶茶", subtitle: "感谢你使用 Mac Unseen。") {
            SupportCard(language: languageSettings.language)
                .id(languageSettings.language)
        }
    }
}

/// Keep only the displayed QR image, for this page's lifetime.
@MainActor
private final class SupportAssets: ObservableObject {
    static let configuration = SupportConfiguration.load()
    private var imageURL: URL?
    private var cachedImage: NSImage?

    func image(at url: URL) -> NSImage? {
        if imageURL == url { return cachedImage }
        guard let image = NSImage(contentsOf: url) else { return nil }
        cachedImage = image
        imageURL = url
        return image
    }

    func clear() { imageURL = nil; cachedImage = nil }
}

struct SupportCard: View {
    @Environment(\.openURL) private var openURL
    @State private var method: SupportMethod
    @StateObject private var assets = SupportAssets()
    private let configuration = SupportAssets.configuration

    init(language: AppLanguage) {
        _method = State(initialValue: language == .english ? .paypal : .wechat)
    }

    var body: some View {
        Card(title: "支持开发", symbol: "cup.and.saucer", tint: .orange) {
            Text(tr("如果你喜欢 Mac Unseen，欢迎请我喝杯奶茶，支持我继续开发和完善它。谢谢！"))
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    feedbackPrompt.fixedSize()
                    feedbackLink.fixedSize()
                }
                VStack(alignment: .leading, spacing: 4) {
                    feedbackPrompt.fixedSize(horizontal: false, vertical: true)
                    feedbackLink
                }
            }.font(.callout)
            Picker(tr("支持方式"), selection: $method) {
                ForEach(SupportMethod.allCases) { method in
                    Text(tr(method.title)).tag(method)
                }
            }
            .pickerStyle(.segmented).frame(maxWidth: 360)
            paymentContent
        }
        .onChange(of: method) { _, method in if method == .paypal { assets.clear() } }
        .onDisappear { assets.clear() }
    }

    private var feedbackPrompt: some View {
        Text(tr("有好的建议，或是发现了 Bug？欢迎在这里反馈："))
            .foregroundStyle(.secondary)
    }

    private var feedbackLink: some View {
        Link("GitHub Issues", destination: URL(string: "https://github.com/NorbuZhang/Mac-Unseen/issues")!)
            .foregroundStyle(AppPalette.accentText)
    }

    @ViewBuilder private var paymentContent: some View {
        if method == .paypal, let link = configuration.paypalLink {
            Text(tr("金额随心，付款将在 PayPal 页面完成。"))
                .font(.callout).foregroundStyle(.secondary)
            Button {
                openURL(link)
            } label: {
                Label(tr("用 PayPal 支持"), systemImage: "arrow.up.right.square")
            }.buttonStyle(.borderedProminent).controlSize(.large)
        } else if method != .paypal,
                  let url = configuration.qrCodeURL(for: method, resourceDirectory: Bundle.main.resourceURL),
                  let image = assets.image(at: url) {
            Image(nsImage: image).resizable().interpolation(.none).scaledToFit()
                .frame(maxWidth: 280, maxHeight: 360).padding(12)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel(tr(method == .wechat ? "微信收款二维码" : "支付宝收款二维码"))
            Text(tr(method == .wechat ? "打开微信扫一扫，金额随心。" : "打开支付宝扫一扫，金额随心。"))
                .font(.callout).foregroundStyle(.secondary)
        } else {
            Text(tr(method == .paypal ? "PayPal 收款链接准备中，感谢你的支持。" : "收款二维码准备中，感谢你的支持。"))
                .font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
        }
    }
}
