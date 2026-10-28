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

    @Test(arguments: [
        ("| a | b |\n|---|---|\n| c | d |\n", 30),
        ("> | a | b |\n> |---|---|\n> | c | d |\n", 30),
        ("> a\n> |-\n", 5),
        ("| a | b |\n|---|---|\n| c \\| e | d |\n", 40),
        ("| a | b |\n|---|---|\n| `c\\|d` | `e` |\n", 42),
    ])
    func materializedSize(_ source: String, _ size: Int) {
        let measured = MarkdownDocument.withParsedDocument(source, options: Self.options) { $0._materializedStringSize }
        #expect(measured == size)
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
        ("> | a | b |\n> |---|---|\n> | c | d |\n", """
            "a" copy
            "b" copy
            "c" copy
            "d" copy

            """),
    ])
    func cellTextOwnership(_ source: String, _ text: String) {
        guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { return }
        #expect(SourceBackedText.describe(source, options: Self.options) == text)
    }
}
