/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

/// `>` TAB `>` after a list item holding an unclosed fenced code block opens a nested block quote: the block
/// quote marker consumes one column of the tab (Tabs), and the second `>` begins the inner block quote.
class BlockQuoteTabNestedAfterListFenceTests: XCTestCase {
    // "- " "```" LF ">" TAB ">"
    private static let bytes: [UInt8] = [0x2d, 0x20, 0x60, 0x60, 0x60, 0x0a, 0x3e, 0x09, 0x3e]

    private func surface() -> String {
        return Document(parsing: String(decoding: Self.bytes, as: UTF8.self), options: ParseOptions(rawValue: 0))
            .debugDescription(options: [])
    }

    func testTabAfterMarkerOpensNestedBlockQuote() {
        let expected = "Document\n├─ UnorderedList\n│  └─ ListItem\n│     └─ CodeBlock language: none\n\n└─ BlockQuote\n   └─ BlockQuote"
        XCTAssertEqual(expected, surface())
    }
}
