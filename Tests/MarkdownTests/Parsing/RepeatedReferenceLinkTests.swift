/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

/// Every use of a link reference definition resolves (Link reference definitions), however long its
/// destination or title and however many times it is used.
class RepeatedReferenceLinkTests: XCTestCase {
    private static let markdown = "[bar]: /" + String(repeating: "a", count: 2000) + "\n\n"
        + Array(repeating: "[bar]", count: 60).joined(separator: " ")

    private func linkCount() -> Int {
        let options: ParseOptions = []
        let surface = Document(parsing: Self.markdown, options: options).debugDescription(options: [])
        return surface.components(separatedBy: "Link destination:").count - 1
    }

    private static func definition(_ label: String, destinationBytes: Int) -> String {
        "[\(label)]: /" + String(repeating: "a", count: destinationBytes - 1) + "\n\n"
    }

    private static func uses(_ use: String, _ count: Int) -> String {
        Array(repeating: use, count: count).joined(separator: " ")
    }

    private func surface(_ markdown: String) -> String {
        let options: ParseOptions = []
        return Document(parsing: markdown, options: options).debugDescription(options: [])
    }

    private func count(_ needle: String, in surface: String) -> Int {
        surface.components(separatedBy: needle).count - 1
    }

    private func links(_ markdown: String) -> Int {
        count("Link destination:", in: surface(markdown))
    }

    func testResolvesEveryUse() {
        XCTAssertEqual(60, linkCount())
    }

    func testFortyUsesResolve() {
        let markdown = Self.definition("bar", destinationBytes: 2001) + Self.uses("[bar]", 40)
        XCTAssertEqual(40, links(markdown))
    }

    func testFiftyUsesResolve() {
        XCTAssertEqual(50, links(Self.definition("bar", destinationBytes: 2000) + Self.uses("[bar]", 50)))
    }

    func testFiftyOneUsesResolve() {
        XCTAssertEqual(51, links(Self.definition("bar", destinationBytes: 2000) + Self.uses("[bar]", 51)))
    }

    func testEveryLabelResolves() {
        let markdown = Self.definition("a", destinationBytes: 2000) + Self.definition("b", destinationBytes: 2001)
            + Self.uses("[a]", 49) + " [b] [a] [a]"
        let result = surface(markdown)
        XCTAssertEqual(52, count("Link destination:", in: result))
        XCTAssertEqual(1, count("Link destination: \"/" + String(repeating: "a", count: 2000) + "\"", in: result))
    }

    func testFullReferenceResolves() {
        let markdown = Self.definition("a", destinationBytes: 2000) + Self.definition("b", destinationBytes: 2001)
            + Self.uses("[a]", 49) + " [a][b] [a] [a]"
        let result = surface(markdown)
        XCTAssertEqual(52, count("Link destination:", in: result))
        XCTAssertEqual(0, count("[a][b]", in: result))
    }

    func testFullAndCollapsedFormsAllResolve() {
        let markdown = Self.definition("bar", destinationBytes: 2001)
            + Self.uses("[bar]", 20) + " " + Self.uses("[bar][]", 20) + " " + Self.uses("[t][bar]", 20)
        XCTAssertEqual(60, links(markdown))
    }

    func testImageReferencesAllResolve() {
        let images = Self.definition("bar", destinationBytes: 2001) + Self.uses("![bar]", 60)
        XCTAssertEqual(60, count("Image source:", in: surface(images)))
        let mixed = Self.definition("bar", destinationBytes: 2001) + Self.uses("[bar] ![bar]", 30)
        let result = surface(mixed)
        XCTAssertEqual(30, count("Link destination:", in: result))
        XCTAssertEqual(30, count("Image source:", in: result))
    }

    func testTitledReferenceAllResolve() {
        let markdown = "[bar]: /" + String(repeating: "a", count: 999) + " \"" + String(repeating: "t", count: 1000) + "\"\n\n"
            + Self.uses("[bar]", 51)
        XCTAssertEqual(51, links(markdown))
    }

    func testEntityDestinationAllResolve() {
        let markdown = "[bar]: /" + String(repeating: "&amp;", count: 1999) + "\n\n" + Self.uses("[bar]", 51)
        XCTAssertEqual(51, links(markdown))
    }

    func testEscapedTitleAllResolve() {
        let title = String(repeating: "\\*", count: 500) + String(repeating: "&eacute;", count: 250)
        let markdown = "[bar]: /" + String(repeating: "a", count: 999) + " \"" + title + "\"\n\n"
            + Self.uses("[bar]", 51)
        XCTAssertEqual(51, links(markdown))
    }

    func testNULDestinationAllResolve() {
        let markdown = "[bar]: /" + String(repeating: "\u{0}", count: 666) + "a\n\n" + Self.uses("[bar]", 51)
        XCTAssertEqual(51, links(markdown))
    }

    func testLargeDocumentAllResolve() {
        let rest = Self.definition("bar", destinationBytes: 2001) + Self.uses("[bar]", 150)
        let fillerBytes = 101 * 2001 - rest.utf8.count - 2
        let exact = String(repeating: "\u{E9}", count: fillerBytes / 2) + "\n\n" + rest
        XCTAssertEqual(150, links(exact))
        let oneShort = String(repeating: "\u{E9}", count: fillerBytes / 2 - 1) + "x\n\n" + rest
        XCTAssertEqual(150, links(oneShort))
    }

    /// `[bar]` names no inline attribute definition, so after each `^[t]` it is a link.
    func testAttributeLookupOfLinkReference() {
        let markdown = Self.definition("bar", destinationBytes: 2001) + Self.uses("^[t][bar]", 10) + " " + Self.uses("[bar]", 60)
        let result = surface(markdown)
        XCTAssertEqual(0, count("InlineAttributes", in: result))
        XCTAssertEqual(70, count("Link destination:", in: result))
    }

    /// The inline form of each inline attribute resolves, and so does the `[bar]` after it.
    func testAttributeLookupAfterInlineForm() {
        let markdown = Self.definition("bar", destinationBytes: 2001) + Self.uses("^[t](a)[bar]", 10) + " " + Self.uses("[bar]", 60)
        let result = surface(markdown)
        XCTAssertEqual(10, count("InlineAttributes", in: result))
        XCTAssertEqual(70, count("Link destination:", in: result))
    }

    func testEveryBlockResolves() {
        let markdown = Self.definition("bar", destinationBytes: 2001) + "# " + Self.uses("[bar]", 30) + "\n\n"
            + Self.uses("[bar]", 30)
        let result = surface(markdown)
        let paragraph = result.components(separatedBy: "Paragraph").last!
        XCTAssertEqual(60, count("Link destination:", in: result))
        XCTAssertEqual(30, count("Link destination:", in: paragraph))
    }
}
