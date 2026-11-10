/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest

/// Numeric character references to noncharacters decode to the noncharacter itself, since each is a valid
/// code point (Entity and numeric character references).
class NoncharacterEntityTests: XCTestCase {
    // Swift string literals reject the escape `\u{FDD0}`, so it is built from its scalar.
    private static let uFDD0 = String(Unicode.Scalar(0xFDD0 as UInt32)!)

    private func surface(_ markdown: String) -> String {
        Document(parsing: markdown).debugDescription(options: [])
    }

    private static func text(_ literal: String) -> String {
        "Document\n└─ Paragraph\n   └─ Text \"\(literal)\""
    }

    // An Image, because the debug description prints a Link's destination but not its title.
    private static func image(source: String, title: String) -> String {
        "Document\n└─ Paragraph\n   └─ Image source: \"\(source)\" title: \"\(title)\"\n      └─ Text \"a\""
    }

    private static func autolink(_ url: String) -> String {
        "Document\n└─ Paragraph\n   └─ Link destination: \"\(url)\"\n      └─ Text \"\(url)\""
    }

    func testOtherNoncharactersAndReplacementCharacterDecode() {
        XCTAssertEqual(Self.text(Self.uFDD0), surface("&#xFDD0;"))
        XCTAssertEqual(Self.text("\u{1FFFE}"), surface("&#x1FFFE;"))
        XCTAssertEqual(Self.text("\u{10FFFF}"), surface("&#x10FFFF;"))
        XCTAssertEqual(Self.text("\u{FFFD}"), surface("&#xFFFD;"))
        XCTAssertEqual(Self.image(source: "/" + Self.uFDD0, title: "\u{1FFFE}"), surface("![a](/&#xFDD0; \"&#x1FFFE;\")"))
        XCTAssertEqual(Self.image(source: "/\u{10FFFF}", title: "\u{FFFD}"), surface("![a](/&#x10FFFF; \"&#xFFFD;\")"))
        XCTAssertEqual(Self.autolink("op:" + Self.uFDD0 + "\u{1FFFE}\u{10FFFF}\u{FFFD}"), surface("<op:&#xFDD0;&#x1FFFE;&#x10FFFF;&#xFFFD;>"))
    }

    func testUFFFEAndUFFFFDecode() {
        XCTAssertEqual(Self.text("\u{FFFE}\u{FFFF}"), surface("&#xFFFE;&#65535;"))
        XCTAssertEqual(Self.text("\u{FFFE}"), surface("&#xFFFE;"))
        XCTAssertEqual(Self.text("\u{FFFE}"), surface("&#65534;"))
        XCTAssertEqual(Self.text("\u{FFFF}"), surface("&#xFFFF;"))
        XCTAssertEqual(Self.text("\u{FFFF}"), surface("&#65535;"))
        XCTAssertEqual(Self.image(source: "/\u{FFFF}", title: "\u{FFFE}"), surface("![a](/&#xFFFF; \"&#xFFFE;\")"))
        XCTAssertEqual(Self.image(source: "/\u{FFFE}", title: "\u{FFFF}"), surface("![a]\n\n[a]: /&#xFFFE; \"&#65535;\""))
        XCTAssertEqual(Self.autolink("op:\u{FFFF}"), surface("<op:&#xFFFF;>"))
        let document = Document(parsing: "```&#xFFFE;\n```", options: [])
        XCTAssertEqual("\u{FFFE}", (document.child(at: 0) as? CodeBlock)?.language)
    }
}
