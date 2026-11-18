/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest

class TaskListCheckboxOnlyLineContinuationTests: XCTestCase {
    func testBracketContinuationKeptAsParagraph() {
        let expected = "Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ Paragraph\n         └─ Text \"[x]\""
        XCTAssertEqual(expected, Document(parsing: "- [x] \n  [x]").debugDescription(options: []))
    }
}
