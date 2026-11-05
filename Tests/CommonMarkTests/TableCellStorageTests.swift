/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// A table cell whose content holds no `\|` is stored as the cell's own source bytes when the table's lines are
/// contiguous in the source, and is never copied a second time.
@Suite("Table cells without escaped pipes store no extra copy")
struct TableCellStorageTests {
    private static let options: MarkdownDocument.ParseOptions = [.tables, .sourcePosition]

    /// The stored strings take at most the table's lines, without block quote markers, plus `unescapedCells`, the content
    /// of the cells holding `\|` with each `\|` replaced by `|`.
    @Test(arguments: [
        ("| a | b |\n|---|---|\n| c | d |\n", ""),
        ("> | a | b |\n> |---|---|\n> | c | d |\n", ""),
        ("> a\n> |-\n", ""),
        ("| a | b |\n|---|---|\n| c \\| e | d |\n", "c | e"),
        ("| a | b |\n|---|---|\n| `c\\|d` | `e` |\n", "`c|d`"),
    ])
    func cellsWithoutEscapedPipesAreNotCopiedAgain(_ source: String, _ unescapedCells: String) {
        let (measured, hasTable) = MarkdownDocument.withParsedDocument(source, options: Self.options) { doc in
            var hasTable = false
            doc.root.children.forEach { block in
                block.children.forEach { if $0.kind == .table { hasTable = true } }
                if block.kind == .table { hasTable = true }
            }
            return (doc._materializedStringSize, hasTable)
        }
        let tableLines = source.split(separator: "\n").map { $0.hasPrefix("> ") ? $0.dropFirst(2) : $0 }
        let tableText = tableLines.joined(separator: "\n") + "\n"
        #expect(hasTable)
        #expect(measured <= tableText.utf8.count + unescapedCells.utf8.count)
    }

    @Test(arguments: [
        ("| a | b |\n|---|---|\n| c | d |\n", """
            "a" source
            "b" source
            "c" source
            "d" source

            """),
        ("| a | b |\n|---|---|\n| c \\| e | d |\n", """
            "a" source
            "b" source
            "c | e" copy
            "d" source

            """),
    ])
    func cellTextOwnership(_ source: String, _ text: String) {
        guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { return }
        #expect(SourceBackedText.describe(source, options: Self.options) == text)
    }
}
