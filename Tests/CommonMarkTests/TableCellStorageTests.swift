/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// A table's cells are stored as their own source bytes, whether or not the table's lines are contiguous in the
/// source. Only a cell whose text differs from its source, because it holds `\|` or a NUL, is copied.
@Suite("Table cells store only the text that differs from the source")
struct TableCellStorageTests {
    private static let options: MarkdownDocument.ParseOptions = [.tables, .sourcePosition]

    /// The stored strings hold one shared line ending, plus the text of each copied cell: `\|` becomes `|`, and a NUL
    /// becomes U+FFFD (Insecure characters), which takes three bytes.
    @Test(arguments: [
        ("| a | b |\n|---|---|\n| c | d |\n", 1),
        ("> | a | b |\n> |---|---|\n> | c | d |\n", 1),
        ("> a\n> |-\n", 1),
        ("- a | b\n  --|--\n  c | d\n", 1),
        ("> p\n> a | b\n> --|--\n", 1),
        ("| a | b |\n|---|---|\n| c \\| e | d |\n", 6),
        ("| a | b |\n|---|---|\n| `c\\|d` | `e` |\n", 6),
        ("| a | b |\n|---|---|\n| c\0 | d |\n", 5),
        ("> a | b\n> --|--\n> c\0 | d\n", 5),
        ("| a | b |\n|---|---|\n| \0\\| | d |\n", 5),
    ])
    func onlyCellsWithDifferingTextAreCopied(_ source: String, _ storedSize: Int) {
        #expect(MarkdownDocument.withParsedDocument(source, options: Self.options) { $0._materializedStringSize } == storedSize)
    }

    @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
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
        ("> a | b\n> --|--\n> c\0 | d\n", """
            "a" source
            "b" source
            "c\u{FFFD}" copy
            "d" source

            """),
    ])
    func cellTextOwnership(_ source: String, _ text: String) {
        #expect(SourceBackedText.describe(source, options: Self.options) == text)
    }
}
