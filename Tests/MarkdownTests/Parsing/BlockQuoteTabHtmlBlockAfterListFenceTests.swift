/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @testable import Markdown
import XCTest

/// A `>` TAB `<!A` block quote (feeding an HTML block) following a list item with an unterminated fenced
/// code block: the partially-consumed tab after the `>` marker must surface its leftover columns as spaces
/// in the HTML block content.
///
/// Ground truth is cmark-gfm. For `- ` fence, then `>` TAB `<!A`, cmark's block-quote marker consumes one
/// column of the tab and the tab's remaining columns become spaces, so the HTML block content is `  <!A`.
/// The rewrite kept the raw tab (`\t<!A`). Same partially-consumed-tab class as #182 / #200 / a3c1c33, at
/// the HTML-block content site; spec-correct, so both flag states must surface spaces. Position-free surface.
class BlockQuoteTabHtmlBlockAfterListFenceTests: XCTestCase {
    // "- " "```" LF ">" TAB "<!A"
    private static let bytes: [UInt8] = [0x2d, 0x20, 0x60, 0x60, 0x60, 0x0a, 0x3e, 0x09, 0x3c, 0x21, 0x41]

    private func surface(cmarkBugCompatible: Bool) -> String {
        var options = ParseOptions(rawValue: UInt(0x75 & 0b11011111))
        if cmarkBugCompatible { options.insert(.cmarkBugCompatibility) }
        return Document(parsing: String(decoding: Self.bytes, as: UTF8.self), options: options)
            .debugDescription(options: [])
    }

    func testLeftoverTabColumnsBecomeSpacesInHtmlBlock() {
        let expected = "Document\n├─ UnorderedList\n│  └─ ListItem\n│     └─ CodeBlock language: none\n\n└─ BlockQuote\n   └─ HTMLBlock\n        <!A"
        XCTAssertEqual(expected, surface(cmarkBugCompatible: true))
        XCTAssertEqual(expected, surface(cmarkBugCompatible: false))
    }
}
