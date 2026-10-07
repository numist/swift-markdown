/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

/// The tree dumper prints a block directive's argument text segments without source locations when
/// `.printSourceLocations` is off.
class TreeDumperDirectiveArgumentsWithoutPositionsTests: XCTestCase {
    func testDirectiveArgumentsPrintedWithoutPositions() {
        let (markdown, options) = DocumentRegressionTests.splitInput([64, 107, 40, 80, 10, 106, 9])!
        XCTAssertEqual("Document\n└─ BlockDirective name: \"k\"\n   ├─ Argument text segments:\n   |    \"P\"\n   |    \"j\"", Document(parsing: markdown, options: options).debugDescription(options: []))
    }
}
