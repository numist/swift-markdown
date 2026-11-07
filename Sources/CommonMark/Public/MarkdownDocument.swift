/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// A parsed Markdown document.
///
/// A document borrows its source's UTF-8 bytes rather than copying them, so the source must outlive it. `withParsedDocument(_:options:_:)` works on every OS release; where `UTF8Span` is available, `init(parsing:options:)` returns a document whose lifetime is tied to the source.
///
///     let source = "# Hello\n\nworld"
///     MarkdownDocument.withParsedDocument(source) { document in
///         document.root.children.forEach { print($0.kind) }
///     }
public struct MarkdownDocument: ~Copyable, ~Escapable {

    internal var _storage: DocumentStorage

    internal let _source: Span<UInt8>

    /// Parses `source` in place. Internal because the public initializers accept only `String` and `UTF8Span`, which guarantee valid UTF-8.
    @_lifetime(copy source)
    internal init(parsing source: Span<UInt8>, options: MarkdownDocument.ParseOptions = []) {
        let storage = DocumentStorage(options: options)
        let parser = BlockParser(storage: storage, source: source)
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
    @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    @_lifetime(copy source)
    public init(parsing source: UTF8Span, options: MarkdownDocument.ParseOptions = []) {
        self.init(parsing: source.span, options: options)
    }

    /// Parses a string as Markdown and passes the borrowed document to a closure.
    ///
    /// This works on any supported OS release. Neither the document nor its nodes can escape `body`.
    ///
    /// - Parameters:
    ///   - source: The Markdown text to parse.
    ///   - options: The options that control parsing.
    ///   - body: A closure that receives the borrowed document, valid only for the duration of the call.
    /// - Returns: The value returned by `body`.
    /// - Throws: Any error `body` throws.
    public static func withParsedDocument<R>(
        _ source: borrowing String,
        options: MarkdownDocument.ParseOptions = [],
        _ body: (borrowing MarkdownDocument) throws -> R
    ) rethrows -> R {
        if #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) {
            let utf8 = source.utf8Span
            let document = MarkdownDocument(parsing: utf8, options: options)
            return try body(document)
        }
        // `makeContiguousUTF8` copies only a non-contiguous string.
        var contiguous = copy source
        contiguous.makeContiguousUTF8()
        if let result = try contiguous.utf8.withContiguousStorageIfAvailable({ (buffer: UnsafeBufferPointer<UInt8>) throws -> R in
            // SAFETY: `buffer` is valid for this closure, and the span over it backs a document that `body` borrows and can't escape, so no access outlives it.
            //         Before anyAppleOS 26 no API vends a `Span` over a `String`'s UTF-8 (`String.UTF8View.span` and `String.utf8Span` are anyAppleOS 26). The safe spans available there, such as `ContiguousArray.span`, cover only storage the caller owns, so they require copying the whole source, which defeats parsing the source in place.
            let document = MarkdownDocument(parsing: unsafe Span(_unsafeElements: buffer), options: options)
            return try body(document)
        }) {
            return result
        }
        // Empty input has no contiguous storage; parse an empty document.
        let document = MarkdownDocument(parsing: Span(), options: options)
        return try body(document)
    }

    /// The root node of the document's syntax tree, whose kind is always `.document`.
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
            // SAFETY: The source came from a validated `String` or `UTF8Span`, so it meets `UTF8Span(unchecked:)`'s precondition of valid UTF-8.
            //         A stored property can't have a type newer than the deployment target, so the document can't keep the validated `UTF8Span`, and `UTF8Span(validating:)` would make this O(1) accessor O(n).
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

extension MarkdownDocument {
    /// Creates a document by parsing a string as Markdown.
    ///
    /// The document borrows the string's UTF-8 bytes instead of copying them, so its lifetime is tied to `source`. To parse on an OS release that doesn't provide `UTF8Span`, use `withParsedDocument(_:options:_:)` instead.
    ///
    /// - Parameters:
    ///   - source: The Markdown text to parse.
    ///   - options: The options that control parsing.
    @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    @_lifetime(borrow source)
    public init(parsing source: borrowing String, options: MarkdownDocument.ParseOptions = []) {
        self.init(parsing: source.utf8Span, options: options)
    }
}
