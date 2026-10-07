/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

class TaskListRetryLazyOrphanRawHTMLTests: XCTestCase {
    private func surface(_ markdown: String) -> String {
        Document(parsing: markdown, options: [.disableSmartOpts]).debugDescription(options: [])
    }

    /// Flag-off (spec-correct): the item has no checkbox (its first block is a block quote) and the `<?`
    /// with no `?>` closer stays text (CommonMark raw HTML), where cmark's later-line checkbox retry
    /// orphans a UTF-8 continuation byte that closes it as raw HTML.
    func testUnclosedProcessingInstructionFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a<?\"\n            ├─ SoftBreak\n            └─ Text \"2\u{fffd} [x]\"", surface("- >a<?\n  2\u{0} [x] \n"))
    }

    /// Flag-off (spec-correct): the item has no checkbox (its first block is a block quote) and the
    /// processing instruction runs across the line ending to its `?>` (CommonMark raw HTML), where cmark's
    /// later-line checkbox retry orphans a UTF-8 continuation byte that closes it early.
    func testProcessingInstructionSpanningLinesFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            └─ InlineHTML <?\n2\u{fffd} [x] ?>", surface("- >a<?\n  2\u{0} [x] ?>\n"))
    }

    /// Flag-off (spec-correct): the item has no checkbox (its first block is a block quote) and the `<?`
    /// with no `?>` closer stays text (CommonMark raw HTML), where cmark's later-line checkbox retry
    /// orphans a UTF-8 continuation byte that closes it as raw HTML.
    func testUnclosedProcessingInstructionAfterTwoDigitsFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a<?\"\n            ├─ SoftBreak\n            └─ Text \"22\u{fffd} [x]\"", surface("- >a<?\n  22\u{0} [x] \n"))
    }

    /// Flag-off (spec-correct): the item has no checkbox (its first block is a block quote) and the `<?`
    /// with no `?>` closer stays text (CommonMark raw HTML), where cmark's later-line checkbox retry
    /// orphans a UTF-8 continuation byte that closes it as raw HTML.
    func testUnclosedProcessingInstructionBeforeMultiByteScalarFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a<?\"\n            ├─ SoftBreak\n            └─ Text \"22\u{E9} [x]\"", surface("- >a<?\n  22\u{E9} [x] \n"))
    }

    /// Flag-off (spec-correct): the item has no checkbox (its first block is a block quote) and the CDATA
    /// opener with no `]]>` closer stays text (CommonMark raw HTML), where cmark's later-line checkbox
    /// retry orphans a UTF-8 continuation byte that closes it as raw HTML.
    func testUnclosedCDATAFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a<![CDATA[\"\n            ├─ SoftBreak\n            └─ Text \"2\u{fffd} [x]\"", surface("- >a<![CDATA[\n  2\u{0} [x] \n"))
    }

    /// Flag-off (spec-correct): the item has no checkbox (its first block is a block quote) and the `<!X`
    /// with no `>` closer stays text (CommonMark raw HTML), where cmark's later-line checkbox retry orphans
    /// a UTF-8 continuation byte that closes it as raw HTML.
    func testUnclosedDeclarationFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a<!X\"\n            ├─ SoftBreak\n            └─ Text \"2\u{fffd} [x]\"", surface("- >a<!X\n  2\u{0} [x] \n"))
    }

    /// Flag-off (spec-correct): the item has no checkbox (its first block is a block quote) and the HTML
    /// comment runs across the line ending to its `-->` (CommonMark raw HTML), where cmark's later-line
    /// checkbox retry orphans a UTF-8 continuation byte that stops its comment scan.
    func testCommentSpanningLinesFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            └─ InlineHTML <!--\n2\u{fffd} [x] -->", surface("- >a<!--\n  2\u{0} [x] -->\n"))
    }

    /// Flag-off (spec-correct): the item has no checkbox (its first block is a block quote) and the
    /// double-quoted attribute value runs across the line ending, so the open tag is raw HTML (CommonMark
    /// raw HTML), where cmark's later-line checkbox retry orphans a UTF-8 continuation byte that stops its
    /// attribute value scan.
    func testQuotedAttributeValueSpanningLinesFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            └─ InlineHTML <a b=\"\n2\u{fffd} [x] \">", surface("- >a<a b=\"\n  2\u{0} [x] \">\n"))
    }

    /// Flag-off (spec-correct): the item has no checkbox (its first block is a block quote) and the lazy
    /// line keeps its `22é` prefix ahead of the `[x]` shortcut reference link, where cmark's later-line
    /// checkbox retry orphans a UTF-8 continuation byte that it repairs to U+FFFD.
    func testShortcutReferenceOnLazyLineFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            ├─ Text \"22\u{E9} \"\n            └─ Link destination: \"/u\"\n               └─ Text \"x\"", surface("- >a\n  22\u{E9} [x] \n\n[x]: /u\n"))
    }

    /// Flag-off (spec-correct): a paragraph beginning `22` has no task list item marker (GFM task list
    /// items), so the item has no checkbox and `22é` precedes the `[x]` shortcut reference link, where
    /// cmark's later-line checkbox retry checks the item and orphans a UTF-8 continuation byte that it
    /// repairs to U+FFFD.
    func testShortcutReferenceOnDigitLineFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         ├─ Text \"22\u{E9} \"\n         └─ Link destination: \"/u\"\n            └─ Text \"x\"", surface("+\n  22\u{E9} [x] \n\n[x]: /u\n"))
    }

    /// Flag-off (spec-correct): the item has no checkbox (its first block is a block quote) and the link
    /// title runs across the line ending, so `[a](/u "…")` is a link (CommonMark links), where cmark's
    /// later-line checkbox retry orphans a UTF-8 continuation byte that stops its title scan.
    func testLinkTitleSpanningLinesFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"x\"\n            └─ Link destination: \"/u\"\n               └─ Text \"a\"", surface("- >x[a](/u \"\n  2\u{0} [x] \")\n"))
    }

    /// Flag-off (spec-correct): the item's first block is a block quote, not a paragraph (GFM task list
    /// items), so the item has no checkbox and the lazy line keeps its `2é` prefix after the unclosed `<?`
    /// text, where cmark's later-line checkbox retry checks the item and drops the advanced bytes.
    func testUnclosedProcessingInstructionWithoutOrphanFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a<?\"\n            ├─ SoftBreak\n            └─ Text \"2\u{E9} [x]\"", surface("- >a<?\n  2\u{E9} [x] \n"))
    }
}
