/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest

/// A backslash before `&` in a fenced code block's info string escapes it (Backslash escapes), so the
/// character reference that follows is literal text.
class FencedInfoStringEntityEscapeOrderTests: XCTestCase {
    private func tree(_ markdown: String) -> String {
        return Document(parsing: markdown).debugDescription(options: [])
    }

    func testEscapedAmpersandLeavesNumericReferenceLiteral() {
        XCTAssertEqual("Document\n└─ CodeBlock language: &#3;\n", tree("```\\&#3;"))
    }

    func testEscapedAmpersandLeavesEntityReferenceLiteral() {
        XCTAssertEqual("Document\n└─ CodeBlock language: &amp;\n", tree("```\\&amp;"))
    }
}
