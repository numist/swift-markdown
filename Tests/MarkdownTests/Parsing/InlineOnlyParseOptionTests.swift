/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

class InlineOnlyParseOptionTests: XCTestCase {
    private func surface(_ markdown: String, options: ParseOptions) -> String {
        Document(parsing: markdown, options: options).debugDescription(options: [])
    }

    func testDefaultOptionsParseBlocks() {
        XCTAssertEqual("Document\n├─ Heading level: 1\n│  └─ Text \"heading\"\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"item\"", surface("# heading\n\n* item", options: []))
    }
}
