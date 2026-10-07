/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

class DecimalNoncharacterEntityTests: XCTestCase {
    /// `&#65534;` is a valid code point (Entity and numeric character references), so it decodes to the
    /// noncharacter U+FFFE.
    func testDecimalEntityDecodesToNoncharacter() {
        let (markdown, options) = DocumentRegressionTests.splitInput([38, 35, 54, 53, 53, 51, 52, 59, 0])!
        let uFFFE = String(Unicode.Scalar(0xFFFE as UInt32)!)
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"\(uFFFE)\"", Document(parsing: markdown, options: options).debugDescription(options: []))
    }
}
