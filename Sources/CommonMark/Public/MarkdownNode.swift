/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// A borrowed view of a single node in a `MarkdownDocument`'s syntax tree.
///
/// A node can't outlive its document, and moving through the tree neither allocates nor copies.
public struct MarkdownNode: ~Escapable {

    internal let _view: StorageView

    internal let _index: DocumentStorage.Index

    @_lifetime(copy view)
    internal init(view: StorageView, index: DocumentStorage.Index) {
        self._view = view
        self._index = index
    }

    /// The kind of this node.
    public var kind: MarkdownNode.Kind {
        borrowing get {
            _view.record(at: _index).kind
        }
    }

    /// A Boolean value that indicates whether the node has no children.
    public var isLeaf: Bool {
        borrowing get {
            _view.record(at: _index).firstChild == nil
        }
    }

    /// A sequence over the node's children, in document order.
    public var children: Children {
        @_lifetime(borrow self)
        borrowing get {
            Children(view: _view, first: _view.record(at: _index).firstChild)
        }
    }

    /// The node's first child, or `nil` if it has no children.
    ///
    /// A navigated node shares the document's borrow, so you can reassign a `var` to walk the tree iteratively.
    public var firstChild: MarkdownNode? {
        @_lifetime(copy self)
        borrowing get {
            guard let f = _view.record(at: _index).firstChild else {
                return nil
            }

            return MarkdownNode(view: _view, index: f)
        }
    }

    /// The node's parent, or `nil` if this is the document root.
    public var parent: MarkdownNode? {
        @_lifetime(copy self)
        borrowing get {
            guard let p = _view.record(at: _index).parent else {
                return nil
            }

            return MarkdownNode(view: _view, index: p)
        }
    }

    /// The next sibling, or `nil` if this is the last child of its parent.
    public var next: MarkdownNode? {
        @_lifetime(copy self)
        borrowing get {
            guard let n = _view.record(at: _index).next else {
                return nil
            }

            return MarkdownNode(view: _view, index: n)
        }
    }

    /// The previous sibling, or `nil` if this is the first child of its parent.
    public var previous: MarkdownNode? {
        @_lifetime(copy self)
        borrowing get {
            guard let p = _view.record(at: _index).previous else {
                return nil
            }

            return MarkdownNode(view: _view, index: p)
        }
    }
}

extension MarkdownNode {
    /// A sequence of a node's children, returned by `MarkdownNode.children`.
    ///
    /// Iterate the children with `forEach(_:)`, which doesn't allocate.
    public struct Children: ~Copyable, ~Escapable {

        internal let _view: StorageView

        internal let _first: DocumentStorage.Index?

        @_lifetime(copy view)
        internal init(view: StorageView, first: DocumentStorage.Index?) {
            self._view = view
            self._first = first
        }

        /// Calls `body` with each child node, in document order.
        ///
        /// A `MarkdownNode` is nonescapable, so iteration takes a closure rather than using `for`-`in`.
        ///
        /// - Parameter body: A closure that receives each child node.
        public borrowing func forEach<E: Swift.Error>(_ body: (borrowing MarkdownNode) throws(E) -> Void) throws(E) {
            var current = _first
            while let valid = current {
                let node = MarkdownNode(view: _view, index: valid)
                try body(node)
                current = _view.record(at: valid).next
            }
        }
    }
}

extension MarkdownNode {
    /// The literal text of a node, as an ordered sequence of contiguous UTF-8 segments.
    ///
    /// The `.text`, `.codeBlock`, and `.htmlBlock` cases of `MarkdownNode.Content` carry it. Each segment addresses the document's bytes in place.
    public struct Segments: ~Copyable, ~Escapable {

        internal let _view: StorageView

        internal let _ref: ContentRef

        @_lifetime(copy view)
        internal init(view: StorageView, ref: ContentRef) {
            self._view = view
            self._ref = ref
        }

        /// The number of segments.
        public var count: Int {
            Int(_ref.count)
        }

        /// A Boolean value that indicates whether there is no content.
        public var isEmpty: Bool {
            _ref.count == 0
        }

        /// The total byte length across all segments.
        public var byteCount: Int {
            Int(_ref.totalLength)
        }

        /// Calls `body` with each segment, in order.
        ///
        /// A `UTF8Span` is nonescapable, so iteration takes a closure rather than using `for`-`in`.
        ///
        /// - Parameter body: A closure that receives each segment.
        @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
        public borrowing func forEach<E: Swift.Error>(_ body: (borrowing UTF8Span) throws(E) -> Void) throws(E) {
            for i in 0..<Int(_ref.count) {
                let segment = _view.segments[Int(_ref.first) + i]
                try body(_view.utf8Span(of: segment))
            }
        }
    }
}

