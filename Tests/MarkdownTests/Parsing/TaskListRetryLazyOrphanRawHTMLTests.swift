/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @testable import Markdown
import XCTest

/// Raw HTML reaching onto a lazy tasklist-retry line whose checkbox advance orphaned UTF-8 continuation bytes.
///
/// Ground truth is cmark-gfm (flag-ON). On `- >a<…` LF `  2` NUL ` [x] `, cmark's retry advance stops inside the
/// NUL's U+FFFD, so the lazy line cmark appends starts with an orphaned continuation byte. cmark's re2c scanners
/// (`src/scanners.c`) validate UTF-8, so a scan body stops at that byte; `handle_pointy_brace` (`src/inlines.c`)
/// then frames the PI, CDATA and declaration bodies with closers it never verifies, swallowing the orphan and
/// the bytes after it, while the comment, quoted attribute value and link title scans fail. The reference's
/// String bridge repairs each orphan to U+FFFD, including a multi-byte source scalar's. Position-free compare
/// surface.
class TaskListRetryLazyOrphanRawHTMLTests: XCTestCase {
    private func surface(_ markdown: String, cmarkBugCompatible: Bool = true) -> String {
        Document(parsing: markdown, options: cmarkBugCompatible ? [.cmarkBugCompatibility, .disableSmartOpts] : [.disableSmartOpts]).debugDescription(options: [])
    }

    private static let prefix = "Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ Paragraph\n"

    func testProcessingInstructionClosesAtOrphan() {
        XCTAssertEqual(Self.prefix + "            ├─ Text \"a\"\n            ├─ InlineHTML <?\n\u{fffd} \n            └─ Text \"[x]\"", surface("- >a<?\n  2\u{0} [x] \n"))
    }

