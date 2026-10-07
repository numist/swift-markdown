/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

/// A line of nested block quote markers ends the preceding list item and its unclosed fenced code block.
/// A tab after a block quote marker counts in columns (Tabs): one column is the marker's optional space, so
/// a following `>` opens a further block quote and following text at four more columns is an indented
/// code block.
class NestedBlockQuoteTabAfterListFenceTests: XCTestCase {
    private static let options = ParseOptions(rawValue: UInt(0x3e & 0b11011111))

    private func surface(_ markdown: String) -> String {
        Document(parsing: markdown, options: Self.options).debugDescription(options: [])
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
