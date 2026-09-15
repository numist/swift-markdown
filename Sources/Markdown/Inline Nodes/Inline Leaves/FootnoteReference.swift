/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// An inline reference to a footnote, written as `[^label]`.
///
/// Footnote references and definitions are a GitHub Flavored Markdown extension enabled with
/// the ``ParseOptions/footnotes`` option. A reference resolves to a ``FootnoteDefinition`` by
/// its label; ``footnoteIndex`` is the 1-based index assigned to the definition in the order
/// its references first appear in the document.
public struct FootnoteReference: InlineMarkup {
    public var _data: _MarkupData

    init(_ raw: RawMarkup) throws {
        guard case .footnoteReference = raw.data else {
            throw RawMarkup.Error.concreteConversionError(from: raw, to: FootnoteReference.self)
        }
        let absoluteRaw = AbsoluteRawMarkup(markup: raw, metadata: MarkupMetadata(id: .newRoot(), indexInParent: 0))
        self.init(_MarkupData(absoluteRaw))
    }

    init(_ data: _MarkupData) {
        self._data = data
    }
}

// MARK: - Public API

public extension FootnoteReference {
    /// Create a footnote reference with a label and index.
    init(label: String, index: Int) {
        try! self.init(.footnoteReference(parsedRange: nil, label: label, index: index))
    }

    /// The reference's label, matching that of its ``FootnoteDefinition``.
    var footnoteLabel: String {
        get {
            guard case let .footnoteReference(label, _) = _data.raw.markup.data else {
                fatalError("\(self) markup wrapped unexpected \(_data.raw)")
            }
            return label
        }
        set {
            _data = _data.replacingSelf(.footnoteReference(parsedRange: nil, label: newValue, index: footnoteIndex))
        }
    }

    /// The 1-based index of the referenced definition, in the order references first appear.
    var footnoteIndex: Int {
        get {
            guard case let .footnoteReference(_, index) = _data.raw.markup.data else {
                fatalError("\(self) markup wrapped unexpected \(_data.raw)")
            }
            return index
        }
        set {
            _data = _data.replacingSelf(.footnoteReference(parsedRange: nil, label: footnoteLabel, index: newValue))
        }
    }

    // MARK: Visitation

    func accept<V: MarkupVisitor>(_ visitor: inout V) -> V.Result {
        return visitor.visitFootnoteReference(self)
    }

    // MARK: PlainTextConvertibleMarkup

    var plainText: String {
        return "[^\(footnoteLabel)]"
    }
}
