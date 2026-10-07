/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

/// Covers the tree dumper's block-directive argument printing without source locations (the
/// fuzzer's compare surface), which the position-printing `FuzzRegressions` pairs never reach.
/// The expected surface is the cmark-gfm reference's output bytes for the same input.
class TreeDumperDirectiveArgumentsWithoutPositionsTests: XCTestCase {
    func testDirectiveArgumentsPrintedWithoutPositions() {
        let (markdown, options) = FuzzRegressionTests.splitInput([64, 107, 40, 80, 10, 106, 9])!
        XCTAssertEqual("Document\n└─ BlockDirective name: \"k\"\n   ├─ Argument text segments:\n   |    \"P\"\n   |    \"j\"", Document(parsing: markdown, options: options).debugDescription(options: []))
    }
}
