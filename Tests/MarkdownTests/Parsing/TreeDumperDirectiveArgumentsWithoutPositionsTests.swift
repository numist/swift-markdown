/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest

/// The tree dumper prints a block directive's argument text segments without source locations when
/// `.printSourceLocations` is off.
class TreeDumperDirectiveArgumentsWithoutPositionsTests: XCTestCase {
    func testDirectiveArgumentsPrintedWithoutPositions() {
        XCTAssertEqual(
            "Document\n└─ BlockDirective name: \"k\"\n   ├─ Argument text segments:\n   |    \"P\"\n   |    \"j\"",
            Document(parsing: "@k(P\nj", options: [.parseBlockDirectives]).debugDescription(options: []))
    }
}
