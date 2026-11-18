/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// A parsed Markdown document.
///
/// A document borrows the UTF-8 bytes of its source instead of copying them, so its lifetime is bounded by that borrow and the source must outlive it. Because a document can't escape its borrow scope, the entry point that works on every OS release is `withParsedDocument(_:options:limits:_:)`, which passes the borrowed document to a closure. Where `UTF8Span` is available, `init(parsing:options:limits:)` returns a document whose lifetime is tied to the source instead.
///
///     let source = "# Hello\n\nworld"
///     MarkdownDocument.withParsedDocument(source) { document in
///         document.root.children.forEach { print($0.kind) }
///     }
public struct MarkdownDocument: ~Copyable, ~Escapable {

    internal var _storage: DocumentStorage

    internal let _source: Span<UInt8>

    /// Core parser entry: borrow the source bytes and parse. Internal - `Span<UInt8>` is not public API (the public surface only accepts `String` / `UTF8Span`, guaranteeing validated Unicode input).
    @_lifetime(copy source)
    internal init(parsing source: Span<UInt8>, options: MarkdownDocument.ParseOptions = [], limits: MarkdownDocument.ParseLimits = .init()) {
        let storage = DocumentStorage(options: options)
        let parser = BlockParser(storage: storage, source: source, limits: limits)
        self._storage = parser.parse()
        self._source = source
        assert(_storage.validateOutput(source: source))
    }

    /// Creates a document by parsing UTF-8 text.
    ///
    /// The document borrows `source`'s bytes instead of copying them, so its lifetime is tied to `source`.
    ///
    /// - Parameters:
    ///   - source: The Markdown text to parse.
    ///   - options: The options that control parsing.
    ///   - limits: The bounds and settings that control which constructs the parser recognizes.
    @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    @_lifetime(copy source)
    public init(parsing source: UTF8Span, options: MarkdownDocument.ParseOptions = [], limits: MarkdownDocument.ParseLimits = .init()) {
        self.init(parsing: source.span, options: options, limits: limits)
    }

    /// Parses a string as Markdown and passes the borrowed document to a closure.
    ///
    /// Use this method to parse on any supported OS release. The document borrows the string's UTF-8 bytes for the duration of `body`, so neither the document nor any `MarkdownNode` obtained from it can escape the closure.
    ///
    /// - Parameters:
    ///   - source: The Markdown text to parse.
    ///   - options: The options that control parsing.
    ///   - limits: The bounds and settings that control which constructs the parser recognizes.
    ///   - body: A closure that receives the borrowed document, valid only for the duration of the call.
    /// - Returns: The value returned by `body`.
    public static func withParsedDocument<R>(
        _ source: borrowing String,
        options: MarkdownDocument.ParseOptions = [],
        limits: MarkdownDocument.ParseLimits = .init(),
        _ body: (borrowing MarkdownDocument) throws -> R
    ) rethrows -> R {
#if !(os(watchOS) && _pointerBitWidth(_32))
        if #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) {
            let utf8 = source.utf8Span
            let document = MarkdownDocument(parsing: utf8, options: options, limits: limits)
            return try body(document)
        }
#else
        if #available(watchOS 26, *) {
            if let utf8 = source._utf8Span {
                let document = MarkdownDocument(parsing: utf8, options: options, limits: limits)
                return try body(document)
            }
            // Only a small string has no contiguous UTF-8 here, and `withUTF8` would copy all of its bytes too.
            let bytes = ContiguousArray(source.utf8)
            let document = MarkdownDocument(parsing: bytes.span, options: options, limits: limits)
            return try body(document)
        }
#endif
        var contiguous = copy source
        return try contiguous.withUTF8 { buffer in
            // SAFETY: `buffer` is valid for this closure, and the span over it backs a document that `body` borrows and can't escape, so no access outlives it.
            //         Before anyAppleOS 26 no API vends a `Span` over a `String`'s UTF-8, so a safe span needs a copy of the whole source.
            let document = MarkdownDocument(parsing: unsafe Span(_unsafeElements: buffer), options: options, limits: limits)
            return try body(document)
        }
    }

    /// The root node of the document's syntax tree.
    ///
    /// Its kind is always `.document`.
    public var root: MarkdownNode {
        @_lifetime(borrow self)
        borrowing get {
            let view = StorageView(storage: _storage, source: _source)
            return MarkdownNode(view: view, index: DocumentStorage.Index(0))
        }
    }

    /// The options the document was parsed with.
    public var options: MarkdownDocument.ParseOptions {
        borrowing get { _storage.options }
    }

    /// The source text the document was parsed from.
    @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    public var source: UTF8Span {
        @_lifetime(borrow self)
        borrowing get {
            // SAFETY: The source is already known-valid UTF-8 - it came from a validated `String` or `UTF8Span` at construction - so skip re-validation with the unchecked initializer.
            //         `UTF8Span(validating:)` would make this O(1) accessor O(n).
            unsafe UTF8Span(unchecked: _source)
        }
    }

    /// The number of lines in the document.
    public var lineCount: Int {
        _storage.lineCount
    }

    /// The size in bytes of the materialized string buffer, for debugging and optimization.
    public var _materializedStringSize: Int {
        _storage.strings.count
    }

    /// The number of content segments in the storage pool, for debugging and optimization.
    public var _segmentCount: Int {
        _storage.segments.count
    }
}

#if !(os(watchOS) && _pointerBitWidth(_32))
extension MarkdownDocument {
    /// Creates a document by parsing a string as Markdown.
    ///
    /// The document borrows the string's UTF-8 bytes instead of copying them, so its lifetime is tied to `source`. To parse on an OS release that doesn't provide `UTF8Span`, use `withParsedDocument(_:options:limits:_:)` instead.
    ///
    /// - Parameters:
    ///   - source: The Markdown text to parse.
    ///   - options: The options that control parsing.
    ///   - limits: The bounds and settings that control which constructs the parser recognizes.
    @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    @_lifetime(borrow source)
    public init(parsing source: borrowing String, options: MarkdownDocument.ParseOptions = [], limits: MarkdownDocument.ParseLimits = .init()) {
        self.init(parsing: source.utf8Span, options: options, limits: limits)
    }
}
#endif
