/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

extension MarkdownDocument {
    /// Options that control how a `MarkdownDocument` parses its source.
    ///
    /// Options enable GitHub Flavored Markdown extensions, inline attributes, source positions, or inline-only parsing. The empty set parses CommonMark.
    ///
    ///     let options: MarkdownDocument.ParseOptions = [.tables, .strikethrough, .footnotes]
    ///     MarkdownDocument.withParsedDocument(source, options: options) { doc in
    ///         // ...
    ///     }
    public struct ParseOptions: OptionSet, Sendable, Hashable {
        /// The bit mask that represents this set of options.
        public let rawValue: Int

        /// Creates a set of parse options from a raw bit mask.
        ///
        /// - Parameter rawValue: The bit mask that represents the options.
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        /// Tracks a source range for each node, which you read with `MarkdownNode.sourceRange`.
        ///
        /// Without this option, `MarkdownNode.sourceRange` returns `nil`.
        public static let sourcePosition = MarkdownDocument.ParseOptions(rawValue: 1 << 1)

        /// Converts straight quotes to curly quotes, `--` to an en dash, `---` to an em dash, and `...` to an ellipsis.
        public static let smart = MarkdownDocument.ParseOptions(rawValue: 1 << 10)

        /// Parses footnote references and definitions, written as `[^label]` and `[^label]:`.
        public static let footnotes = MarkdownDocument.ParseOptions(rawValue: 1 << 13)

        /// Requires two tildes for strikethrough, as in `~~text~~`, and rejects a single tilde.
        public static let strikethroughDoubleTilde = MarkdownDocument.ParseOptions(rawValue: 1 << 14)

        /// Parses only inline content, ignoring block structure.
        public static let inlineOnly = MarkdownDocument.ParseOptions(rawValue: 1 << 18)

        /// Parses only inline content while preserving source whitespace, such as tabs and repeated spaces.
        public static let preserveWhitespace: MarkdownDocument.ParseOptions = [
            .inlineOnly,
            MarkdownDocument.ParseOptions(rawValue: 1 << 19),
        ]

        /// Allows row and column spans in GFM tables.
        public static let tableSpans = MarkdownDocument.ParseOptions(rawValue: 1 << 20)

        /// Treats a `"` in a GFM table cell as a ditto mark that repeats the cell above.
        public static let tableRowspanDitto = MarkdownDocument.ParseOptions(rawValue: 1 << 21)

        /// Enables GFM strikethrough, written as `~text~` or `~~text~~`.
        ///
        /// Without this option, `~` is ordinary text. Combine it with `.strikethroughDoubleTilde` to require exactly two tildes on each side.
        public static let strikethrough = MarkdownDocument.ParseOptions(rawValue: 1 << 22)

        /// Enables GFM task list items.
        ///
        /// A list item whose first paragraph begins with `[ ]`, `[x]`, or `[X]` becomes an unchecked or checked task list item.
        public static let tasklist = MarkdownDocument.ParseOptions(rawValue: 1 << 23)

        /// Enables GFM extended autolinks.
        ///
        /// Bare URLs, such as `https://example.com` and `www.example.com`, and email addresses become `.link` nodes without requiring angle brackets around them.
        public static let gfmAutolink = MarkdownDocument.ParseOptions(rawValue: 1 << 24)

        /// Enables GFM tables.
        ///
        /// A paragraph whose second line is a delimiter row, such as `| --- | :---: |`, becomes a table.
        public static let tables = MarkdownDocument.ParseOptions(rawValue: 1 << 25)

        /// Enables inline attributes, written as `^[text](key: value)`, and attribute definitions, written as `^[label]: key: value`.
        ///
        /// An inline attribute becomes an `.attribute` node whose children are the bracketed text; `^[text][label]` takes its attributes from the definition with that label. Without this option, `^[` has no special meaning.
        public static let attributes = MarkdownDocument.ParseOptions(rawValue: 1 << 28)
    }
}
