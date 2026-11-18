/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest

// `MarkupParser.shippingLimits` reads up to 8 digits in a decimal or hexadecimal numeric character reference,
// leading zeros included, more than the spec's 7 and 6 (Entity and numeric character references).
class CharacterReferenceDigitLimitTests: XCTestCase {
    private func tree(_ markdown: String) -> String {
        Document(parsing: markdown, options: []).debugDescription(options: [])
    }

    // The tests parse images because the debug description prints an Image's title but not a Link's.

    func testInlineTitleReferenceOfEightDigitsDecodes() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Image source: \"A\" title: \"A\"\n      └─ Text \"l\"", tree("![l](&#00000065; \"&#x00000041;\")"))
    }

    func testInlineTitleReferenceOfNineDigitsIsText() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Image source: \"&#000000065;\" title: \"&#x000000041;\"\n      └─ Text \"l\"", tree("![l](&#000000065; \"&#x000000041;\")"))
    }

    func testDefinitionTitleReferenceOfEightDigitsDecodes() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Image source: \"A\" title: \"A\"\n      └─ Text \"l\"", tree("[l]: &#x00000041; '&#00000065;'\n\n![l]"))
    }

    func testDefinitionTitleReferenceOfNineDigitsIsText() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Image source: \"&#x000000041;\" title: \"&#000000065;\"\n      └─ Text \"l\"", tree("[l]: &#x000000041; '&#000000065;'\n\n![l]"))
    }
}
