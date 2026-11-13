/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest

/// A line of nested block quote markers ends the preceding ordered list item and its unclosed fenced code
/// block. A tab after a block quote marker counts in columns (Tabs): one column is the marker's optional space and
/// the rest count toward the indentation of what follows, so a following `>` opens a further block quote, and two
/// more spaces before it make an indented code block.
class NestedBlockQuoteTabAfterListFenceTests: XCTestCase {
    private func tree(_ markdown: String) -> String {
        Document(parsing: markdown, options: []).debugDescription(options: [])
    }

    func testOrderedListFence() {
        XCTAssertEqual("Document\n├─ OrderedList\n│  └─ ListItem\n│     └─ CodeBlock language: none\n\n└─ BlockQuote\n   └─ BlockQuote\n      └─ BlockQuote\n         └─ BlockQuote\n            └─ BlockQuote", tree("1. ```\n>>>>\t>"))
    }

    func testOrderedListFenceTabThenSpaces() {
        XCTAssertEqual("Document\n├─ OrderedList\n│  └─ ListItem\n│     └─ CodeBlock language: none\n\n└─ BlockQuote\n   └─ BlockQuote\n      └─ BlockQuote\n         └─ BlockQuote\n            └─ CodeBlock language: none\n                >", tree("1. ```\n>>>>\t  >"))
    }
}
