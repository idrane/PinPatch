import XCTest
@testable import PinPatch

final class TitleNormalizerTests: XCTestCase {
    func testPreservesRoomNumbers() {
        XCTAssertEqual(PPTitleNormalizer.normalize("Room 301"), "Room 301")
        XCTAssertEqual(PPTitleNormalizer.normalize("Room 302"), "Room 302")
        XCTAssertEqual(PPTitleNormalizer.normalize("Order number 12345 · Room 301"), "{order} · Room 301")
        XCTAssertEqual(PPTitleNormalizer.normalize("Order number Room 301"), "Order number Room 301")
    }

    func testMasksExplicitOrderIdentifiers() {
        XCTAssertEqual(PPTitleNormalizer.normalize("Order number 12345"), "{order}")
        XCTAssertEqual(PPTitleNormalizer.normalize("Order ID AB-123"), "{order}")
    }

    func testPreservesOrdinaryNumbers() {
        XCTAssertEqual(PPTitleNormalizer.normalize("Level 12"), "Level 12")
    }

    func testNormalizesOnlyWhitespaceAndNFCByDefault() {
        XCTAssertEqual(PPTitleNormalizer.normalize("  Cafe\u{301}   12  "), "Café 12")
    }
}
