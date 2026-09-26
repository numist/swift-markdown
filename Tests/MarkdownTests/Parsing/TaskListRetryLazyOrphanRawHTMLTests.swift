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
    private func surface(_ markdown: String) -> String {
        Document(parsing: markdown, options: [.cmarkBugCompatibility, .disableSmartOpts]).debugDescription(options: [])
    }

    private static let prefix = "Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ Paragraph\n"

    func testProcessingInstructionClosesAtOrphan() {
        XCTAssertEqual(Self.prefix + "            ├─ Text \"a\"\n            ├─ InlineHTML <?\n\u{fffd} \n            └─ Text \"[x]\"", surface("- >a<?\n  2\u{0} [x] \n"))
    }

    func testProcessingInstructionClosesAtOrphanBeforeRealCloser() {
        XCTAssertEqual(Self.prefix + "            ├─ Text \"a\"\n            ├─ InlineHTML <?\n\u{fffd} \n            └─ Text \"[x] ?>\"", surface("- >a<?\n  2\u{0} [x] ?>\n"))
    }

    func testProcessingInstructionClosesAtTwoOrphans() {
        XCTAssertEqual(Self.prefix + "            ├─ Text \"a\"\n            ├─ InlineHTML <?\n\u{fffd}\u{fffd}\n            └─ Text \" [x]\"", surface("- >a<?\n  22\u{0} [x] \n"))
    }

    func testProcessingInstructionClosesAtSourceOrphan() {
        XCTAssertEqual(Self.prefix + "            ├─ Text \"a\"\n            ├─ InlineHTML <?\n\u{fffd} \n            └─ Text \"[x]\"", surface("- >a<?\n  22\u{E9} [x] \n"))
    }

    func testCDATAClosesAtOrphan() {
        XCTAssertEqual(Self.prefix + "            ├─ Text \"a\"\n            ├─ InlineHTML <![CDATA[\n\u{fffd} [\n            └─ Text \"x]\"", surface("- >a<![CDATA[\n  2\u{0} [x] \n"))
    }

    func testDeclarationClosesAtOrphan() {
        XCTAssertEqual(Self.prefix + "            ├─ Text \"a\"\n            ├─ InlineHTML <!X\n\u{fffd}\n            └─ Text \" [x]\"", surface("- >a<!X\n  2\u{0} [x] \n"))
    }

    func testCommentStopsAtOrphan() {
        XCTAssertEqual(Self.prefix + "            ├─ Text \"a<!--\"\n            ├─ SoftBreak\n            └─ Text \"\u{fffd} [x] -->\"", surface("- >a<!--\n  2\u{0} [x] -->\n"))
    }

    func testQuotedAttributeValueStopsAtOrphan() {
        XCTAssertEqual(Self.prefix + "            ├─ Text \"a<a b=\"\"\n            ├─ SoftBreak\n            └─ Text \"\u{fffd} [x] \">\"", surface("- >a<a b=\"\n  2\u{0} [x] \">\n"))
    }

    func testSourceOrphanTextNodeIsReplaced() {
        XCTAssertEqual(Self.prefix + "            ├─ Text \"a\"\n            ├─ SoftBreak\n            ├─ Text \"\u{fffd} \"\n            └─ Link destination: \"/u\"\n               └─ Text \"x\"", surface("- >a\n  22\u{E9} [x] \n\n[x]: /u\n"))
    }

    func testFirstLineSourceOrphanTextNodeIsReplaced() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ Paragraph\n         ├─ Text \"\u{fffd} \"\n         └─ Link destination: \"/u\"\n            └─ Text \"x\"", surface("+\n  22\u{E9} [x] \n\n[x]: /u\n"))
    }

    func testLinkTitleStopsAtOrphan() {
        XCTAssertEqual(Self.prefix + "            ├─ Text \"x[a](/u \"\"\n            ├─ SoftBreak\n            └─ Text \"\u{fffd} [x] \")\"", surface("- >x[a](/u \"\n  2\u{0} [x] \")\n"))
    }

    func testProcessingInstructionWithoutOrphanOverruns() {
        XCTAssertEqual(Self.prefix + "            ├─ Text \"a<?\"\n            ├─ SoftBreak\n            └─ Text \"[x]\"", surface("- >a<?\n  2\u{E9} [x] \n"))
    }
}
