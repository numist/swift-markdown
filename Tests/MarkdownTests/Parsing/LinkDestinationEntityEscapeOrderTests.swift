/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest

/// A backslash before `&` in a link destination escapes it (Backslash escapes), so the character reference
/// that follows is literal text.
class LinkDestinationEntityEscapeOrderTests: XCTestCase {
    private func surface(_ markdown: String) -> String {
        Document(parsing: markdown).debugDescription(options: [])
    }

    func testEscapedAmpersandLeavesNumericReferenceLiteral() {
        XCTAssertEqual(
            "Document\n└─ Paragraph\n   └─ Link destination: \"&#3;\"\n      └─ Text \"a\"",
            surface("[a](\\&#3;)"))
    }

    func testEscapedAmpersandLeavesEntityReferenceLiteral() {
        XCTAssertEqual(
            "Document\n└─ Paragraph\n   └─ Link destination: \"&amp;\"\n      └─ Text \"a\"",
            surface("[a](\\&amp;)"))
    }
}