    /// Flag-off (spec-correct): the item has no checkbox (its first block is a block quote) and the `<?`
    /// with no `?>` closer stays text (CommonMark raw HTML), where cmark's later-line checkbox retry
    /// orphans a UTF-8 continuation byte that closes it as raw HTML.
    func testUnclosedProcessingInstructionFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a<?\"\n            ├─ SoftBreak\n            └─ Text \"2\u{fffd} [x]\"", surface("- >a<?\n  2\u{0} [x] \n", cmarkBugCompatible: false))
    }

    func testProcessingInstructionClosesAtOrphanBeforeRealCloser() {
        XCTAssertEqual(Self.prefix + "            ├─ Text \"a\"\n            ├─ InlineHTML <?\n\u{fffd} \n            └─ Text \"[x] ?>\"", surface("- >a<?\n  2\u{0} [x] ?>\n"))
    }

    /// Flag-off (spec-correct): the item has no checkbox (its first block is a block quote) and the
    /// processing instruction runs across the line ending to its `?>` (CommonMark raw HTML), where cmark's
    /// later-line checkbox retry orphans a UTF-8 continuation byte that closes it early.
    func testProcessingInstructionSpanningLinesFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            └─ InlineHTML <?\n2\u{fffd} [x] ?>", surface("- >a<?\n  2\u{0} [x] ?>\n", cmarkBugCompatible: false))
    }

    func testProcessingInstructionClosesAtTwoOrphans() {
        XCTAssertEqual(Self.prefix + "            ├─ Text \"a\"\n            ├─ InlineHTML <?\n\u{fffd}\u{fffd}\n            └─ Text \" [x]\"", surface("- >a<?\n  22\u{0} [x] \n"))
    }

    /// Flag-off (spec-correct): the item has no checkbox (its first block is a block quote) and the `<?`
    /// with no `?>` closer stays text (CommonMark raw HTML), where cmark's later-line checkbox retry
    /// orphans a UTF-8 continuation byte that closes it as raw HTML.
    func testUnclosedProcessingInstructionAfterTwoDigitsFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a<?\"\n            ├─ SoftBreak\n            └─ Text \"22\u{fffd} [x]\"", surface("- >a<?\n  22\u{0} [x] \n", cmarkBugCompatible: false))
    }

    func testProcessingInstructionClosesAtSourceOrphan() {
        XCTAssertEqual(Self.prefix + "            ├─ Text \"a\"\n            ├─ InlineHTML <?\n\u{fffd} \n            └─ Text \"[x]\"", surface("- >a<?\n  22\u{E9} [x] \n"))
    }

    /// Flag-off (spec-correct): the item has no checkbox (its first block is a block quote) and the `<?`
    /// with no `?>` closer stays text (CommonMark raw HTML), where cmark's later-line checkbox retry
    /// orphans a UTF-8 continuation byte that closes it as raw HTML.
    func testUnclosedProcessingInstructionBeforeMultiByteScalarFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a<?\"\n            ├─ SoftBreak\n            └─ Text \"22\u{E9} [x]\"", surface("- >a<?\n  22\u{E9} [x] \n", cmarkBugCompatible: false))
    }

    func testCDATAClosesAtOrphan() {
        XCTAssertEqual(Self.prefix + "            ├─ Text \"a\"\n            ├─ InlineHTML <![CDATA[\n\u{fffd} [\n            └─ Text \"x]\"", surface("- >a<![CDATA[\n  2\u{0} [x] \n"))
    }

    /// Flag-off (spec-correct): the item has no checkbox (its first block is a block quote) and the CDATA
    /// opener with no `]]>` closer stays text (CommonMark raw HTML), where cmark's later-line checkbox
    /// retry orphans a UTF-8 continuation byte that closes it as raw HTML.
    func testUnclosedCDATAFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a<![CDATA[\"\n            ├─ SoftBreak\n            └─ Text \"2\u{fffd} [x]\"", surface("- >a<![CDATA[\n  2\u{0} [x] \n", cmarkBugCompatible: false))
    }

    func testDeclarationClosesAtOrphan() {
        XCTAssertEqual(Self.prefix + "            ├─ Text \"a\"\n            ├─ InlineHTML <!X\n\u{fffd}\n            └─ Text \" [x]\"", surface("- >a<!X\n  2\u{0} [x] \n"))
    }

    /// Flag-off (spec-correct): the item has no checkbox (its first block is a block quote) and the `<!X`
    /// with no `>` closer stays text (CommonMark raw HTML), where cmark's later-line checkbox retry orphans
    /// a UTF-8 continuation byte that closes it as raw HTML.
    func testUnclosedDeclarationFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a<!X\"\n            ├─ SoftBreak\n            └─ Text \"2\u{fffd} [x]\"", surface("- >a<!X\n  2\u{0} [x] \n", cmarkBugCompatible: false))
    }

    func testCommentStopsAtOrphan() {
        XCTAssertEqual(Self.prefix + "            ├─ Text \"a<!--\"\n            ├─ SoftBreak\n            └─ Text \"\u{fffd} [x] -->\"", surface("- >a<!--\n  2\u{0} [x] -->\n"))
    }

    /// Flag-off (spec-correct): the item has no checkbox (its first block is a block quote) and the HTML
    /// comment runs across the line ending to its `-->` (CommonMark raw HTML), where cmark's later-line
    /// checkbox retry orphans a UTF-8 continuation byte that stops its comment scan.
    func testCommentSpanningLinesFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            └─ InlineHTML <!--\n2\u{fffd} [x] -->", surface("- >a<!--\n  2\u{0} [x] -->\n", cmarkBugCompatible: false))
    }

    func testQuotedAttributeValueStopsAtOrphan() {
        XCTAssertEqual(Self.prefix + "            ├─ Text \"a<a b=\"\"\n            ├─ SoftBreak\n            └─ Text \"\u{fffd} [x] \">\"", surface("- >a<a b=\"\n  2\u{0} [x] \">\n"))
    }

    /// Flag-off (spec-correct): the item has no checkbox (its first block is a block quote) and the
    /// double-quoted attribute value runs across the line ending, so the open tag is raw HTML (CommonMark
    /// raw HTML), where cmark's later-line checkbox retry orphans a UTF-8 continuation byte that stops its
    /// attribute value scan.
    func testQuotedAttributeValueSpanningLinesFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            └─ InlineHTML <a b=\"\n2\u{fffd} [x] \">", surface("- >a<a b=\"\n  2\u{0} [x] \">\n", cmarkBugCompatible: false))
    }

    func testSourceOrphanTextNodeIsReplaced() {
        XCTAssertEqual(Self.prefix + "            ├─ Text \"a\"\n            ├─ SoftBreak\n            ├─ Text \"\u{fffd} \"\n            └─ Link destination: \"/u\"\n               └─ Text \"x\"", surface("- >a\n  22\u{E9} [x] \n\n[x]: /u\n"))
    }

    /// Flag-off (spec-correct): the item has no checkbox (its first block is a block quote) and the lazy
    /// line keeps its `22é` prefix ahead of the `[x]` shortcut reference link, where cmark's later-line
    /// checkbox retry orphans a UTF-8 continuation byte that it repairs to U+FFFD.
    func testShortcutReferenceOnLazyLineFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            ├─ Text \"22\u{E9} \"\n            └─ Link destination: \"/u\"\n               └─ Text \"x\"", surface("- >a\n  22\u{E9} [x] \n\n[x]: /u\n", cmarkBugCompatible: false))
    }

    func testFirstLineSourceOrphanTextNodeIsReplaced() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ Paragraph\n         ├─ Text \"\u{fffd} \"\n         └─ Link destination: \"/u\"\n            └─ Text \"x\"", surface("+\n  22\u{E9} [x] \n\n[x]: /u\n"))
    }

    /// Flag-off (spec-correct): a paragraph beginning `22` has no task list item marker (GFM task list
    /// items), so the item has no checkbox and `22é` precedes the `[x]` shortcut reference link, where
    /// cmark's later-line checkbox retry checks the item and orphans a UTF-8 continuation byte that it
    /// repairs to U+FFFD.
    func testShortcutReferenceOnDigitLineFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         ├─ Text \"22\u{E9} \"\n         └─ Link destination: \"/u\"\n            └─ Text \"x\"", surface("+\n  22\u{E9} [x] \n\n[x]: /u\n", cmarkBugCompatible: false))
    }

    func testLinkTitleStopsAtOrphan() {
        XCTAssertEqual(Self.prefix + "            ├─ Text \"x[a](/u \"\"\n            ├─ SoftBreak\n            └─ Text \"\u{fffd} [x] \")\"", surface("- >x[a](/u \"\n  2\u{0} [x] \")\n"))
    }

    /// Flag-off (spec-correct): the item has no checkbox (its first block is a block quote) and the link
    /// title runs across the line ending, so `[a](/u "…")` is a link (CommonMark links), where cmark's
    /// later-line checkbox retry orphans a UTF-8 continuation byte that stops its title scan.
    func testLinkTitleSpanningLinesFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"x\"\n            └─ Link destination: \"/u\"\n               └─ Text \"a\"", surface("- >x[a](/u \"\n  2\u{0} [x] \")\n", cmarkBugCompatible: false))
    }

    func testProcessingInstructionWithoutOrphanOverruns() {
        XCTAssertEqual(Self.prefix + "            ├─ Text \"a<?\"\n            ├─ SoftBreak\n            └─ Text \"[x]\"", surface("- >a<?\n  2\u{E9} [x] \n"))
    }

    /// Flag-off (spec-correct): the item's first block is a block quote, not a paragraph (GFM task list
    /// items), so the item has no checkbox and the lazy line keeps its `2é` prefix after the unclosed `<?`
    /// text, where cmark's later-line checkbox retry checks the item and drops the advanced bytes.
    func testUnclosedProcessingInstructionWithoutOrphanFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a<?\"\n            ├─ SoftBreak\n            └─ Text \"2\u{E9} [x]\"", surface("- >a<?\n  2\u{E9} [x] \n", cmarkBugCompatible: false))
    }
}
