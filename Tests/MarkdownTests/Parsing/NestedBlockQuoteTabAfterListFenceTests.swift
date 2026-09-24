/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @testable import Markdown
import XCTest

/// A tab between nested block-quote markers, on a line that closes a list item's open fence, is consumed
/// in columns by the following `>` marker.
///
/// Ground truth is cmark-gfm. Each case's second line leaves the list item (closing its unterminated fence)
/// and opens nested block quotes whose last `>` follows a tab; cmark opens that last `>` as a further block
/// quote (or, after its leftover columns, an indented code block). Position-free compare surface.
class NestedBlockQuoteTabAfterListFenceTests: XCTestCase {
    private static let fuzzedBits = ParseOptions(rawValue: UInt(0x3e & 0b11011111))

    private func surface(_ markdown: String) -> String {
        var options = Self.fuzzedBits
        options.insert(.cmarkBugCompatibility)
        return Document(parsing: markdown, options: options).debugDescription(options: [])
    }

    func testTabBeforeFourthMarker() {
        XCTAssertEqual("Document\n├─ UnorderedList\n│  └─ ListItem\n│     └─ CodeBlock language: none\n\n└─ BlockQuote\n   └─ BlockQuote\n      └─ BlockQuote\n         └─ BlockQuote", surface("- ```\n>>>\t>"))
    }

    func testSpacedMarkersThenTab() {
        XCTAssertEqual("Document\n├─ UnorderedList\n│  └─ ListItem\n│     └─ CodeBlock language: none\n\n└─ BlockQuote\n   └─ BlockQuote\n      └─ BlockQuote", surface("- ```\n> >\t>"))
    }

    func testOrderedListFence() {
        XCTAssertEqual("Document\n├─ OrderedList\n│  └─ ListItem\n│     └─ CodeBlock language: none\n\n└─ BlockQuote\n   └─ BlockQuote\n      └─ BlockQuote\n         └─ BlockQuote", surface("1. ```\n>>>\t>"))
    }

    func testTabThenIndentedCode() {
        XCTAssertEqual("Document\n├─ UnorderedList\n│  └─ ListItem\n│     └─ CodeBlock language: none\n\n└─ BlockQuote\n   └─ BlockQuote\n      └─ BlockQuote\n         └─ CodeBlock language: none\n            x", surface("- ```\n>>>\t    x"))
    }
}
