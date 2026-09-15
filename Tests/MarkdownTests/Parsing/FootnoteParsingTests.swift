/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
@_spi(Footnotes) @testable import Markdown

class FootnoteParsingTests: XCTestCase {
    func testSimpleReferenceAndDefinition() {
        let doc = Document(parsing: "see [^a]\n\n[^a]: note\n", options: [.footnotes])
        let expected = """
        Document
        ├─ Paragraph
        │  ├─ Text "see "
        │  └─ FootnoteReference label: "a" index: 1
        └─ FootnoteDefinition label: "a"
           └─ Paragraph
              └─ Text "note"
        """
        XCTAssertEqual(doc.debugDescription(), expected)
    }
}
