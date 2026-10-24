import Foundation
import XCTest
@testable import MacUnseen

final class SupportConfigurationTests: XCTestCase {
    func testUnconfiguredPaymentsStayUnavailable() throws {
        let config = try JSONDecoder().decode(SupportConfiguration.self, from: Data("{}".utf8))
        XCTAssertNil(config.paypalLink)
        XCTAssertNil(config.qrCodeURL(for: .wechat, resourceDirectory: URL(fileURLWithPath: "/tmp")))
    }

    func testPayPalLinksRequireOfficialHTTPSDestination() {
        XCTAssertNotNil(SupportConfiguration(paypalURL: "https://paypal.me/example").paypalLink)
        XCTAssertNotNil(SupportConfiguration(paypalURL: "https://www.paypal.com/ncp/payment/example").paypalLink)
        for invalid in ["http://paypal.me/example", "https://paypal.me.example.com/pay", "https://user@paypal.com/pay", "https://paypal.com", "https://paypal.com:8080/pay"] {
            XCTAssertNil(SupportConfiguration(paypalURL: invalid).paypalLink)
        }
    }

    func testQRCodeResourcesAreLocalImages() {
        let directory = URL(fileURLWithPath: "/tmp/resources")
        XCTAssertEqual(SupportConfiguration(wechatQRCode: "wechat.png").qrCodeURL(for: .wechat, resourceDirectory: directory)?.path, "/tmp/resources/Support/wechat.png")
        for invalid in ["../wechat.png", "/tmp/wechat.png", "https://example.com/wechat.png", "wechat.svg", "..\\wechat.png"] {
            XCTAssertNil(SupportConfiguration(wechatQRCode: invalid).qrCodeURL(for: .wechat, resourceDirectory: directory))
        }
    }
}
