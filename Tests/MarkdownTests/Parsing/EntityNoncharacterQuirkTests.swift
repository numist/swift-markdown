/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

/// Flag-OFF keeps the scalar, which CommonMark §6.5
/// treats as a valid code point. Position-free compare surface.
class EntityNoncharacterQuirkTests: XCTestCase {
    // Swift string literals reject noncharacter escapes such as `\u{FDD0}`, so these are built from scalars.
    private static let uFFFE = String(Unicode.Scalar(0xFFFE as UInt32)!)
    private static let uFFFF = String(Unicode.Scalar(0xFFFF as UInt32)!)
    private static let uFDD0 = String(Unicode.Scalar(0xFDD0 as UInt32)!)
    private static let u1FFFE = String(Unicode.Scalar(0x1FFFE as UInt32)!)

    private func surface(_ markdown: String) -> String {
        Document(parsing: markdown).debugDescription(options: [])
    }

    private static func text(_ literal: String) -> String {
        "Document\n└─ Paragraph\n   └─ Text \"\(literal)\""
    }

    // An Image, because the surface prints a Link's destination but not its title.
    private static func image(source: String, title: String) -> String {
        "Document\n└─ Paragraph\n   └─ Image source: \"\(source)\" title: \"\(title)\"\n      └─ Text \"a\""
    }

    private static func autolink(_ url: String) -> String {
        "Document\n└─ Paragraph\n   └─ Link destination: \"\(url)\"\n      └─ Text \"\(url)\""
    }

    // MARK: Agreeing controls — other scalars survive under both flags

    func testOtherScalarsSurviveUnderBothFlags() {
        XCTAssertEqual(Self.text(Self.uFDD0), surface("&#xFDD0;"))
        XCTAssertEqual(Self.text(Self.u1FFFE), surface("&#x1FFFE;"))
        XCTAssertEqual(Self.text("\u{10FFFF}"), surface("&#x10FFFF;"))
        XCTAssertEqual(Self.text("\u{FFFD}"), surface("&#xFFFD;"))
        XCTAssertEqual(Self.image(source: "/" + Self.uFDD0, title: Self.u1FFFE), surface("![a](/&#xFDD0; \"&#x1FFFE;\")"))
        XCTAssertEqual(Self.image(source: "/\u{10FFFF}", title: "\u{FFFD}"), surface("![a](/&#x10FFFF; \"&#xFFFD;\")"))
        XCTAssertEqual(Self.autolink("op:" + Self.uFDD0 + Self.u1FFFE + "\u{10FFFF}\u{FFFD}"), surface("<op:&#xFDD0;&#x1FFFE;&#x10FFFF;&#xFFFD;>"))
    }

    // MARK: Flag OFF — the deliverable keeps the noncharacter scalar

    func testFlagOffKeepsNoncharacters() {
        XCTAssertEqual(Self.text(Self.uFFFE + Self.uFFFF), surface("&#xFFFE;&#65535;"))
        XCTAssertEqual(Self.text(Self.uFFFE), surface("&#xFFFE;"))
        XCTAssertEqual(Self.text(Self.uFFFF), surface("&#xFFFF;"))
        XCTAssertEqual(Self.text(Self.uFFFF), surface("&#65535;"))
        XCTAssertEqual(Self.image(source: "/" + Self.uFFFF, title: Self.uFFFE), surface("![a](/&#xFFFF; \"&#xFFFE;\")"))
        XCTAssertEqual(Self.image(source: "/" + Self.uFFFE, title: Self.uFFFF), surface("![a]\n\n[a]: /&#xFFFE; \"&#65535;\""))
        XCTAssertEqual(Self.autolink("op:" + Self.uFFFF), surface("<op:&#xFFFF;>"))
        let document = Document(parsing: "```&#xFFFE;\n```", options: [])
        XCTAssertEqual(Self.uFFFE, (document.child(at: 0) as? CodeBlock)?.language)
    }
}
