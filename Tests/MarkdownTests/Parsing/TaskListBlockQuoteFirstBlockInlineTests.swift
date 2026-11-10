/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest

/// A lazy continuation line of a block quote in a list item holds a NUL, which is replaced by U+FFFD (Insecure
/// characters), or a multibyte character, and a `[x]` that does not begin a paragraph and so is text (Task list items
/// (extension)). Inline content after it on the same line parses as usual.
class TaskListBlockQuoteFirstBlockInlineTests: XCTestCase {
    private func tree(_ markdown: String) -> String {
        Document(parsing: markdown, options: []).debugDescription(options: [])
    }

    func testEmphasis() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            ├─ Text \"2\u{fffd} [x] \"\n            └─ Emphasis\n               └─ Text \"b\"", tree("- > a\n  2\u{0} [x] *b*\n"))
    }

    func testStrong() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            ├─ Text \"2\u{fffd} [x] \"\n            └─ Strong\n               └─ Text \"b\"", tree("- > a\n  2\u{0} [x] **b**\n"))
    }

    func testCodeSpan() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            ├─ Text \"2\u{fffd} [x] \"\n            └─ InlineCode `b`", tree("- > a\n  2\u{0} [x] `b`\n"))
    }

    func testEntity() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            └─ Text \"2\u{fffd} [x] &\"", tree("- > a\n  2\u{0} [x] &amp;\n"))
    }

    func testLink() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            ├─ Text \"2\u{fffd} [x] \"\n            └─ Link destination: \"u\"\n               └─ Text \"l\"", tree("- > a\n  2\u{0} [x] [l](u)\n"))
    }

    func testAutolink() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            ├─ Text \"2\u{fffd} [x] \"\n            └─ Link destination: \"http://e.com\"\n               └─ Text \"http://e.com\"", tree("- > a\n  2\u{0} [x] <http://e.com>\n"))
    }

    func testHardBreakEndsLazyLine() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            ├─ Text \"2\u{fffd} [x] b\"\n            ├─ LineBreak\n            └─ Text \"c\"", tree("- > a\n  2\u{0} [x] b  \n  > c\n"))
    }

    func testEmphasisAcrossSecondLazyLine() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            ├─ Text \"2\u{fffd} [x] \"\n            └─ Emphasis\n               ├─ Text \"b\"\n               ├─ SoftBreak\n               └─ Text \"c\"", tree("- > a\n  2\u{0} [x] *b\nc*\n"))
    }

    func testMultiByteLazyLineEmphasis() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            ├─ Text \"22\u{E9} [x] \"\n            └─ Emphasis\n               └─ Text \"b\"", tree("- > a\n  22\u{E9} [x] *b*\n"))
    }
}
