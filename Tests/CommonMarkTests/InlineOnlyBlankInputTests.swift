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
    /// cmark opens the paragraph for any input line, even a blank or BOM-only one, and keeps it empty; only input with no bytes at all has no line and so no paragraph.
    @Test(arguments: [
        [.tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .smart, .inlineOnly],
        [.tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .smart, .preserveWhitespace],
    ] as [MarkdownDocument.ParseOptions])
    func testEmptyAndBlankInputs(options: MarkdownDocument.ParseOptions) {
        #expect(CmarkTreeDump.dump("", options: options) == "document\n")
        #expect(CmarkTreeDump.dump("\u{FEFF}", options: options) == "document\n  paragraph\n")
        #expect(CmarkTreeDump.dump("\u{FEFF}\n", options: options) == "document\n  paragraph\n    text \"\\n\"\n")
        #expect(CmarkTreeDump.dump("\u{FEFF}  ", options: options) == "document\n  paragraph\n    text \"  \"\n")
        #expect(CmarkTreeDump.dump("\n", options: options) == "document\n  paragraph\n    text \"\\n\"\n")
    }
}
