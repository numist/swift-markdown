/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

class TableLazyIndentedPipeLineTests: XCTestCase {
    /// A lazy continuation line's leading whitespace is stripped like any paragraph line's (Paragraphs), so the
    /// header row is a lone `|` and no table forms (Tables (extension)).
    func testLazyIndentedPipeLineIsParagraphText() {
        let (markdown, options) = DocumentRegressionTests.splitInput([62, 120, 10, 32, 32, 124, 10, 62, 45, 124, 10])!
        XCTAssertEqual("Document\n└─ BlockQuote\n   └─ Paragraph\n      ├─ Text \"x\"\n      ├─ SoftBreak\n      ├─ Text \"|\"\n      ├─ SoftBreak\n      └─ Text \"-|\"", Document(parsing: markdown, options: options).debugDescription(options: []))
    }
}
