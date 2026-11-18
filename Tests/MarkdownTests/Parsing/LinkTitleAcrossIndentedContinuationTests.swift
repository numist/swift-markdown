/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest

class LinkTitleAcrossIndentedContinuationTests: XCTestCase {
    private func tree(_ markdown: String) -> String {
        Document(parsing: markdown, options: []).debugDescription(options: [])
    }

    // The cases that check a title use images, because the debug description prints an Image's title but not a Link's.

    func testEscapedParenDestination() {
        XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"x\"\n   ├─ SoftBreak\n   └─ Image source: \"(\" title: \"'\n\"", tree("x\n ![](\\(\n'\\'\n')"))
    }

    func testTitleSpanningThreeLines() {
        XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"x\"\n   ├─ SoftBreak\n   └─ Image source: \"a\" title: \"'\nb\n\"", tree("x\n ![](a\n'\\'\nb\n')"))
    }

    // The title ends at the `'` on the next line, which no `)` follows, so no link forms.
    func testLongestTitleWithoutCloserIsNotALink() {
        XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"x\"\n   ├─ SoftBreak\n   ├─ Text \"[](a ’')\"\n   ├─ SoftBreak\n   └─ Text \"’\"", tree("x\n [](a '\\')\n'"))
    }

    func testPointyDestinationWithBareLineEndIsNotALink() {
        XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"x\"\n   ├─ SoftBreak\n   ├─ Text \"[](\"\n   ├─ InlineHTML <a\nb>\n   └─ Text \")\"", tree("x\n [](<a\nb>)"))
    }
}
