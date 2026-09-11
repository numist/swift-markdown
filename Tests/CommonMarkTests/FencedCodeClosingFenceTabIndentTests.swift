/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// A fenced-code CLOSING fence may be indented by at most 3 COLUMNS (CommonMark §4.5). cmark measures
/// that indentation in columns (blocks.c `parser->indent <= 3`, where a tab advances to the next tab
/// stop), so a line led by a TAB has 4 columns of indentation and is NOT a closing fence - it is code
/// content. The rewrite previously measured the closing-fence indent in BYTES, counting a leading tab
/// as one column, so a tab-indented fence line was mistaken for a close and truncated the code block.
///
/// Lines inside an open fenced code block skip the leading-tab pre-expansion (`expandPrefixTabs`), so
/// the closing-fence line still carries its literal tab - which is exactly why the byte count diverged.
@Suite("Fenced-code closing fence: tab-led line is content, not a close")
struct FencedCodeClosingFenceTabIndentTests {

    // FIX: the `\t```` line is indented 4 columns (one tab), so it is content, not a close. Its tab is
    // preserved literally (fence_offset is 0, so no columns are stripped from a content line).
    @Test("tab-led fence line is code content, not a closing fence")
    func tabLedLineIsContent() throws {
        try MarkdownDocument.withParsedDocument("```\n\t```") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds == [.document, .fencedCode()])
            try #require(codeBlocks(doc).count == 1)
            #expect(codeBlocks(doc).map(\.literal) == ["\t```\n"])
        }
    }

    // FIX: a preceding content line then the tab-led line - the block stays open and both are content.
    @Test("tab-led fence line after content stays content")
    func tabLedLineAfterContent() throws {
        try MarkdownDocument.withParsedDocument("```\nx\n\t```") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds == [.document, .fencedCode()])
            try #require(codeBlocks(doc).count == 1)
            #expect(codeBlocks(doc).map(\.literal) == ["x\n\t```\n"])
        }
    }

    // GUARD: a real closing fence with no indent closes the block, leaving it empty.
    @Test("unindented fence line closes the block")
    func unindentedLineCloses() throws {
        try MarkdownDocument.withParsedDocument("```\n```") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds == [.document, .fencedCode()])
            try #require(codeBlocks(doc).count == 1)
            #expect(codeBlocks(doc).map(\.literal) == [""])
        }
    }

    // GUARD: three spaces of indent (3 columns) still closes - the space analog of a passing indent.
    @Test("three-space-indented fence line still closes")
    func threeSpaceIndentCloses() throws {
        try MarkdownDocument.withParsedDocument("```\n   ```") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds == [.document, .fencedCode()])
            try #require(codeBlocks(doc).count == 1)
            #expect(codeBlocks(doc).map(\.literal) == [""])
        }
    }

    // GUARD: four spaces of indent (4 columns) fails the close test, so the line is content - the space
    // analog of the tab case, correct with either byte or column counting since 4 spaces == 4 columns.
    @Test("four-space-indented fence line is code content")
    func fourSpaceIndentIsContent() throws {
        try MarkdownDocument.withParsedDocument("```\n    ```") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds == [.document, .fencedCode()])
            try #require(codeBlocks(doc).count == 1)
            #expect(codeBlocks(doc).map(\.literal) == ["    ```\n"])
        }
    }
}
