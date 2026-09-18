/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @testable import Markdown
import XCTest

/// Block structure for a list item containing an unterminated fenced code block, immediately followed by
/// a block quote whose content is indented by tabs.
///
/// Ground truth is cmark-gfm. For the fuzzer artifact `"+\t\`\`\`\n>\t\t>"` cmark parses a list holding an
/// empty code block, then a separate block quote whose indented-code content is `  >` (two leading
/// spaces). The rewrite produced the same tree but with `>` (no leading spaces) for the block-quote code
/// content. `>\t\t>` on its own already matches on both sides — only this combined shape diverged. This
/// asserts the fuzzer compare surface (position-free `debugDescription`).
class TabListFenceStateStructureTests: XCTestCase {
    /// The two leading spaces on the block quote's indented-code content must survive the preceding
    /// list-item's unterminated fenced code block.
    func testOpenListFenceThenBlockQuoteTabIndent() {
        // Fuzzer artifact bytes (markdown portion): "+" TAB "```" LF ">" TAB TAB ">"
        let markdown = String(
            decoding: [0x2b, 0x09, 0x60, 0x60, 0x60, 0x0a, 0x3e, 0x09, 0x09, 0x3e] as [UInt8],
            as: UTF8.self)
        // Options byte 0xff, masked to the fuzzable bits, then the fixed cmarkBugCompatibility bit that
        // the differential fuzzer's compare surface always sets.
        var options = ParseOptions(rawValue: UInt(0xff & 0b11011111))
        options.insert(.cmarkBugCompatibility)

        let expected = "Document\n├─ UnorderedList\n│  └─ ListItem\n│     └─ CodeBlock language: none\n\n└─ BlockQuote\n   └─ CodeBlock language: none\n        >"

        let document = Document(parsing: markdown, options: options)
        XCTAssertEqual(expected, document.debugDescription(options: []))
    }
}
