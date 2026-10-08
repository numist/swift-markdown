/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest

class SetextHeadingLazyLeadingSpaceTests: XCTestCase {
    /// Leading whitespace is stripped from a setext heading's content (Setext headings), including content
    /// from a lazy continuation line that follows a link reference definition.
    func testLazyContinuationLeadingSpaceIsStripped() {
        let (markdown, options) = DocumentRegressionTests.splitInput([62, 91, 97, 93, 58, 117, 10, 32, 255, 10, 62, 61, 10])!
        XCTAssertEqual("Document\n└─ BlockQuote\n   └─ Heading level: 1\n      └─ Text \"\u{fffd}\"", Document(parsing: markdown, options: options).debugDescription(options: []))
    }
}
