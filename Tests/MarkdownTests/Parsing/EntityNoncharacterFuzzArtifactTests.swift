/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @_spi(InlineOnly) @testable import Markdown
import XCTest

/// Minimized differential-fuzzer artifact; the expected surface is the cmark-gfm reference's output bytes.
/// Input is `[markdown …][option byte]`, split as the fuzzer does. Position-free compare surface.
class EntityNoncharacterFuzzArtifactTests: XCTestCase {
    func testFuzzedArtifact() {
        let (markdown, options) = FuzzRegressionTests.splitInput([38, 35, 54, 53, 53, 51, 52, 59, 0])!
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"\u{fffd}\"", Document(parsing: markdown, options: options.union(.cmarkBugCompatibility)).debugDescription(options: []))
    }
}
