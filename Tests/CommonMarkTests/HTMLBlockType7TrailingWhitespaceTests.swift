/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// Start condition 7 (HTML blocks) lets only whitespace follow the tag, and whitespace includes line tabulation and
/// form feed (Characters and lines).
@Suite("Whitespace after a type 7 HTML block start tag")
struct HTMLBlockType7TrailingWhitespaceTests {
    private static let options: MarkdownDocument.ParseOptions = [.sourcePosition]

    private func surface(_ markdown: String) -> String {
        TreeDump.dump(markdown, options: Self.options, sourceRanges: true)
    }

    @Test func testLineTabulationAfterOpenTagStartsHTMLBlock() {
        #expect(surface("<a>\u{0B}") == "document @1:1-1:5\n  html_block \"<a>\\u{B}\\n\" @1:1-1:5\n")
    }

    @Test func testFormFeedAfterOpenTagStartsHTMLBlock() {
        #expect(surface("<a>\u{0C}") == "document @1:1-1:5\n  html_block \"<a>\\u{C}\\n\" @1:1-1:5\n")
    }

    @Test func testLineTabulationAfterClosingTagStartsHTMLBlock() {
        #expect(surface("</a>\u{0B}\nx") == "document @1:1-2:2\n  html_block \"</a>\\u{B}\\nx\\n\" @1:1-2:2\n")
    }

    @Test func testTextAfterLineTabulationIsParagraph() {
        #expect(surface("<a>\u{0B}x") == "document @1:1-1:6\n  paragraph @1:1-1:6\n    html_inline \"<a>\" @1:1-1:4\n    text \"\\u{B}x\" @1:4-1:6\n")
    }
}
