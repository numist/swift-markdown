/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest

/// Inline links and images that begin on an indented paragraph continuation line, with a link title that
/// spans lines. A single-quoted title contains `'` only when backslash-escaped (Links), so it ends at the
/// first unescaped `'`, which may be on a later line.
class LinkTitleAcrossIndentedContinuationTests: XCTestCase {
    private func tree(_ markdown: String) -> String {
        Document(parsing: markdown, options: []).debugDescription(options: [])
    }

    // Images, because the debug description prints an Image's title but not a Link's.

    func testEscapedParenDestination() {
        XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"x\"\n   ├─ SoftBreak\n   └─ Image source: \"(\" title: \"'\n\"", tree("x\n ![](\\(\n'\\'\n')"))
    }

    func testTitleSpanningThreeLines() {
        XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"x\"\n   ├─ SoftBreak\n   └─ Image source: \"a\" title: \"'\nb\n\"", tree("x\n ![](a\n'\\'\nb\n')"))
    }

    /// The title ends at the `'` on the next line, which no `)` follows, so no link forms.
    func testLongestTitleWithoutCloserIsNotALink() {
        XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"x\"\n   ├─ SoftBreak\n   ├─ Text \"[](a ’')\"\n   ├─ SoftBreak\n   └─ Text \"’\"", tree("x\n [](a '\\')\n'"))
    }

    /// A `<…>` link destination cannot contain a line ending (Links), so no link forms.
    func testPointyDestinationWithBareLineEndIsNotALink() {
        XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"x\"\n   ├─ SoftBreak\n   ├─ Text \"[](\"\n   ├─ InlineHTML <a\nb>\n   └─ Text \")\"", tree("x\n [](<a\nb>)"))
    }
}
