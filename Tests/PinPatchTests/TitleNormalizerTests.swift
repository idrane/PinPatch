import XCTest
@testable import PinPatch

final class TitleNormalizerTests: XCTestCase {
    func testPreservesRoomNumbers() {
        XCTAssertEqual(PPTitleNormalizer.normalize("301호"), "301호")
        XCTAssertEqual(PPTitleNormalizer.normalize("302호"), "302호")
        XCTAssertEqual(PPTitleNormalizer.normalize("주문번호 12345 · 301호"), "{order} · 301호")
        XCTAssertEqual(PPTitleNormalizer.normalize("주문번호 301호"), "주문번호 301호")
    }

    func testMasksExplicitOrderIdentifiers() {
        XCTAssertEqual(PPTitleNormalizer.normalize("주문번호 12345"), "{order}")
        XCTAssertEqual(PPTitleNormalizer.normalize("Order ID AB-123"), "{order}")
    }

    func testPreservesOrdinaryNumbers() {
        XCTAssertEqual(PPTitleNormalizer.normalize("레벨 12"), "레벨 12")
    }

    func testNormalizesOnlyWhitespaceAndNFCByDefault() {
        XCTAssertEqual(PPTitleNormalizer.normalize("  Cafe\u{301}   12  "), "Café 12")
    }
}
