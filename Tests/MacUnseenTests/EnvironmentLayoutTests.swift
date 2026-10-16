import XCTest
@testable import MacUnseen

final class EnvironmentLayoutTests: XCTestCase {
    func testBothTopCardsResizeWithContainer() {
        let narrow = EnvironmentTopCardLayout.widths(totalWidth: 760)
        let wide = EnvironmentTopCardLayout.widths(totalWidth: 1_060)

        XCTAssertGreaterThan(wide.angle, narrow.angle)
        XCTAssertGreaterThan(wide.ambient, narrow.ambient)
        XCTAssertEqual(narrow.angle, narrow.ambient)
        XCTAssertEqual(wide.angle, wide.ambient)
        XCTAssertEqual(
            narrow.angle + narrow.ambient + EnvironmentTopCardLayout.spacing,
            760
        )
        XCTAssertEqual(
            wide.angle + wide.ambient + EnvironmentTopCardLayout.spacing,
            1_060
        )
    }
}
