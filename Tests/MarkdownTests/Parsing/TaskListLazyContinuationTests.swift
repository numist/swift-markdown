/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @testable import Markdown
import XCTest

/// Lazy continuation of a task-list item's paragraph.
///
/// Ground truth is cmark-gfm. A non-indented line following a paragraph inside a list item is a lazy
/// continuation line and extends that paragraph (CommonMark §4.8 / §5.2). The rewrite instead broke out of
/// the list and started a new top-level paragraph for the third line — but only when the item had a task
/// checkbox AND an intermediate continuation line whose content was `-|` (a bare dash before a pipe); the
/// plain-list, no-checkbox, and other-content variants already continued correctly. Lazy continuation is
/// spec-correct, so both flag states must extend the paragraph. Position-free compare surface.
class TaskListLazyContinuationTests: XCTestCase {
    private func surface(_ bytes: [UInt8], options optionByte: UInt8, cmarkBugCompatible: Bool) -> String {
        var options = ParseOptions(rawValue: UInt(optionByte & 0b11011111))
        if cmarkBugCompatible { options.insert(.cmarkBugCompatibility) }
        return Document(parsing: String(decoding: bytes, as: UTF8.self), options: options)
            .debugDescription(options: [])
    }

    /// The fuzzer artifact: `- [ ] |` / `  -|` / `|`.
    func testArtifactLazyContinuesTaskItemParagraph() {
        let bytes: [UInt8] = [0x2d, 0x20, 0x5b, 0x20, 0x5d, 0x20, 0x7c, 0x0a, 0x20, 0x20, 0x2d, 0x7c, 0x0a, 0x7c]
        let expected = "Document\n└─ UnorderedList\n   └─ ListItem checkbox: [ ]\n      └─ Paragraph\n         ├─ Text \"|\"\n         ├─ SoftBreak\n         ├─ Text \"-|\"\n         ├─ SoftBreak\n         └─ Text \"|\""
        XCTAssertEqual(expected, surface(bytes, options: 0x75, cmarkBugCompatible: true))
        XCTAssertEqual(Self.shippedTable(lastLine: "|"), surface(bytes, options: 0x75, cmarkBugCompatible: false))
    }

    /// Clean variant with a plain third line: `- [ ] |` / `  -|` / `z`.
    func testPlainThirdLineLazyContinuesTaskItemParagraph() {
        let bytes: [UInt8] = [0x2d, 0x20, 0x5b, 0x20, 0x5d, 0x20, 0x7c, 0x0a, 0x20, 0x20, 0x2d, 0x7c, 0x0a, 0x7a]
        let expected = "Document\n└─ UnorderedList\n   └─ ListItem checkbox: [ ]\n      └─ Paragraph\n         ├─ Text \"|\"\n         ├─ SoftBreak\n         ├─ Text \"-|\"\n         ├─ SoftBreak\n         └─ Text \"z\""
        XCTAssertEqual(expected, surface(bytes, options: 0x00, cmarkBugCompatible: true))
        XCTAssertEqual(Self.shippedTable(lastLine: "z"), surface(bytes, options: 0x00, cmarkBugCompatible: false))
    }

    /// The shipped parser's tree: `[ ] |` over `-|` is a one-column table, so the item's first block is
    /// no paragraph and the item is no task item (spec "Task list items (extension)"); a table takes no
    /// lazy continuation, so the last line is a paragraph after the list.
    private static func shippedTable(lastLine: String) -> String {
        "Document\n├─ UnorderedList\n│  └─ ListItem\n│     └─ Table alignments: |-|\n│        ├─ Head\n│        │  └─ Cell\n│        │     └─ Text \"[ ]\"\n│        └─ Body\n└─ Paragraph\n   └─ Text \"\(lastLine)\""
    }
}
