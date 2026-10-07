/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

class TaskListRetryLazyOrphanInlineTests: XCTestCase {
    private func surface(_ markdown: String) -> String {
        Document(parsing: markdown, options: []).debugDescription(options: [])
    }

    /// Flag-off (spec-correct): the item's first block is a block quote, not a paragraph (GFM task list
    /// items), so the item has no checkbox and the lazy line keeps its `2` prefix ahead of the emphasis,
    /// where cmark's later-line checkbox retry checks the item and drops the advanced bytes.
    func testEmphasisFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            ├─ Text \"2\u{fffd} [x] \"\n            └─ Emphasis\n               └─ Text \"b\"", surface("- > a\n  2\u{0} [x] *b*\n"))
    }

    /// Flag-off (spec-correct): the item's first block is a block quote, not a paragraph (GFM task list
    /// items), so the item has no checkbox and the lazy line keeps its `2` prefix ahead of the strong
    /// emphasis, where cmark's later-line checkbox retry checks the item and drops the advanced bytes.
    func testStrongFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            ├─ Text \"2\u{fffd} [x] \"\n            └─ Strong\n               └─ Text \"b\"", surface("- > a\n  2\u{0} [x] **b**\n"))
    }

    /// Flag-off (spec-correct): the item's first block is a block quote, not a paragraph (GFM task list
    /// items), so the item has no checkbox and the lazy line keeps its `2` prefix ahead of the code span,
    /// where cmark's later-line checkbox retry checks the item and drops the advanced bytes.
    func testCodeSpanFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            ├─ Text \"2\u{fffd} [x] \"\n            └─ InlineCode `b`", surface("- > a\n  2\u{0} [x] `b`\n"))
    }

    /// Flag-off (spec-correct): the item's first block is a block quote, not a paragraph (GFM task list
    /// items), so the item has no checkbox and the lazy line keeps its `2` prefix ahead of the decoded
    /// entity, where cmark's later-line checkbox retry checks the item and drops the advanced bytes.
    func testEntityFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            └─ Text \"2\u{fffd} [x] &\"", surface("- > a\n  2\u{0} [x] &amp;\n"))
    }

    /// Flag-off (spec-correct): the item's first block is a block quote, not a paragraph (GFM task list
    /// items), so the item has no checkbox and the lazy line keeps its `2` prefix ahead of the link, where
    /// cmark's later-line checkbox retry checks the item and drops the advanced bytes.
    func testLinkFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            ├─ Text \"2\u{fffd} [x] \"\n            └─ Link destination: \"u\"\n               └─ Text \"l\"", surface("- > a\n  2\u{0} [x] [l](u)\n"))
    }

    /// Flag-off (spec-correct): the item's first block is a block quote, not a paragraph (GFM task list
    /// items), so the item has no checkbox and the lazy line keeps its `2` prefix ahead of the autolink,
    /// where cmark's later-line checkbox retry checks the item and drops the advanced bytes.
    func testAutolinkFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            ├─ Text \"2\u{fffd} [x] \"\n            └─ Link destination: \"http://e.com\"\n               └─ Text \"http://e.com\"", surface("- > a\n  2\u{0} [x] <http://e.com>\n"))
    }

    /// Flag-off (spec-correct): the item's first block is a block quote, not a paragraph (GFM task list
    /// items), so the item has no checkbox and the lazy line keeps its `2` prefix ahead of the hard line
    /// break, where cmark's later-line checkbox retry checks the item and drops the advanced bytes.
    func testHardBreakEndsLazyLineFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            ├─ Text \"2\u{fffd} [x] b\"\n            ├─ LineBreak\n            └─ Text \"c\"", surface("- > a\n  2\u{0} [x] b  \n  > c\n"))
    }

    /// Flag-off (spec-correct): the item's first block is a block quote, not a paragraph (GFM task list
    /// items), so the item has no checkbox and the lazy line keeps its `2` prefix ahead of the emphasis,
    /// where cmark's later-line checkbox retry checks the item and drops the advanced bytes.
    func testEmphasisAcrossSecondLazyLineFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            ├─ Text \"2\u{fffd} [x] \"\n            └─ Emphasis\n               ├─ Text \"b\"\n               ├─ SoftBreak\n               └─ Text \"c\"", surface("- > a\n  2\u{0} [x] *b\nc*\n"))
    }

    /// Flag-off (spec-correct): the item's first block is a block quote, not a paragraph (GFM task list
    /// items), so the item has no checkbox and the lazy line keeps its `22é` prefix ahead of the emphasis,
    /// where cmark's later-line checkbox retry checks the item and drops the advanced bytes.
    func testMultiByteLazyLineEmphasisFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            ├─ Text \"22\u{E9} [x] \"\n            └─ Emphasis\n               └─ Text \"b\"", surface("- > a\n  22\u{E9} [x] *b*\n"))
    }
}
