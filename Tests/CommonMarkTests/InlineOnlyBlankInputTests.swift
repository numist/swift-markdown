/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

@Suite("Inline-only parsing of empty and blank input")
struct InlineOnlyBlankInputTests {
    /// Any input line, even a blank or BOM-only one, opens the paragraph; input with no bytes has no line and so no paragraph.
    @Test(arguments: [
        [.tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .smart, .inlineOnly],
        [.tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .smart, .preserveWhitespace],
    ] as [MarkdownDocument.ParseOptions])
    func testEmptyAndBlankInputs(options: MarkdownDocument.ParseOptions) {
        #expect(TreeDump.dump("", options: options) == "document\n")
        #expect(TreeDump.dump("\u{FEFF}", options: options) == "document\n  paragraph\n")
        #expect(TreeDump.dump("\u{FEFF}\n", options: options) == "document\n  paragraph\n    text \"\\n\"\n")
        #expect(TreeDump.dump("\u{FEFF}  ", options: options) == "document\n  paragraph\n    text \"  \"\n")
        #expect(TreeDump.dump("\n", options: options) == "document\n  paragraph\n    text \"\\n\"\n")
    }
}