extension MarkdownNode {
    /// The kind of a node in the syntax tree.
    ///
    /// Several cases carry metadata as associated values, so match a kind with `switch` or `if case` rather than `==`.
    public enum Kind: Sendable, Hashable {
        // Block kinds

        /// The root of the document tree.
        case document
        /// A block quote (`>`-prefixed lines).
        case blockQuote
        /// A bullet or ordered list.
        case list(ListInfo)
        /// A list item. With `MarkdownDocument.ParseOptions.tasklist`, `checked` is a task list item's checkbox state; it is `nil` for any other item.
        case item(checked: Bool?)
        /// A fenced or indented code block.
        case codeBlock(CodeBlockInfo)
        /// A block of raw HTML.
        case htmlBlock
        /// A paragraph of inline content.
        case paragraph
        /// A heading. `level` is the heading level, `1` through `6`.
        case heading(level: Int)
        /// A thematic break (a horizontal rule, such as `---`).
        case thematicBreak
        /// A footnote definition (`[^label]: …`), produced when parsing with `MarkdownDocument.ParseOptions.footnotes`.
        ///
        /// Footnote definitions are children of the document, after its other blocks, in the order their labels are first referenced. A definition whose label no reference uses is dropped, as is any later definition of the same label.
        case footnoteDefinition
        /// A GFM table, produced when parsing with `MarkdownDocument.ParseOptions.tables`.
        case table
        /// A table row. `isHeader` is `true` for the header row and `false` for a body row.
        case tableRow(isHeader: Bool)
        /// A table cell, carrying its column `alignment` and the number of `columns` and `rows` it spans.
        ///
        /// Both are `1` for an ordinary cell. With `MarkdownDocument.ParseOptions.tableSpans`:
        /// - An empty cell, with nothing between its pipes (`||`), reports `columns: 0`. The nearest cell to its left that isn't empty, if there is one, counts it in `columns`, so a non-empty cell's `columns` is one plus the number of empty cells directly after it, including empty cells past the table's last column, which the row doesn't hold.
        /// - A cell holding only the rowspan marker, `^` (`"` in its place with `.tableRowspanDitto`), reports `rows: 0`. The nearest cell above it that isn't a marker cell counts it in `rows`, and the marker cell's text is dropped. A marker cell with no such cell above it, such as one in the header row, keeps its marker text.
        case tableCell(alignment: TableAlignment, columns: Int, rows: Int)

        // Inline kinds

        /// A run of literal text.
        case text
        /// A soft line break (a line ending within a paragraph that renders as a space).
        case softBreak
        /// A hard line break (a line ending with two or more spaces or a backslash).
        case lineBreak
        /// An inline code span. `backtickCount` is the length of each delimiter run, which the node's source range includes.
        case codeInline(backtickCount: Int)
        /// An inline span of raw HTML.
        case htmlInline
        /// Emphasized text (`*text*` or `_text_`), typically rendered italic.
        case emphasis
        /// Strongly emphasized text (`**text**` or `__text__`), typically rendered bold.
        case strong
        /// A link. The destination URL and title are available through the node's content.
        case link
        /// An image. The source URL and title are available through the node's content.
        case image
        /// A footnote reference (`[^label]`), produced when parsing with `MarkdownDocument.ParseOptions.footnotes`. `index` numbers labels from 1 in order of first reference; repeated references reuse it.
        case footnoteReference(index: Int)
        /// Struck-through text (`~text~` or `~~text~~`), produced when parsing with `MarkdownDocument.ParseOptions.strikethrough`.
        case strikethrough
        /// An inline attribute (`^[…]`), produced when parsing with `MarkdownDocument.ParseOptions.attributes`. The raw attribute string is available through the node's content.
        case attribute
        
        /// A Boolean value that indicates whether this is a block-level kind.
        public var isBlock: Bool {
            switch self {
            case .document, .blockQuote, .list, .item, .codeBlock, .htmlBlock,
                 .paragraph, .heading, .thematicBreak,
                 .footnoteDefinition, .table, .tableRow, .tableCell:
                return true
            default:
                return false
            }
        }

        /// A Boolean value that indicates whether this is an inline-level kind.
        public var isInline: Bool {
            !isBlock
        }

        /// The leaf blocks that accumulate text lines.
        internal var canAccumulateText: Bool {
            switch self {
            case .paragraph, .heading:
                return true
            default:
                return false
            }
        }

        internal var isCodeBlock: Bool {
            if case .codeBlock = self {
                return true
            }
            return false
        }

