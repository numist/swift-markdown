/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @testable import Markdown
import XCTest

/// A `>` TAB `>` block quote following a list item that holds an unterminated fenced code block: the tab
/// after the outer `>` marker leaves enough columns that the second `>` opens a NESTED block quote.
///
/// Ground truth is cmark-gfm. For `- ` fence, then `>` TAB `>`, cmark produces `BlockQuote` → `BlockQuote`
/// (nested). `>` TAB `>` on its own already nests on both sides, and the two-tab indented-code sibling
/// (#182) is fixed; only this one-tab nested-quote case in the open-list-fence context still produced
/// `BlockQuote` → `Paragraph` `Text ">"`. The nested quote is spec-correct (partially-consumed-tab
/// columns), so both flag states must nest. Position-free compare surface.
class BlockQuoteTabNestedAfterListFenceTests: XCTestCase {
    // "- " "```" LF ">" TAB ">"
    private static let bytes: [UInt8] = [0x2d, 0x20, 0x60, 0x60, 0x60, 0x0a, 0x3e, 0x09, 0x3e]

    private func surface(cmarkBugCompatible: Bool) -> String {
        var options = ParseOptions(rawValue: 0)
        if cmarkBugCompatible { options.insert(.cmarkBugCompatibility) }
        return Document(parsing: String(decoding: Self.bytes, as: UTF8.self), options: options)
            .debugDescription(options: [])
    }

    func testTabAfterMarkerOpensNestedBlockQuote() {
        let expected = "Document\n├─ UnorderedList\n│  └─ ListItem\n│     └─ CodeBlock language: none\n\n└─ BlockQuote\n   └─ BlockQuote"
        XCTAssertEqual(expected, surface(cmarkBugCompatible: true))
        XCTAssertEqual(expected, surface(cmarkBugCompatible: false))
    }
}
