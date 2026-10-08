/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A closing code fence may be indented up to three spaces (Fenced code blocks). A leading tab advances to
/// column 4 (Tabs), so a tab-indented fence line is code content, not a closing fence.
@Suite("Fenced code block closing fence indentation")
struct FencedCodeClosingFenceTabIndentTests {

    // The opening fence is unindented, so no indentation is removed from content lines and the tab is kept.
    @Test("tab-led fence line is code content, not a closing fence")
    func tabLedLineIsContent() throws {
        try MarkdownDocument.withParsedDocument("```\n\t```") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds == [.document, .fencedCode()])
            try #require(codeBlocks(doc).count == 1)
            #expect(codeBlocks(doc).map(\.literal) == ["\t```\n"])
        }
    }

    @Test("tab-led fence line after content stays content")
    func tabLedLineAfterContent() throws {
        try MarkdownDocument.withParsedDocument("```\nx\n\t```") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds == [.document, .fencedCode()])
            try #require(codeBlocks(doc).count == 1)
            #expect(codeBlocks(doc).map(\.literal) == ["x\n\t```\n"])
        }
    }

    @Test("unindented fence line closes the block")
    func unindentedLineCloses() throws {
        try MarkdownDocument.withParsedDocument("```\n```") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds == [.document, .fencedCode()])
            try #require(codeBlocks(doc).count == 1)
            #expect(codeBlocks(doc).map(\.literal) == [""])
        }
    }

    @Test("three-space-indented fence line closes the block")
    func threeSpaceIndentCloses() throws {
        try MarkdownDocument.withParsedDocument("```\n   ```") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds == [.document, .fencedCode()])
            try #require(codeBlocks(doc).count == 1)
            #expect(codeBlocks(doc).map(\.literal) == [""])
        }
    }

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