        internal var isList: Bool {
            if case .list = self {
                return true
            }
            return false
        }
    }

    /// Column alignment for a GFM table cell.
    public enum TableAlignment: UInt8, Sendable, Hashable {
        /// No explicit alignment (a `---` delimiter row cell).
        case none
        /// Left-aligned (a `:---` delimiter row cell).
        case left
        /// Center-aligned (a `:---:` delimiter row cell).
        case center
        /// Right-aligned (a `---:` delimiter row cell).
        case right
    }

    /// List-specific metadata exposed on `MarkdownNode.Kind.list` nodes.
    public struct ListInfo: Sendable, Hashable {
        /// Bullet vs. ordered list.
        public enum Kind: UInt8, Sendable, Hashable {
            /// An unordered list, whose items begin with a bullet marker.
            case bullet
            /// An ordered list, whose items begin with a number and delimiter.
            case ordered
        }

        /// Marker character used by a bullet-list item (`-`, `+`, or `*`).
        public enum BulletMarker: UInt8, Sendable, Hashable {
            /// A hyphen-minus marker (`-`).
            case hyphen
            /// A plus-sign marker (`+`).
            case plus
            /// An asterisk marker (`*`).
            case asterisk
        }

        /// Delimiter following an ordered-list start number (`1.` vs. `1)`).
        public enum OrderedDelimiter: UInt8, Sendable, Hashable {
            /// A period delimiter (`1.`).
            case period
            /// A closing-parenthesis delimiter (`1)`).
            case paren
        }

        /// Whether the list is a bullet or an ordered list.
        public var kind: Kind
        /// The start number of an ordered list; `1` for a bullet list.
        public var start: Int
        /// A Boolean value that indicates whether the list is tight: no blank line separates two of its items, or two blocks that one of its items directly contains.
        public var tight: Bool
        /// The delimiter of an ordered list's markers; `.period` for a bullet list.
        public var orderedDelimiter: OrderedDelimiter
        /// The marker character of a bullet list's items; `.hyphen` for an ordered list.
        public var bulletMarker: BulletMarker
    }

    /// Code-block metadata exposed on `MarkdownNode.Kind.codeBlock` nodes.
    public struct CodeBlockInfo: Sendable, Hashable {
        /// A Boolean value that indicates whether the block is fenced (`true`) or indented (`false`).
        public var isFenced: Bool
        /// Fence character, or `nil` for indented blocks.
        public var fenceCharacter: FenceCharacter?
        /// Number of fence characters used (3 or more); zero for indented blocks.
        public var fenceLength: Int
        /// Indentation of the opening fence, in columns from its container's content column; each content line loses up to this many columns of indentation. Zero for indented blocks.
        public var fenceOffset: Int
        
        /// Fence character for a code block.
        public enum FenceCharacter: UInt8, Sendable, Hashable {
            /// Code fenced with a backtick.
            case backtick
            
            /// Code fenced with a tilde.
            case tilde
            
            internal var character: UInt8 {
                switch self {
                case .backtick: UInt8(ascii: "`")
                case .tilde: UInt8(ascii: "~")
                }
            }
            
            internal init?(character: UInt8) {
                switch character {
                case UInt8(ascii: "`"): self = .backtick
                case UInt8(ascii: "~"): self = .tilde
                default:
                    return nil
                }
            }
        }
    }
}

extension MarkdownNode {
    /// A position in the source: a 1-based line and a 1-based UTF-8 byte column within it.
    public struct SourcePosition: Comparable, Hashable, Sendable {
        /// The 1-based line number.
        public var line: Int
        /// The 1-based UTF-8 byte offset within the line.
        public var column: Int

        /// Creates a source position.
        ///
        /// - Parameters:
        ///   - line: The 1-based line number.
        ///   - column: The 1-based UTF-8 byte offset within the line.
        public init(line: Int, column: Int) {
            self.line = line
            self.column = column
        }

        /// Returns a Boolean value that indicates whether the first position precedes the second.
        public static func < (lhs: SourcePosition, rhs: SourcePosition) -> Bool {
            (lhs.line, lhs.column) < (rhs.line, rhs.column)
        }
    }
}

extension MarkdownNode {
    /// The node's source range, or `nil` without `MarkdownDocument.ParseOptions.sourcePosition` or for a node that has no source range.
    ///
    /// The range runs from the node's first byte in the source, such as a block quote's `>` or a code span's opening backtick, to just past its last. Whitespace and blank lines after a block's last content are outside it, so a container ends with its last child or marker.
    public var sourceRange: Range<SourcePosition>? {
        _view.sourceRange(of: _index)
    }
}
