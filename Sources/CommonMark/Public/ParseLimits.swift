/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

extension MarkdownDocument {
    /// Bounds on the size of constructs the parser recognizes.
    ///
    /// A construct past a limit is not recognized, and its source parses as other content, usually text. The defaults follow GFM 0.29 where it states a limit and are otherwise unlimited (`Int.max`). A value below its meaningful range behaves as the nearest meaningful value.
    ///
    ///     var limits = MarkdownDocument.ParseLimits()
    ///     limits.maxCodeSpanOpeningBackticks = 80
    ///     MarkdownDocument.withParsedDocument(source, limits: limits) { doc in
    ///         // ...
    ///     }
    public struct ParseLimits: Sendable, Hashable {
        /// The most characters a link label can have inside its brackets, for link references, link reference definitions and inline attribute labels. The default is the spec's 999.
        public var maxLinkLabelCharacters: Int = 999

        /// The most bytes a link label can have inside its brackets, for link references, link reference definitions and inline attribute labels.
        ///
        /// The bytes counted are those of the label's block content: container markers and indentation before each line are excluded, and a NUL counts as the 3 bytes of U+FFFD. The default is unlimited.
        public var maxLinkLabelBytes: Int = .max

        /// The most characters a footnote label can have inside its brackets, for footnote references and footnote definitions. The default is 999.
        public var maxFootnoteLabelCharacters: Int = 999

        /// The most bytes a footnote label can have inside its brackets, for footnote references and footnote definitions, counted as for `maxLinkLabelBytes`. The default is unlimited.
        public var maxFootnoteLabelBytes: Int = .max

        /// The most digits a decimal numeric character reference (`&#…;`) can have, leading zeros included. The default is the spec's 7.
        public var maxDecimalCharacterReferenceDigits: Int = 7

        /// The most digits a hexadecimal numeric character reference (`&#x…;`) can have, leading zeros included. The default is the spec's 6.
        public var maxHexadecimalCharacterReferenceDigits: Int = 6

        /// The deepest nesting of unescaped parentheses a link destination not enclosed in `<` `>` can have. The default is unlimited.
        ///
        /// The spec requires at least 3 levels to be supported, so a lower value is not spec-compliant.
        public var maxLinkDestinationParenthesisNesting: Int = .max

        /// The deepest nesting of unescaped parentheses inside the outer parentheses of an inline attribute's `^[…](…)` attributes. The default is unlimited.
        public var maxAttributeParenthesisNesting: Int = .max

        /// The longest backtick string that can open a code span. The default is unlimited.
        public var maxCodeSpanOpeningBackticks: Int = .max

        /// The number of containers opened earlier on the same line at which a list marker or a footnote definition is no longer recognized. Block quotes count toward it but are always recognized. The default is unlimited.
        public var maxContainersOpenedOnLineBeforeListMarker: Int = .max

        /// The longest opening code fence length a closing fence has to match: a closing fence closes the block when its length is at least the smaller of the opening fence's length and this value. The default is unlimited.
        public var fenceLengthClampForClosing: Int = .max

        /// The length of the chunks a run of `~` is split into, from its start, when parsing strikethrough. Each chunk is a potential delimiter on its own. The default is unlimited, so a run is one chunk.
        public var strikethroughTildeRunChunk: Int = .max

        /// The bytes of destination and title that link references can expand to, in total.
        ///
        /// The budget is the larger of this value and the source's byte count. Each resolved link reference, in document order, is charged the bytes of its definition's destination and title after unescaping and entity decoding; a reference whose charge would exceed the budget is not resolved. Footnote and inline attribute references are not charged. The default is unlimited.
        public var referenceExpansionBudget: Int = .max

        /// The most cells a table row can have. Every cell a line splits into counts, empty cells and span fillers included, before a body row is cut to the header's width. A delimiter row past it opens no table, and neither does one below a paragraph line past it; a body row past it ends the table and starts a paragraph. The default is unlimited.
        public var maxTableRowCells: Int = .max

        /// The most empty cells a table can add to pad its body rows to the header's width. A body row is not part of the table once the cells added to the rows before it exceed this: it ends the table and starts a paragraph. The default is unlimited.
        public var maxTableAutocompletedCells: Int = .max

        /// Creates the default limits.
        public init() {}
    }
}
