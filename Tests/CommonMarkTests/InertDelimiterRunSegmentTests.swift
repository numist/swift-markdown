/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

@Suite("A delimiter run that can neither open nor close is text in one segment with the text around it")
struct InertDelimiterRunSegmentTests {

    @Test(arguments: [
        ("a ** b", "a ** b"),
        ("a __ b", "a __ b"),
        ("a ~~ b", "a ~~ b"),
        ("a ~ b", "a ~ b"),
        ("a ~~~ b", "a ~~~ b"),
        ("a__b", "a__b"),
        ("a_b", "a_b"),
    ])
    func inertRun(source: String, quoted: String) {
        guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { return }
        #expect(TreeDump.dumpSegments(source, options: .strikethrough) == """
            document
              paragraph
                text "\(quoted)" ["\(quoted)"]

            """)
    }
}
