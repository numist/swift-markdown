/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

/// Minimized differential-fuzzer artifact.
/// Input is `[markdown …][option byte]`, split as the fuzzer does. Position-free compare surface.
class SetextRefdefLazySpaceFuzzArtifactTests: XCTestCase {
    /// Flag-off (shipped): a setext heading's content is stripped of leading whitespace, where cmark-gfm
    /// keeps the lazy continuation line's leading space after resolving the reference definition.
    func testFlagOff() {
        let (markdown, options) = FuzzRegressionTests.splitInput([62, 91, 97, 93, 58, 117, 10, 32, 255, 10, 62, 61, 10])!
        XCTAssertEqual("Document\n└─ BlockQuote\n   └─ Heading level: 1\n      └─ Text \"\u{fffd}\"", Document(parsing: markdown, options: options).debugDescription(options: []))
    }
}
