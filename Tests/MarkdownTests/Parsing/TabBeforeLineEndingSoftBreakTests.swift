/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest

/// A tab before a line ending makes a soft line break: a hard line break needs two or more spaces or a
/// backslash before the line ending (Hard line breaks).
class TabBeforeLineEndingSoftBreakTests: XCTestCase {
    private static let source = "[\u{FFFD}\r ]:\u{FFFD}\n=\n*\t\r*"
    private static let options: ParseOptions = [.parseBlockDirectives, .parseMinimalDoxygen]

    private func tree() -> String {
        Document(parsing: Self.source, options: Self.options).debugDescription(options: [])
    }

    func testTrailingTabIsSoftBreak() {
        let expected = "Document\n└─ Paragraph\n   ├─ Text \"=\"\n   ├─ SoftBreak\n   ├─ Text \"*\"\n   ├─ SoftBreak\n   └─ Text \"*\""
        XCTAssertEqual(expected, tree())
    }
}
