/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

internal import BasicContainers

/// The emphasis `openersBottom` table: rows by `length % 3`, columns by delimiter character (`*_~'"`).
///
/// It wraps `SIMD16` because a nested `InlineArray` requires the anyAppleOS 26 runtime.
internal struct OpenersBottom {
    private var storage: SIMD16<Int>

    internal init(fill: Int) {
        storage = SIMD16(repeating: fill)
    }

    internal subscript(_ row: Int, _ col: Int) -> Int {
        get { storage[row * 5 + col] }
        set { storage[row * 5 + col] = newValue }
    }
}

/// Per kind, the starts from which a raw-HTML closer scan fails in the current `parseInline` pass. A scan
/// that fails from `p` reached the content end, ruling out every start at or after `p`, so an unclosed opener
/// doesn't rescan to the end.
internal struct HTMLCloserMisses {
    var comment: Range<Int> = 0..<0
    var cdata: Range<Int> = 0..<0
    var declaration: Range<Int> = 0..<0
    var processingInstruction: Range<Int> = 0..<0
}

/// The backtick runs that a closer scan passed on its way to the content end in one `parseInline` pass.
///
/// A scan from a run's end splits the content into the same runs as any other, so once a scan has reached the end from
/// `scannedToEndFrom`, an opener ending at or past it has a closer exactly when a run of its length starts at or past its
/// end. At most one scan per pass reaches the end.
internal struct BacktickRunsSeen {
    /// The earliest offset from which a scan has run to the content end without finding a closer, if any has.
    var scannedToEndFrom: Int?
    /// The latest start of a run of each length at or past `scannedToEndFrom`.
    var latestStart: [Int: Int] = [:]

    /// Whether no run of `length` backticks starts at or past `openEnd`, the end of an opening run of that length.
    func rulesOutCloser(length: Int, after openEnd: Int) -> Bool {
        guard let scannedToEndFrom, scannedToEndFrom <= openEnd else {
            return false
        }
        return latestStart[length, default: -1] < openEnd
    }

    mutating func recordRun(length: Int, start: Int) {
        latestStart[length] = max(latestStart[length, default: -1], start)
    }
}

/// Inline-level Markdown parsing functions.
extension BlockParser {

    /// Parses `content` into inline children of `parent`.
    mutating func parseInline(
        content: borrowing ContentSpan,
        into parent: DocumentStorage.Index,
        preserveWhitespace: Bool = false
    ) {
        if content.isEmpty {
            return
        }
        // The delimiter and bracket stacks are reused across blocks rather than allocated per call.
        delimiters.removeSubrange(0..<delimiters.count)
        brackets.removeSubrange(0..<brackets.count)
        
        var cursor = content.startOffset
        let endOffset = content.endOffset
        var pendingTextStart = cursor
        lastDelim = nil
        lastBracket = nil

        let strikethroughEnabled = storage.options.contains(.strikethrough)
        let gfmAutolinkEnabled = storage.options.contains(.gfmAutolink)
        let smartEnabled = storage.options.contains(.smart)

        htmlCloserMisses = HTMLCloserMisses()
        // Runs are recorded only once a scan has reached the content end.
        if backtickRunsSeen.scannedToEndFrom != nil {
            backtickRunsSeen = BacktickRunsSeen()
        }
        characterReferenceSources.removeAll(keepingCapacity: true)

        while cursor < endOffset {
            let byte = content[cursor]
            switch byte {
            case UInt8(ascii: "`"):
                cursor = handleBackticks(at: cursor, content: content, parent: parent, pendingTextStart: &pendingTextStart)

            case UInt8(ascii: "\n"):
                cursor = handleLineEnding(at: cursor, preserveWhitespace: preserveWhitespace, content: content, parent: parent, pendingTextStart: &pendingTextStart)

            case UInt8(ascii: "&"):
                cursor = handleCharacterReference(at: cursor, content: content, parent: parent, pendingTextStart: &pendingTextStart)

            case UInt8(ascii: "<"):
                cursor = handleAngleBracket(at: cursor, content: content, parent: parent, pendingTextStart: &pendingTextStart)

            case UInt8(ascii: "*"), UInt8(ascii: "_"):
                cursor = handleDelimRun(
                    char: byte,
                    start: cursor,
                    content: content,
                    parent: parent,
                    pendingTextStart: &pendingTextStart
                )

            case UInt8(ascii: "~"):
                if storage.options.contains(.strikethrough) {
                    cursor = handleDelimRun(
                        char: byte,
                        start: cursor,
                        content: content,
                        parent: parent,
                        pendingTextStart: &pendingTextStart
                    )
                } else {
                    cursor += 1
                }
                
            case UInt8(ascii: "["):
                cursor = openBracket(
                    .link,
                    length: 1,
                    at: cursor,
                    to: parent,
                    pendingTextStart: &pendingTextStart,
                    content: content
                )

            case UInt8(ascii: "!"):
                cursor = handleExclamationMark(at: cursor, content: content, parent: parent, pendingTextStart: &pendingTextStart)

            case UInt8(ascii: "^"):
                cursor = handleCaret(at: cursor, content: content, parent: parent, pendingTextStart: &pendingTextStart)

            case UInt8(ascii: "]"):
                flushPendingText(
                    start: pendingTextStart,
                    end: cursor,
                    content: content,
                    into: parent
                )
                cursor = handleCloseBracket(
                    cursor: cursor,
                    content: content,
                    parent: parent
                )
                pendingTextStart = cursor

            case UInt8(ascii: "\\"):
                cursor = handleBackslash(at: cursor, content: content, parent: parent, pendingTextStart: &pendingTextStart)

            case UInt8(ascii: ":"), UInt8(ascii: "w"), UInt8(ascii: "W"):
                cursor = handleGFMAutolinkTrigger(byte, at: cursor, content: content, parent: parent, pendingTextStart: &pendingTextStart)

            case UInt8(ascii: "'"), UInt8(ascii: "\""):
                // `processEmphasis` resolves quote delimiters to curly quotes.
                if smartEnabled {
                    cursor = handleQuoteDelim(
                        char: byte,
                        start: cursor,
                        content: content,
                        parent: parent,
                        pendingTextStart: &pendingTextStart
                    )
                } else {
                    cursor += 1
                }

            case UInt8(ascii: "-"):
                if smartEnabled {
                    cursor = handleSmartHyphen(
                        start: cursor,
                        content: content,
                        parent: parent,
                        pendingTextStart: &pendingTextStart
                    )
                } else {
                    cursor += 1
                }

            case UInt8(ascii: "."):
                if smartEnabled {
                    cursor = handleEllipsis(at: cursor, content: content, parent: parent, pendingTextStart: &pendingTextStart)
                } else {
                    cursor += 1
                }

            default:
                // Skip plain text to the next significant byte; the skipped run stays pending.
                cursor = content.nextSignificant(
                    from: cursor,
                    strikethrough: strikethroughEnabled,
                    gfmAutolink: gfmAutolinkEnabled,
                    smart: smartEnabled
                )
            }
        }
        flushPendingText(
            start: pendingTextStart,
            end: endOffset,
            content: content,
            into: parent
        )
        processEmphasis(
            stackBottom: -1,
            content: content
        )
    }

    // Each `handle` step consumes the construct starting at `cursor` and returns where scanning resumes: past the construct, or past the one byte, which stays pending text.

    /// A code span (Code spans). An unmatched backtick run stays pending text whole.
    private mutating func handleBackticks(at cursor: Int, content: borrowing ContentSpan, parent: DocumentStorage.Index, pendingTextStart: inout Int) -> Int {
        if let span = matchCodeSpan(
            start: cursor,
            content: content
        ) {
            emitLiteral(
                .codeInline(backtickCount: span.backtickCount),
                normalizeCodeSpanContent(span.content),
                start: cursor,
                end: span.afterClose,
                to: parent,
                pendingTextStart: &pendingTextStart,
                content: content
            )
            return span.afterClose
        }
        return scanBacktickRun(
            start: cursor,
            content: content
        )
    }

    /// A soft or hard line break (Soft line breaks, Hard line breaks).
    private mutating func handleLineEnding(at cursor: Int, preserveWhitespace: Bool, content: borrowing ContentSpan, parent: DocumentStorage.Index, pendingTextStart: inout Int) -> Int {
        let info: LineBreakInfo
        if preserveWhitespace {
            // Preserving whitespace, a line ending is literal text unless a backslash before it forms a hard line break (Hard line breaks).
            guard cursor > pendingTextStart, content[cursor - 1] == UInt8(ascii: "\\") else {
                return cursor + 1
            }
            info = LineBreakInfo(isHard: true, textEnd: cursor - 1)
        } else {
            info = classifyLineBreak(
                at: cursor,
                pendingTextStart: pendingTextStart,
                content: content
            )
        }
        flushPendingText(
            start: pendingTextStart,
            end: info.textEnd,
            content: content,
            into: parent
        )
        let kind: MarkdownNode.Kind = info.isHard ? .lineBreak : .softBreak
        let breakIdx = storage.appendNode(NodeRecord(kind: kind, parent: parent))
        storage.appendChild(breakIdx, to: parent)
        pendingTextStart = cursor + 1
        return cursor + 1
    }

    /// An entity or numeric character reference (Entity and numeric character references).
    private mutating func handleCharacterReference(at cursor: Int, content: borrowing ContentSpan, parent: DocumentStorage.Index, pendingTextStart: inout Int) -> Int {
        // Entity matching reads one buffer, so it scans `&`'s segment; a line join ends any reference anyway.
        let contiguous = content.contiguousChunk(fromVirtual: cursor, limit: content.endOffset)
        precondition(contiguous != nil, "an `&` lies in a source segment: the only synthetic segment is the line join")
        let window = contiguous!
        // A separate expression keeps the borrowed `source` span scoped to the call.
        let entity: EntityParser.EntityMatch? = if window.inSource {
            EntityParser.matchEntity(start: window.offset, end: window.offset + window.length, source: sourceBytes)
        } else {
            EntityParser.matchEntity(start: window.offset, end: window.offset + window.length, source: storage.strings.span)
        }
        guard let entity else {
            return cursor + 1
        }
        let decoded = Self.appendUTF8Bytes(
            bytes: entity.bytes,
            count: entity.count,
            into: &storage.strings
        )
        let afterSemi = cursor + (entity.afterSemi - window.offset)
        let textIdx = emitLiteral(
            .text,
            decoded,
            start: cursor,
            end: afterSemi,
            to: parent,
            pendingTextStart: &pendingTextStart,
            content: content
        )
        if positionsEnabled {
            let source = storage.sourceRanges[textIdx]
            characterReferenceSources.append((decoded.range, Int(source.start)..<Int(source.end)))
        }
        return afterSemi
    }

    /// An autolink (Autolinks) or raw inline HTML (Raw HTML).
    private mutating func handleAngleBracket(at cursor: Int, content: borrowing ContentSpan, parent: DocumentStorage.Index, pendingTextStart: inout Int) -> Int {
        if let auto = matchAutolink(
            start: cursor,
            content: content
        ) {
            flushPendingText(
                start: pendingTextStart,
                end: cursor,
                content: content,
                into: parent
            )
            emitAutolink(
                auto: auto,
                into: parent,
                content: content
            )
            // Links may not contain other links (Links), and an autolink binds more tightly
            // than link text brackets, so the link openers before it cannot form links.
            markLinkOpenersInactive()
            pendingTextStart = auto.afterClose
            return auto.afterClose
        }
        if let htmlEnd = matchInlineHTML(
            start: cursor,
            content: content
        ) {
            // A tag spanning a line ending in multi-segment content is materialized; otherwise the literal is zero-copy.
            emitLiteral(
                .htmlInline,
                materializedChunk(start: cursor, end: htmlEnd, content: content),
                start: cursor,
                end: htmlEnd,
                to: parent,
                pendingTextStart: &pendingTextStart,
                content: content
            )
            return htmlEnd
        }
        return cursor + 1
    }

    /// An image opener `![`.
    private mutating func handleExclamationMark(at cursor: Int, content: borrowing ContentSpan, parent: DocumentStorage.Index, pendingTextStart: inout Int) -> Int {
        // `![^` opens no image: the `!` is literal text and the `[` opens a bracket, so `![^a]`
        // is `!` followed by a footnote reference, link or literal text.
        let endOffset = content.endOffset
        if cursor + 1 < endOffset,
           content[cursor + 1] == UInt8(ascii: "["),
           !(cursor + 2 < endOffset && content[cursor + 2] == UInt8(ascii: "^")) {
            return openBracket(
                .image,
                length: 2,
                at: cursor,
                to: parent,
                pendingTextStart: &pendingTextStart,
                content: content
            )
        }
        return cursor + 1
    }

    /// An inline attribute opener `^[`.
    private mutating func handleCaret(at cursor: Int, content: borrowing ContentSpan, parent: DocumentStorage.Index, pendingTextStart: inout Int) -> Int {
        // Without `.attributes`, `^` is ordinary text and a following `[` opens a link bracket.
        if storage.options.contains(.attributes),
           cursor + 1 < content.endOffset,
           content[cursor + 1] == UInt8(ascii: "[") {
            return openBracket(
                .attribute,
                length: 2,
                at: cursor,
                to: parent,
                pendingTextStart: &pendingTextStart,
                content: content
            )
        }
        return cursor + 1
    }

    /// A backslash escape (Backslash escapes). A backslash before a line ending is handled with the line ending; one before anything but ASCII punctuation is literal.
    private mutating func handleBackslash(at cursor: Int, content: borrowing ContentSpan, parent: DocumentStorage.Index, pendingTextStart: inout Int) -> Int {
        if cursor + 1 < content.endOffset {
            let next = content[cursor + 1]
            if next.isASCIIPunct {
                // The node's content is the escaped character, but its source range starts at the backslash.
                emitLiteral(
                    .text,
                    content.chunk(offset: cursor + 1, length: 1),
                    start: cursor,
                    end: cursor + 2,
                    to: parent,
                    pendingTextStart: &pendingTextStart,
                    content: content
                )
                return cursor + 2
            }
        }
        return cursor + 1
    }

    /// A `://` or `www.` extended autolink, triggered by `byte` (`:`, `w` or `W`).
    private mutating func handleGFMAutolinkTrigger(_ byte: UInt8, at cursor: Int, content: borrowing ContentSpan, parent: DocumentStorage.Index, pendingTextStart: inout Int) -> Int {
        // Extended email autolinks are found after emphasis resolution (`gfmEmailAutolinkPass`), so a `_`
        // or `*` beside an email resolves first. No `://` or `www.` autolink forms while a `[` or `![`
        // opener is open, so `[a http://t.t` is text; an `^[` opener does not suppress one.
        let insideLinkOrImageBracket = lastBracket.map { brackets[$0].insideLinkOrImage } ?? false
        if storage.options.contains(.gfmAutolink),
           !insideLinkOrImageBracket,
           let auto = matchGFMAutolink(
            trigger: byte,
            cursor: cursor,
            content: content
           ) {
            flushPendingText(
                start: pendingTextStart,
                end: auto.urlStart,
                content: content,
                into: parent
            )
            emitGFMAutolink(
                auto: auto,
                content: content,
                into: parent
            )
            pendingTextStart = auto.urlEnd
            return auto.urlEnd
        }
        return cursor + 1
    }

    /// A smart ellipsis, `...`.
    private mutating func handleEllipsis(at cursor: Int, content: borrowing ContentSpan, parent: DocumentStorage.Index, pendingTextStart: inout Int) -> Int {
        guard cursor + 2 < content.endOffset,
              content[cursor + 1] == UInt8(ascii: "."),
              content[cursor + 2] == UInt8(ascii: ".") else {
            return cursor + 1
        }
        // The ellipsis is arena-backed, but its source range is the three dots.
        emitLiteral(
            .text,
            smartConstantChunk(Self.ellipsis),
            start: cursor,
            end: cursor + 3,
            to: parent,
            pendingTextStart: &pendingTextStart,
            content: content
        )
        return cursor + 3
    }

    // MARK: - Links / images (bracket stack)

    internal enum BracketKind {
        case link
        case image
        case attribute

        var nodeKind: MarkdownNode.Kind {
            switch self {
            case .link: .link
            case .image: .image
            case .attribute: .attribute
            }
        }
    }

    /// An open `[`, `![` or `^[` on the bracket stack, a linked list through `previous` in `brackets`.
    internal struct BracketRecord {
        var kind: BracketKind
        var inlText: DocumentStorage.Index
        /// The opener's virtual offset, from which the wrapper's start is stamped. The opener text node's range is in source offsets, so stamping from it would map twice.
        var virtualStart: Int
        /// The delimiter stack top at push: the `stackBottom` for resolving emphasis inside the link text.
        var delimPosition: Int
        /// Whether a bracket was pushed after this one. Its text then holds an unescaped bracket, which no link label does, so it skips the shortcut lookup.
        var bracketAfter: Bool = false
        /// Whether this bracket or one enclosing it is a link or image opener, which suppresses `://` and `www.` extended autolinks.
        var insideLinkOrImage: Bool
        /// Whether a link or autolink formed after this opener, which then can't form a link: links may not contain
        /// other links (Links).
        var linkFormedAfter: Bool = false
        var previous: Int?
    }

    /// Marks every open link opener as unable to form a link, because a link or autolink formed after it.
    private mutating func markLinkOpenersInactive() {
        var idx = lastBracket
        while let i = idx {
            if brackets[i].kind == .link {
                brackets[i].linkFormedAfter = true
            }
            idx = brackets[i].previous
        }
    }

    /// Pushes a `kind` opener, the `length` bytes at `cursor`, and returns the offset past it. An unresolved opener stays literal text with its own source range.
    private mutating func openBracket(_ kind: BracketKind, length: Int, at cursor: Int, to parent: DocumentStorage.Index, pendingTextStart: inout Int, content: borrowing ContentSpan) -> Int {
        let textIdx = emitLiteral(.text, content.chunk(offset: cursor, length: length), start: cursor, end: cursor + length, to: parent, pendingTextStart: &pendingTextStart, content: content)
        pushBracket(kind: kind, inlText: textIdx, virtualStart: cursor, delimPosition: lastDelim ?? -1)
        return cursor + length
    }

    private mutating func pushBracket(kind: BracketKind, inlText: DocumentStorage.Index, virtualStart: Int, delimPosition: Int) {
        if let lastBracket {
            brackets[lastBracket].bracketAfter = true
        }
        let prev = lastBracket
        let newIdx = brackets.count
        let insideLinkOrImage = (prev.map { brackets[$0].insideLinkOrImage } ?? false)
            || kind == .link || kind == .image
        brackets.append(BracketRecord(
            kind: kind,
            inlText: inlText,
            virtualStart: virtualStart,
            delimPosition: delimPosition,
            insideLinkOrImage: insideLinkOrImage,
            previous: prev
        ))
        lastBracket = newIdx
    }

    private mutating func popBracket() {
        if let last = lastBracket {
            lastBracket = brackets[last].previous
        }
    }
    
    /// Handles a `]`: the innermost opener becomes a link, image or attribute when that form follows, or a footnote reference when `[^label]` names a definition. Otherwise the `]` is literal; after an `^[` opener its text also spans the label that follows it.
    private mutating func handleCloseBracket(cursor: Int, content: borrowing ContentSpan, parent: DocumentStorage.Index) -> Int {
        let afterBracket = cursor + 1
        guard let openerIdx = lastBracket else {
            emitBracketLiteral(at: cursor, end: afterBracket, content: content, parent: parent)
            return afterBracket
        }
        let openerKind = brackets[openerIdx].kind
        let openerInl = brackets[openerIdx].inlText
        let openerDelimPos = brackets[openerIdx].delimPosition
        let openerStart = brackets[openerIdx].virtualStart
        // A link opener cannot form a link inside another link, or after a link formed at its level.
        if openerKind == .link, brackets[openerIdx].linkFormedAfter {
            popBracket()
            emitBracketLiteral(at: cursor, end: afterBracket, content: content, parent: parent)
            return afterBracket
        }
        let formed: (data: NodeData, end: Int)?
        let literalEnd: Int
        if openerKind == .attribute {
            let attribute = matchAttributeForm(cursor: cursor, content: content)
            formed = attribute.data.map { ($0, attribute.end) }
            literalEnd = attribute.end
        } else {
            formed = matchLinkForm(shortcutLabelStart: brackets[openerIdx].bracketAfter ? nil : openerStart + (openerKind == .image ? 2 : 1), cursor: cursor, content: content)
            literalEnd = afterBracket
        }
        if let formed {
            wrapBracketContent(openerKind.nodeKind, formed.data, openerInl: openerInl, delimPosition: openerDelimPos, start: openerStart, end: formed.end, content: content)
            popBracket()
            if openerKind == .link {
                markLinkOpenersInactive()
            }
            return formed.end
        }
        // Failing a link form, a `[^label]` naming a footnote definition is a footnote reference. The
        // footnote map is complete before inline parsing.
        let footnoteBracketStart = openerStart + (openerKind == .image ? 1 : 0)
        if openerKind != .attribute,
           storage.options.contains(.footnotes),
           let defIdx = footnoteDefinition(referencedFrom: footnoteBracketStart, closeBracket: cursor, in: content) {
            // Resolve emphasis inside the bracket first, so removing its nodes leaves no stale delimiters.
            processEmphasis(stackBottom: openerDelimPos, content: content)
            emitFootnoteReference(openerInl: openerInl, definition: defIdx, span: footnoteBracketStart..<afterBracket, content: content)
            popBracket()
            return afterBracket
        }
        popBracket()
        emitBracketLiteral(at: cursor, end: literalEnd, content: content, parent: parent)
        return literalEnd
    }

    /// The link or image data for the form after the `]` at `cursor`, and the offset past it. Tries the inline form, then full, collapsed and shortcut references.
    ///
    /// `shortcutLabelStart` is where the shortcut label begins, or `nil` when a bracket nested under the opener rules it out.
    @inline(__always)
    private mutating func matchLinkForm(shortcutLabelStart: Int?, cursor: Int, content: borrowing ContentSpan) -> (data: NodeData, end: Int)? {
        let end = content.endOffset
        let pos = cursor + 1
        if pos < end, content[pos] == UInt8(ascii: "("),
           let inline = matchInlineLinkTail(afterParen: pos + 1, content: content) {
            return (.link(url: storage.intern(inline.url), title: storage.intern(inline.title)), inline.end)
        }
        // A reference matches only a link reference definition, so without one no label is normalized.
        if storage.referenceMap.isEmpty {
            return nil
        }
        var key = ""
        var afterReference = pos
        if let label = matchLabelKey(from: pos, content: content) {
            key = label.key
            // A whitespace-only `[ ]` is neither a link label nor `[]` (Links), so after a shortcut
            // reference it stays text.
            if !key.isEmpty || label.afterEnd == pos + 2 {
                afterReference = label.afterEnd
            }
        }
        // A collapsed or blank label, or none, falls back to the shortcut form, whose label is the bracket text.
        if key.isEmpty, let textStart = shortcutLabelStart {
            // A link label has at most 999 characters inside its brackets (Links), so a longer shortcut stays literal.
            if cursor > textStart, linkLabelFitsLengthCap(virtualRange: textStart..<cursor, in: content) {
                key = normalizeLabel(virtualRange: textStart..<cursor, in: content)
            }
        }
        guard !key.isEmpty, let definition = storage.referenceMap[key] else {
            return nil
        }
        return (.link(url: storage.intern(definition.destination), title: storage.intern(definition.title)), afterReference)
    }

    /// Matches an inline link's `destination "title")` after its `(`, returning the cleaned destination and title and the offset past the `)`.
    ///
    /// Either may span a line ending, so both are materialized, zero-copy within one segment.
    @inline(__always)
    private mutating func matchInlineLinkTail(afterParen: Int, content: borrowing ContentSpan) -> (url: Chunk, title: Chunk, end: Int)? {
        let end = content.endOffset
        let destStart = skipSpaceChars(start: afterParen, content: content)
        guard let dest = matchLinkDestination(from: destStart, end: end, in: content) else {
            return nil
        }
        let titleStart = skipSpaceChars(start: dest.afterEnd, content: content)
        var titleEnd = dest.afterEnd
        var titleInterior = dest.afterEnd..<dest.afterEnd
        if titleStart > dest.afterEnd,
           let title = matchLinkTitle(from: titleStart, end: end, in: content) {
            titleInterior = title.interior
            titleEnd = title.afterEnd
        }
        let close = skipSpaceChars(start: titleEnd, content: content)
        guard close < end, content[close] == UInt8(ascii: ")") else {
            return nil
        }
        return (
            cleanURLChunk(materializedChunk(start: dest.destination.lowerBound, end: dest.destination.upperBound, content: content)),
            unescapeURLChunk(materializedChunk(start: titleInterior.lowerBound, end: titleInterior.upperBound, content: content)),
            close + 1
        )
    }

    /// The normalized key of the label at `pos`, empty for a blank one, and the offset past its `]`.
    ///
    /// `mutating` so that calling its non-mutating callees does not copy `self`, which costs more than the call.
    private mutating func matchLabelKey(from pos: Int, content: borrowing ContentSpan) -> (key: String, afterEnd: Int)? {
        let end = content.endOffset
        guard let label = matchLinkLabel(from: pos, end: end, in: content) else {
            return nil
        }
        // A collapsed `[]` has no label to normalize.
        return (label.interior.isEmpty ? "" : normalizeLabel(virtualRange: label.interior, in: content), label.afterEnd)
    }

    /// Appends a text node holding the `]` at `cursor`, spanning `cursor..<end`.
    private mutating func emitBracketLiteral(at cursor: Int, end: Int, content: borrowing ContentSpan, parent: DocumentStorage.Index) {
        appendInline(.text, .literal(storage.intern(content.chunk(offset: cursor, length: 1))), to: parent, start: cursor, end: end, content: content)
    }

    /// Wrap the nodes after the opener's text in a new `kind` node spanning the virtual range `start..<end`, remove the opener's text, and resolve emphasis inside the new node with the opener's delimiter position as the floor.
    @inline(__always)
    private mutating func wrapBracketContent(_ kind: MarkdownNode.Kind, _ data: NodeData, openerInl: DocumentStorage.Index, delimPosition: Int, start: Int, end: Int, content: borrowing ContentSpan) {
        let wrapper = storage.appendNode(NodeRecord(kind: kind, parent: storage[openerInl].parent, data: data))
        stampInline(wrapper, start, end, content: content)
        storage.insertChildBefore(wrapper, before: openerInl)
        var sibling = storage[openerInl].next
        while let current = sibling {
            sibling = storage[current].next
            storage.unlinkChild(current)
            storage.appendChild(current, to: wrapper)
        }
        storage.unlinkChild(openerInl)
        processEmphasis(stackBottom: delimPosition, content: content)
    }

    // MARK: - Footnote references

    /// The definition the footnote-shaped bracket from `open` to `closeBracket` references, or `nil`. Its label,
    /// everything after the `^`, is normalized as a link label (Links), so it may span a line ending.
    private func footnoteDefinition(referencedFrom open: Int, closeBracket: Int, in content: borrowing ContentSpan) -> DocumentStorage.Index? {
        let labelStart = open + 2
        guard !storage.footnoteMap.isEmpty, labelStart < closeBracket, content[open + 1] == UInt8(ascii: "^"),
              linkLabelFitsLengthCap(virtualRange: labelStart..<closeBracket, in: content) else {
            return nil
        }
        return storage.footnoteMap[normalizeLabel(virtualRange: labelStart..<closeBracket, in: content)]
    }

    /// Replaces the opener's text and the bracket's inner nodes with a `.footnoteReference` to `definition` over `span`.
    ///
    /// The reference carries the definition's label, so `[^Foo]` resolving to `[^foo]` displays `foo`. Its index is 0
    /// until the footnote pass numbers the finalized tree, because an enclosing bracket can still discard it.
    private mutating func emitFootnoteReference(openerInl: DocumentStorage.Index, definition defIdx: DocumentStorage.Index, span: Range<Int>, content: borrowing ContentSpan) {
        guard case .footnoteDefinition(let defLabel) = storage[defIdx].data else {
            preconditionFailure("footnoteMap holds only footnote definitions")
        }
        let parentIdx = storage[openerInl].parent
        let fnRefIdx = storage.appendNode(NodeRecord(
            kind: .footnoteReference(index: 0),
            parent: parentIdx,
            data: .footnoteReference(label: defLabel)
        ))
        storage.insertChildBefore(fnRefIdx, before: openerInl)
        stampInline(fnRefIdx, span.lowerBound, span.upperBound, content: content)
        storage.unlinkChild(openerInl)
        // The inner `^label` nodes go; a reference is rendered from its label and index.
        var sib = storage[fnRefIdx].next
        while let sib_ = sib {
            let nextSib = storage[sib_].next
            storage.unlinkChild(sib_)
            sib = nextSib
        }
    }

    // MARK: - Extended attributes (`^[..]`)

    /// The attribute data for the form after the `]` closing an `^[` opener, and the offset past it: an inline `(attrs)`, or a `[label]`.
    ///
    /// A link label, or a collapsed or blank one, belongs to the form whether or not it names an attribute definition; the data is `nil` when it names none, or when no form follows.
    private mutating func matchAttributeForm(cursor: Int, content: borrowing ContentSpan) -> (data: NodeData?, end: Int) {
        let end = content.endOffset
        let pos = cursor + 1
        if pos < end, content[pos] == UInt8(ascii: "("),
           let scanned = matchAttributeAttributes(start: pos + 1, content: content),
           scanned.afterEnd < end,
           content[scanned.afterEnd] == UInt8(ascii: ")") {
            return (.attribute(storage.intern(scanned.chunk)), scanned.afterEnd + 1)
        }
        // Without an attribute definition the label names none, but still belongs to the form.
        if storage.attributeReferenceMap.isEmpty {
            return (nil, matchLinkLabel(from: pos, end: end, in: content)?.afterEnd ?? pos)
        }
        guard let label = matchLabelKey(from: pos, content: content) else {
            return (nil, pos)
        }
        guard !label.key.isEmpty, let attributes = storage.attributeReferenceMap[label.key] else {
            return (nil, label.afterEnd)
        }
        return (.attribute(storage.intern(attributes)), label.afterEnd)
    }

    private struct AttributeAttributesMatch {
        var chunk: Chunk
        var afterEnd: Int
    }

    /// Scans an attribute form's `(…)` interior, which may hold whitespace, parentheses balanced to depth 32, and backslash escapes.
    private mutating func matchAttributeAttributes(start: Int, content: borrowing ContentSpan) -> AttributeAttributesMatch? {
        let end = content.endOffset
        var i = start
        var nbParen = 0
        while i < end {
            let c = content[i]
            if c == UInt8(ascii: "\\") && i + 1 < end {
                let next = content[i + 1]
                if next.isASCIIPunct {
                    i += 2
                    continue
                }
                i += 1
                continue
            }
            if c == UInt8(ascii: "(") {
                nbParen += 1
                if nbParen > 32 {
                    return nil
                }
                i += 1
                continue
            }
            if c == UInt8(ascii: ")") {
                if nbParen == 0 {
                    return AttributeAttributesMatch(chunk: materializedChunk(start: start, end: i, content: content), afterEnd: i)
                }
                nbParen -= 1
                i += 1
                continue
            }
            i += 1
        }
        return nil
    }

    // MARK: - Emphasis / strong (delimiter stack)

    /// A delimiter run on the emphasis stack (Appendix: A parsing strategy), pointing at the `.text` node holding it.
    ///
    /// The stack is a doubly-linked list through `delimiters`; unlinking a record leaves the array, and so other indices, intact.
    internal struct DelimiterRecord {
        var character: UInt8
        var length: Int
        var canOpen: Bool
        var canClose: Bool
        var inlText: DocumentStorage.Index
        /// The virtual range of the run's unused delimiters, from which `insertEmph` stamps the emphasis node. The run's text node is in source offsets, so stamping from it would map twice.
        ///
        /// A closer uses delimiters from its start and an opener from its end, so the unused ones stay contiguous.
        var virtualStart: Int
        var virtualEnd: Int
        var previous: Int?
        var next: Int?
    }

    /// The flanking classification of a delimiter run.
    private struct Flanking {
        var leftFlanking: Bool
        var rightFlanking: Bool
        /// The byte before the run, past any skipped `~` run, for the quote `]`/`)` rule.
        var beforeChar: UInt8
        /// Whether the bordering characters are punctuation, for the `_` intraword rule.
        var beforeIsPunct: Bool
        var afterIsPunct: Bool
    }

    /// Classifies a delimiter run as left- or right-flanking (Emphasis and strong emphasis).
    ///
    /// With strikethrough on, a `*`, `_` or quote run reads its neighbours past any adjacent `~` run, so the
    /// closing `*` in `*-*~a` borders `a` and closes no emphasis.
    private func classifyFlanking(char: UInt8, start: Int, runEnd: Int, content: borrowing ContentSpan) -> Flanking {
        let end = content.endOffset
        let chunkStart = content.startOffset
        let tilde = UInt8(ascii: "~")
        let skipTilde = char != tilde && storage.options.contains(.strikethrough)
        // The content's start and end count as line endings.
        var beforeIdx = start - 1
        if skipTilde {
            while beforeIdx >= chunkStart, content[beforeIdx] == tilde { beforeIdx -= 1 }
        }
        let beforeChar: UInt8 = beforeIdx >= chunkStart ? content[beforeIdx] : UInt8(ascii: "\n")
        var afterIdx = runEnd
        if skipTilde {
            while afterIdx < end, content[afterIdx] == tilde { afterIdx += 1 }
        }
        // Flanking is defined over characters, so a multi-byte whitespace or punctuation neighbour counts.
        let beforeScalar: Int32 = beforeIdx >= chunkStart
            ? Self.flankingScalarBefore(endingAt: beforeIdx, lowerBound: chunkStart, content: content)
            : 0x0A
        let afterScalar: Int32 = afterIdx < end
            ? Self.flankingScalarAfter(startingAt: afterIdx, content: content)
            : 0x0A
        let beforeIsSpace = Self.isUnicodeWhitespace(beforeScalar)
        let beforeIsPunct = Self.isUnicodePunctuation(beforeScalar)
        let afterIsSpace = Self.isUnicodeWhitespace(afterScalar)
        let afterIsPunct = Self.isUnicodePunctuation(afterScalar)
        let leftFlanking = !afterIsSpace && (!afterIsPunct || beforeIsSpace || beforeIsPunct)
        let rightFlanking = !beforeIsSpace && (!beforeIsPunct || afterIsSpace || afterIsPunct)
        return Flanking(
            leftFlanking: leftFlanking,
            rightFlanking: rightFlanking,
            beforeChar: beforeChar,
            beforeIsPunct: beforeIsPunct,
            afterIsPunct: afterIsPunct
        )
    }

    /// The scalar whose last byte is at `endIdx`, decoded from its lead byte at or after `lowerBound`.
    @inline(__always)
    private static func flankingScalarBefore(endingAt endIdx: Int, lowerBound: Int, content: borrowing ContentSpan) -> Int32 {
        let last = content[endIdx]
        if last < 0x80 { return Int32(last) }
        var lead = endIdx
        while lead > lowerBound, content[lead] & 0xC0 == 0x80 { lead -= 1 }
        return decodeUTF8Scalar(at: lead, content: content)
    }

    @inline(__always)
    private static func flankingScalarAfter(startingAt idx: Int, content: borrowing ContentSpan) -> Int32 {
        let first = content[idx]
        if first < 0x80 { return Int32(first) }
        return decodeUTF8Scalar(at: idx, content: content)
    }

    /// Decodes the multi-byte scalar whose lead byte is at `idx`. Inline content is valid UTF-8 cut only at
    /// ASCII bytes, so the whole sequence lies inside the content.
    private static func decodeUTF8Scalar(at idx: Int, content: borrowing ContentSpan) -> Int32 {
        let b0 = content[idx]
        precondition(b0 >= 0xC2 && b0 <= 0xF4, "inline content is valid UTF-8, so a decoded scalar starts at a multi-byte lead byte")
        if b0 < 0xE0 {
            return (Int32(b0 & 0x1F) << 6) | Int32(content[idx + 1] & 0x3F)
        }
        if b0 < 0xF0 {
            return (Int32(b0 & 0x0F) << 12) | (Int32(content[idx + 1] & 0x3F) << 6) | Int32(content[idx + 2] & 0x3F)
        }
        return (Int32(b0 & 0x07) << 18) | (Int32(content[idx + 1] & 0x3F) << 12) | (Int32(content[idx + 2] & 0x3F) << 6) | Int32(content[idx + 3] & 0x3F)
    }

    /// Whether `uc` is a Unicode whitespace character (Characters and lines).
    @inline(__always)
    private static func isUnicodeWhitespace(_ uc: Int32) -> Bool {
        if uc < 0x80 { return UInt8(uc).isFlankingSpace }
        switch uc {
        case 160, 5760, 8192...8202, 8239, 8287, 12288:
            return true
        default:
            return false
        }
    }

    /// Whether `uc` is a punctuation character (Characters and lines).
    @inline(__always)
    private static func isUnicodePunctuation(_ uc: Int32) -> Bool {
        if uc < 0x80 { return UInt8(uc).isASCIIPunct }
        switch uc {
        case 161, 167, 171, 182, 183, 187, 191, 894, 903,
            1370...1375, 1417, 1418, 1470, 1472, 1475, 1478, 1523, 1524,
            1545, 1546, 1548, 1549, 1563, 1566, 1567, 1642...1645, 1748,
            1792...1805, 2039...2041, 2096...2110, 2142, 2404, 2405, 2416,
            2800, 3572, 3663, 3674, 3675, 3844...3858, 3860, 3898...3901,
            3973, 4048...4052, 4057, 4058, 4170...4175, 4347, 4960...4968,
            5120, 5741, 5742, 5787, 5788, 5867...5869, 5941, 5942,
            6100...6102, 6104...6106, 6144...6154, 6468, 6469, 6686, 6687,
            6816...6822, 6824...6829, 7002...7008, 7164...7167, 7227...7231,
            7294, 7295, 7360...7367, 7379, 8208...8231, 8240...8259,
            8261...8273, 8275...8286, 8317, 8318, 8333, 8334, 8968...8971,
            9001, 9002, 10088...10101, 10181, 10182, 10214...10223,
            10627...10648, 10712...10715, 10748, 10749, 11513...11516,
            11518, 11519, 11632, 11776...11822, 11824...11842, 12289...12291,
            12296...12305, 12308...12319, 12336, 12349, 12448, 12539,
            42238, 42239, 42509...42511, 42611, 42622, 42738...42743,
            43124...43127, 43214, 43215, 43256...43258, 43310, 43311,
            43359, 43457...43469, 43486, 43487, 43612...43615, 43742, 43743,
            43760, 43761, 44011, 64830, 64831, 65040...65049, 65072...65106,
            65108...65121, 65123, 65128, 65130, 65131, 65281...65283,
            65285...65290, 65292...65295, 65306, 65307, 65311, 65312,
            65339...65341, 65343, 65371, 65373, 65375...65381, 65792...65794,
            66463, 66512, 66927, 67671, 67871, 67903, 68176...68184, 68223,
            68336...68342, 68409...68415, 68505...68508, 69703...69709,
            69819, 69820, 69822...69825, 69952...69955, 70004, 70005,
            70085...70088, 70093, 70200...70205, 70854, 71105...71113,
            71233...71235, 74864...74868, 92782, 92783, 92917, 92983...92987,
            92996, 113823:
            return true
        default:
            return false
        }
    }

    /// Scans the delimiter run at `start`, emits its text, and pushes a delimiter if it can open or close (Emphasis and strong emphasis). Returns the offset past the run.
    private mutating func handleDelimRun(char: UInt8, start: Int, content: borrowing ContentSpan, parent: DocumentStorage.Index, pendingTextStart: inout Int) -> Int {
        let end = content.endOffset
        var runEnd = start
        while runEnd < end, content[runEnd] == char {
            runEnd += 1
        }

        let count = runEnd - start
        let flanking = classifyFlanking(char: char, start: start, runEnd: runEnd, content: content)
        let leftFlanking = flanking.leftFlanking
        let rightFlanking = flanking.rightFlanking
        let beforeIsPunct = flanking.beforeIsPunct
        let afterIsPunct = flanking.afterIsPunct
        
        let canOpen: Bool
        let canClose: Bool
        if char == UInt8(ascii: "_") {
            // Rules 2, 4, 6 and 8 (Emphasis and strong emphasis).
            canOpen = leftFlanking && (!rightFlanking || beforeIsPunct)
            canClose = rightFlanking && (!leftFlanking || afterIsPunct)
        } else {
            canOpen = leftFlanking
            canClose = rightFlanking
        }
        // A run that can neither open nor close stays pending text, so the email autolink pass sees an
        // unbroken local part (`a.b-c_d@a.b`). A non-flanking `~` run is surrounded by whitespace, so its
        // own text node never splits an autolink.
        let isStrikethrough = char == UInt8(ascii: "~")
        if !canOpen && !canClose && !isStrikethrough {
            return runEnd
        }
        // An unpaired delimiter stays literal text with its own source range.
        let textIdx = emitLiteral(.text, content.chunk(offset: start, length: count), start: start, end: runEnd, to: parent, pendingTextStart: &pendingTextStart, content: content)
        if canOpen || canClose {
            // Strikethrough (extension) uses two tildes, or one unless `.strikethroughDoubleTilde` is set.
            // Other `~` runs stay literal.
            let pushDelim: Bool
            if isStrikethrough {
                let doubleTilde = storage.options.contains(.strikethroughDoubleTilde)
                pushDelim = count == 2 || (!doubleTilde && count == 1)
            } else {
                pushDelim = true
            }
            if pushDelim {
                pushDelimiter(char, length: count, canOpen: canOpen, canClose: canClose, inlText: textIdx, range: start..<runEnd)
            }
        }
        return runEnd
    }

    /// Resolves emphasis among the delimiters above `stackBottom` (`-1` for the whole stack), pairing each closer with the nearest compatible opener.
    ///
    /// `openersBottom` records, per closer length mod 3 and character, where a failed opener search stopped, so no later closer searches below it.
    private mutating func processEmphasis(stackBottom: Int, content: borrowing ContentSpan) {
        // openersBottom[length % 3, char-index]: 0=`*`, 1=`_`, 2=`~`, 3=`'`, 4=`"`.
        var openersBottom = OpenersBottom(fill: stackBottom)
        // The earliest delimiter above `stackBottom`.
        var closer: Int? = nil
        var walker = lastDelim
        while let w = walker, w > stackBottom {
            closer = w
            walker = delimiters[w].previous
        }
        while let c = closer {
            if !delimiters[c].canClose {
                closer = delimiters[c].next
                continue
            }
            let closerChar = delimiters[c].character
            let charIdx = charIndex(for: closerChar)
            let lenMod = delimiters[c].length % 3
            var opener = delimiters[c].previous
            var openerFound = false
            while let o = opener, o > stackBottom,
                  o >= openersBottom[lenMod, charIdx] {
                if delimiters[o].canOpen
                    && delimiters[o].character == closerChar {
                    let cl = delimiters[c]
                    let op = delimiters[o]
                    // The multiple-of-3 test of rules 9 and 10 (Emphasis and strong emphasis) applies to `~`
                    // too. A `~` opener of any length is accepted: `insertEmph` discards a mismatched pair,
                    // so a closer never reaches past the nearest `~` opener.
                    if !(cl.canOpen || op.canClose)
                        || cl.length % 3 == 0
                        || (op.length + cl.length) % 3 != 0 {
                        openerFound = true
                        break
                    }
                }
                opener = delimiters[o].previous
            }
            let oldCloser = c
            if closerChar == UInt8(ascii: "'") || closerChar == UInt8(ascii: "\"") {
                // A quote closer already has its closing glyph from `handleQuoteDelim`. Re-interning it would move its segment to the pool's end, so `consolidateTextNodes` could not merge it with its neighbours (the apostrophe in `it's`).
                let single = closerChar == UInt8(ascii: "'")
                let next = delimiters[c].next
                if openerFound, let opener {
                    setSmartLiteral(
                        of: delimiters[opener].inlText,
                        single ? Self.leftSingleQuote : Self.leftDoubleQuote
                    )
                    removeDelim(opener)
                    removeDelim(oldCloser)
                }
                closer = next
            } else if openerFound, let opener {
                closer = insertEmph(
                    opener: opener,
                    closer: c,
                    content: content
                )
            } else {
                closer = delimiters[c].next
            }
            if !openerFound {
                openersBottom[delimiters[oldCloser].length % 3, charIdx] = oldCloser
                if !delimiters[oldCloser].canOpen {
                    removeDelim(oldCloser)
                }
            }
        }
        // Free remaining delimiters above stackBottom.
        while let last = lastDelim, last > stackBottom {
            removeDelim(last)
        }
    }

    private func charIndex(for c: UInt8) -> Int {
        switch c {
        case UInt8(ascii: "_"): return 1
        case UInt8(ascii: "~"): return 2
        case UInt8(ascii: "'"): return 3
        case UInt8(ascii: "\""): return 4
        default: return 0
        }
    }

    /// Wraps the nodes between `opener` and `closer` in an `.emphasis`, `.strong` or `.strikethrough` node, trims the used delimiters, and returns the next closer to process: `closer` again if part of its run remains.
    private mutating func insertEmph(opener: Int, closer: Int, content: borrowing ContentSpan) -> Int? {
        let openerInl = delimiters[opener].inlText
        let closerInl = delimiters[closer].inlText
        let openerChar = delimiters[opener].character
        var openerNumChars = literalLength(of: openerInl)
        var closerNumChars = literalLength(of: closerInl)
        let useDelims: Int
        let kind: MarkdownNode.Kind
        if openerChar == UInt8(ascii: "~") {
            // Strikethrough forms only between runs of equal length. On a mismatch both stay literal, and
            // every delimiter from the closer back through the opener goes, so no farther opener pairs with it.
            if openerNumChars != closerNumChars {
                let next = delimiters[closer].next
                removeDelims(after: opener, through: closer)
                removeDelim(opener)
                return next
            }
            useDelims = openerNumChars
            kind = .strikethrough
        } else {
            useDelims = (closerNumChars >= 2 && openerNumChars >= 2) ? 2 : 1
            kind = useDelims == 1 ? .emphasis : .strong
        }
        openerNumChars -= useDelims
        closerNumChars -= useDelims
        // A record's `length` stays the original run length, which rules 9 and 10 sum and `openersBottom`
        // is indexed by: a closer reduced from 4 to 2 keeps its slot, or `****a**o****` would not nest as
        // Strong>Strong. The count still available is the text literal's length.
        storage.trimLiteral(of: openerInl, trimStart: 0, newLength: openerNumChars)
        storage.trimLiteral(of: closerInl, trimStart: useDelims, newLength: closerNumChars)
        // Intervening delimiters go; their text nodes become children of the new node.
        if let previous = delimiters[closer].previous, previous != opener {
            removeDelims(after: opener, through: previous)
        }
        let parentIdx = storage[openerInl].parent
        let emphIdx = storage.appendNode(NodeRecord(kind: kind, parent: parentIdx))
        // The node covers the used delimiters and the content, not the leftover delimiters (`**o*` → `Emphasis @1:2-1:5`).
        let start = delimiters[opener].virtualEnd - useDelims
        let end = delimiters[closer].virtualStart + useDelims
        stampInline(emphIdx, start, end, content: content)
        // The unused delimiters stay text covering only themselves.
        stampInline(openerInl, delimiters[opener].virtualStart, start, content: content)
        stampInline(closerInl, end, delimiters[closer].virtualEnd, content: content)
        delimiters[opener].virtualEnd = start
        delimiters[closer].virtualStart = end
        var sibling = storage[openerInl].next
        while let sibling_ = sibling, sibling_ != closerInl {
            let nextSibling = storage[sibling_].next
            storage.unlinkChild(sibling_)
            storage.appendChild(sibling_, to: emphIdx)
            sibling = nextSibling
        }
        storage.insertChildAfter(emphIdx, after: openerInl)
        var resultCloser: Int? = closer
        if openerNumChars == 0 {
            storage.unlinkChild(openerInl)
            removeDelim(opener)
        }
        if closerNumChars == 0 {
            storage.unlinkChild(closerInl)
            let next = delimiters[closer].next
            removeDelim(closer)
            resultCloser = next
        }
        return resultCloser
    }

    /// Removes the delimiters from `last` back to, but not including, `first`.
    private mutating func removeDelims(after first: Int, through last: Int) {
        var d: Int? = last
        while let dd = d, dd != first {
            let prev = delimiters[dd].previous
            removeDelim(dd)
            d = prev
        }
    }

    private mutating func removeDelim(_ idx: Int) {
        let prev = delimiters[idx].previous
        let next = delimiters[idx].next
        if let prev {
            delimiters[prev].next = next
        }
        if let next {
            delimiters[next].previous = prev
        }
        if idx == lastDelim {
            lastDelim = prev
        }
    }

    private func literalLength(of nodeIdx: DocumentStorage.Index) -> Int {
        guard case .literal(let ref) = storage[nodeIdx].data else {
            preconditionFailure("a delimiter run's text node holds a literal")
        }
        return Int(ref.totalLength)
    }

    // MARK: - Smart punctuation

    /// Smart-punctuation replacement characters.
    static let leftSingleQuote = "\u{2018}"
    static let rightSingleQuote = "\u{2019}"
    static let leftDoubleQuote = "\u{201C}"
    static let rightDoubleQuote = "\u{201D}"
    static let enDash = "\u{2013}"
    static let emDash = "\u{2014}"
    static let ellipsis = "\u{2026}"

    private mutating func appendSmartConstant(_ s: String) {
        for b in s.utf8 {
            storage.strings.append(b)
        }
    }

    /// Appends `s` to the arena, returning its chunk.
    private mutating func smartConstantChunk(_ s: String) -> Chunk {
        let offset = storage.strings.count
        appendSmartConstant(s)
        return arenaChunk(from: offset)
    }

    /// Replace a text node's literal with a constant smart-punctuation glyph.
    private mutating func setSmartLiteral(of nodeIdx: DocumentStorage.Index, _ s: String) {
        let ref = storage.intern(smartConstantChunk(s))
        storage[nodeIdx].data = .literal(ref)
    }

    /// A run of two or more hyphens becomes en and em dashes; a lone hyphen stays pending text.
    private mutating func handleSmartHyphen(start: Int, content: borrowing ContentSpan, parent: DocumentStorage.Index, pendingTextStart: inout Int) -> Int {
        let end = content.endOffset
        var runEnd = start
        while runEnd < end,
              content[runEnd] == UInt8(ascii: "-") {
            runEnd += 1
        }
        let numHyphens = runEnd - start
        if numHyphens < 2 {
            return runEnd
        }
        var enCount = 0
        var emCount = 0
        if numHyphens % 3 == 0 {
            emCount = numHyphens / 3
        } else if numHyphens % 2 == 0 {
            enCount = numHyphens / 2
        } else if numHyphens % 3 == 2 {
            enCount = 1
            emCount = (numHyphens - 2) / 3
        } else {
            enCount = 2
            emCount = (numHyphens - 4) / 3
        }
        let offset = storage.strings.count
        for _ in 0..<emCount {
            appendSmartConstant(Self.emDash)
        }
        for _ in 0..<enCount {
            appendSmartConstant(Self.enDash)
        }
        let chunk = arenaChunk(from: offset)
        // The dashes are arena-backed, but their source range is the hyphen run.
        emitLiteral(.text, chunk, start: start, end: runEnd, to: parent, pendingTextStart: &pendingTextStart, content: content)
        return runEnd
    }

    /// Emits a `'` or `"` as its initial curly quote and, if it can open or close, pushes a delimiter for `processEmphasis` to pair.
    private mutating func handleQuoteDelim(char: UInt8, start: Int, content: borrowing ContentSpan, parent: DocumentStorage.Index, pendingTextStart: inout Int) -> Int {
        // A quote delimiter is one character.
        let runEnd = start + 1
        let flanking = classifyFlanking(char: char, start: start, runEnd: runEnd, content: content)
        let leftFlanking = flanking.leftFlanking
        let rightFlanking = flanking.rightFlanking
        let beforeChar = flanking.beforeChar
        let canOpen = leftFlanking && !rightFlanking && beforeChar != UInt8(ascii: "]") && beforeChar != UInt8(ascii: ")")
        let canClose = rightFlanking
        // `'` starts as an apostrophe; `"` as a closing quote when it can close, otherwise an opening one.
        let literal: String
        if char == UInt8(ascii: "'") {
            literal = Self.rightSingleQuote
        } else {
            literal = canClose ? Self.rightDoubleQuote : Self.leftDoubleQuote
        }
        // The curly quote is arena-backed, but its source range is the straight quote.
        let textIdx = emitLiteral(.text, smartConstantChunk(literal), start: start, end: runEnd, to: parent, pendingTextStart: &pendingTextStart, content: content)
        if canOpen || canClose {
            // A length of 3 makes the multiple-of-3 test always admit a quote pairing.
            pushDelimiter(char, length: 3, canOpen: canOpen, canClose: canClose, inlText: textIdx, range: start..<runEnd)
        }
        return runEnd
    }

    /// Pushes a delimiter run spanning virtual `range` onto the delimiter stack.
    private mutating func pushDelimiter(_ char: UInt8, length: Int, canOpen: Bool, canClose: Bool, inlText: DocumentStorage.Index, range: Range<Int>) {
        let prev = lastDelim
        let newIdx = delimiters.count
        delimiters.append(DelimiterRecord(
            character: char,
            length: length,
            canOpen: canOpen,
            canClose: canClose,
            inlText: inlText,
            virtualStart: range.lowerBound,
            virtualEnd: range.upperBound,
            previous: prev,
            next: nil
        ))
        if let prev {
            delimiters[prev].next = newIdx
        }
        lastDelim = newIdx
    }

    // MARK: - Code spans

    private struct CodeSpanMatch {
        var content: Chunk      // the raw code-span content
        var afterClose: Int     // offset just past the closing backtick run
        var backtickCount: Int  // number of backticks in the opening/closing run
    }

    /// Matches a code span at the backtick run at `start`, or `nil` if no closing run of equal length follows.
    private mutating func matchCodeSpan(start: Int, content: borrowing ContentSpan) -> CodeSpanMatch? {
        let end = content.endOffset
        let openEnd = scanBacktickRun(start: start, content: content)
        let runLength = openEnd - start
        // Rescanning for every unmatched opener would make a paragraph of distinct-length runs quadratic.
        if backtickRunsSeen.rulesOutCloser(length: runLength, after: openEnd) {
            return nil
        }

        // Find a matching same-length backtick run after `openEnd`.
        var i = openEnd
        while i < end {
            let b = content[i]
            if b == UInt8(ascii: "`") {
                let closeEnd = scanBacktickRun(start: i, content: content)
                let closeLength = closeEnd - i
                if closeLength == runLength {
                    // The caller normalizes the raw content. A continuation line's leading whitespace is not
                    // part of it (Paragraphs).
                    let contentChunk = materializedChunk(start: openEnd, end: i, content: content)
                    return CodeSpanMatch(content: contentChunk, afterClose: closeEnd, backtickCount: runLength)
                }
                i = closeEnd
                continue
            }
            i += 1
        }
        // Runs are recorded in a second walk, taken at most once per paragraph, so scans that find a closer skip
        // the bookkeeping.
        backtickRunsSeen.scannedToEndFrom = min(backtickRunsSeen.scannedToEndFrom ?? openEnd, openEnd)
        var k = openEnd
        while k < end {
            guard content[k] == UInt8(ascii: "`") else {
                k += 1
                continue
            }
            let runEnd = scanBacktickRun(start: k, content: content)
            backtickRunsSeen.recordRun(length: runEnd - k, start: k)
            k = runEnd
        }
        return nil
    }

    /// The offset past the backtick run at `start`.
    private func scanBacktickRun(start: Int, content: borrowing ContentSpan) -> Int {
        let end = content.endOffset
        var i = start
        while i < end, content[i] == UInt8(ascii: "`") {
            i += 1
        }
        return i
    }

    /// Normalizes code span content (Code spans), copying only if a line ending becomes a space.
    private mutating func normalizeCodeSpanContent(_ chunk: Chunk) -> Chunk {
        var hasNewline = false
        let endOff = chunk.offset + chunk.length
        for i in chunk.offset..<endOff {
            let b = readByte(at: i, in: chunk)
            if b == UInt8(ascii: "\n") {
                hasNewline = true
                break
            }
        }
        var workChunk: Chunk
        if hasNewline {
            let outOffset = storage.strings.count
            var i = chunk.offset
            while i < endOff {
                let b = readByte(at: i, in: chunk)
                assert(b != UInt8(ascii: "\r"), "inline content holds no carriage return: lines split on CR and join with LF")
                if b == UInt8(ascii: "\n") {
                    storage.strings.append(UInt8(ascii: " "))
                    i += 1
                    continue
                }
                storage.strings.append(b)
                i += 1
            }
            workChunk = arenaChunk(from: outOffset)
        } else {
            workChunk = chunk
        }
        return trimSingleSpaces(workChunk)
    }

    /// The code span one-space strip (Code spans).
    private func trimSingleSpaces(_ chunk: Chunk) -> Chunk {
        let start = chunk.offset
        let end = chunk.range.upperBound
        if start < end,
           readByte(at: start, in: chunk) == UInt8(ascii: " "),
           readByte(at: end - 1, in: chunk) == UInt8(ascii: " ") {
            let innerStart = start + 1
            let innerEnd = end - 1
            var hasNonSpace = false
            if innerStart < innerEnd {
                for j in innerStart..<innerEnd {
                    let b = readByte(at: j, in: chunk)
                    if b != UInt8(ascii: " ") {
                        hasNonSpace = true
                        break
                    }
                }
            }
            if hasNonSpace {
                return chunk.extracting(1..<(chunk.length - 1))
            }
        }
        return chunk
    }

    // MARK: - Line breaks

    private struct LineBreakInfo {
        var isHard: Bool
        var textEnd: Int  // exclusive end of the pending-text region (excludes the marker bytes)
    }

    /// Classifies the line ending at `newlineOffset` as a soft or hard line break (Hard line breaks), with where the
    /// pending text ends, before any backslash or trailing spaces.
    private func classifyLineBreak(at newlineOffset: Int, pendingTextStart: Int, content: borrowing ContentSpan) -> LineBreakInfo {
        // Backslash hard break.
        if newlineOffset > pendingTextStart {
            let prev = content[newlineOffset - 1]
            if prev == UInt8(ascii: "\\") {
                return LineBreakInfo(isHard: true, textEnd: newlineOffset - 1)
            }
        }
        // Spaces and tabs before a line ending are not text, whatever the break; a line tabulation or form
        // feed is (`a\f\t  \n` keeps `a\f`). The break is hard when the two characters before the line ending
        // are spaces, so `a  \t\n` is soft.
        var textEnd = newlineOffset
        var leadingSpaces = 0
        var inSpaceRun = true
        while textEnd > pendingTextStart {
            let prev = content[textEnd - 1]
            if prev == UInt8(ascii: " ") {
                if inSpaceRun { leadingSpaces += 1 }
            } else if prev == UInt8(ascii: "\t") {
                inSpaceRun = false
            } else {
                break
            }
            textEnd -= 1
        }
        return LineBreakInfo(isHard: leadingSpaces >= 2, textEnd: textEnd)
    }

    // MARK: - Autolinks

    private struct AutolinkMatch {
        var interior: Range<Int>  // bytes between `<` and `>` (the visible text)
        var afterClose: Int       // offset just past the closing `>`
        var isEmail: Bool
    }

    /// Matches an autolink (Autolinks) at the `<` at `start`.
    private func matchAutolink(start: Int, content: borrowing ContentSpan) -> AutolinkMatch? {
        if let uri = matchURIAutolink(start: start, content: content) {
            return uri
        }
        return matchEmailAutolink(start: start, content: content)
    }

    /// A URI autolink (Autolinks).
    private func matchURIAutolink(start: Int, content: borrowing ContentSpan) -> AutolinkMatch? {
        let end = content.endOffset
        var i = start + 1
        if i >= end {
            return nil
        }
        let first = content[i]
        if !first.isASCIILetter {
            return nil
        }
        i += 1
        var schemeChars = 1
        while i < end, schemeChars < 32 {
            let b = content[i]
            let ok = b.isASCIILetter
                || b.isASCIIDigit
                || b == UInt8(ascii: "+")
                || b == UInt8(ascii: ".")
                || b == UInt8(ascii: "-")
            if !ok {
                break
            }
            i += 1
            schemeChars += 1
        }
        // Need at least 2-char scheme and a `:`.
        if schemeChars < 2 || i >= end {
            return nil
        }
        if content[i] != UInt8(ascii: ":") {
            return nil
        }
        i += 1
        // Scan body until `>`. An absolute URI excludes ASCII control characters, DEL (0x7F) included.
        let bodyStart = start + 1
        while i < end {
            let b = content[i]
            if b == UInt8(ascii: ">") {
                return AutolinkMatch(
                    interior: bodyStart..<i,
                    afterClose: i + 1,
                    isEmail: false
                )
            }
            if b == UInt8(ascii: "<") || b == UInt8(ascii: " ") || b == UInt8(ascii: "\t")
                || b == UInt8(ascii: "\n") || b == UInt8(ascii: "\r") || b < 0x20
                || b == 0x7F {
                return nil
            }
            i += 1
        }
        return nil
    }

    /// An email autolink (Autolinks).
    private func matchEmailAutolink(start: Int, content: borrowing ContentSpan) -> AutolinkMatch? {
        let end = content.endOffset
        var i = start + 1
        let bodyStart = i
        // Local part: 1+ local-allowed chars, no `@`.
        var localChars = 0
        while i < end {
            let b = content[i]
            if b == UInt8(ascii: "@") {
                break
            }
            if !isEmailLocalChar(b) {
                return nil
            }
            i += 1
            localChars += 1
        }
        if localChars == 0 || i >= end {
            return nil
        }
        i += 1
        var labelStart = i
        while true {
            if i >= end {
                return nil
            }
            let b = content[i]
            if b == UInt8(ascii: ">") || b == UInt8(ascii: ".") {
                let labelLength = i - labelStart
                if labelLength == 0 || labelLength > 63
                    || content[labelStart] == UInt8(ascii: "-") || content[i - 1] == UInt8(ascii: "-") {
                    return nil
                }
                if b == UInt8(ascii: ">") {
                    break
                }
                labelStart = i + 1
            } else if !(b.isASCIILetter || b.isASCIIDigit || b == UInt8(ascii: "-")) {
                // Stopping at the first byte no domain holds keeps an unclosed `<local@` from scanning the block.
                return nil
            }
            i += 1
        }
        return AutolinkMatch(
            interior: bodyStart..<i,
            afterClose: i + 1,
            isEmail: true
        )
    }

    private func isEmailLocalChar(_ b: UInt8) -> Bool {
        if b.isASCIILetter || b.isASCIIDigit {
            return true
        }
        switch b {
        case UInt8(ascii: "."), UInt8(ascii: "!"), UInt8(ascii: "#"), UInt8(ascii: "$"),
             UInt8(ascii: "%"), UInt8(ascii: "&"), UInt8(ascii: "'"), UInt8(ascii: "*"),
             UInt8(ascii: "+"), UInt8(ascii: "/"), UInt8(ascii: "="), UInt8(ascii: "?"),
             UInt8(ascii: "^"), UInt8(ascii: "_"), UInt8(ascii: "`"), UInt8(ascii: "{"),
             UInt8(ascii: "|"), UInt8(ascii: "}"), UInt8(ascii: "~"), UInt8(ascii: "-"):
            return true
        default:
            return false
        }
    }

    /// Whether `b` may appear in an extended email autolink's local part (Autolinks (extension)).
    private func isGFMEmailLocalChar(_ b: UInt8) -> Bool {
        if b.isASCIILetter || b.isASCIIDigit {
            return true
        }
        switch b {
        case UInt8(ascii: "."), UInt8(ascii: "+"), UInt8(ascii: "-"), UInt8(ascii: "_"):
            return true
        default:
            return false
        }
    }

    /// Emits a `.link` with one `.text` child for an autolink.
    ///
    /// The text has character references decoded, but not backslash escapes (Backslash escapes). An email's URL gets a `mailto:` prefix; an email admits no `;`, so it holds no reference.
    private mutating func emitAutolink(auto: AutolinkMatch, into parent: DocumentStorage.Index, content: borrowing ContentSpan) {
        let textChunk = unescapeURLChunk(
            content.chunk(offset: auto.interior.lowerBound, length: auto.interior.count),
            backslashEscapes: false
        )
        let urlChunk = auto.isEmail
            ? materializeAutolinkURL(prefix: "mailto:", start: auto.interior.lowerBound, end: auto.interior.upperBound, content: content)
            : textChunk
        let urlRef = storage.intern(urlChunk)
        let textRef = storage.intern(textChunk)
        // The link spans the whole `<…>`; the text child spans just the interior visible bytes.
        let linkIdx = appendInline(.link, .link(url: urlRef, title: .empty), to: parent, start: auto.interior.lowerBound - 1, end: auto.afterClose, content: content)
        appendInline(.text, .literal(textRef), to: linkIdx, start: auto.interior.lowerBound, end: auto.interior.upperBound, content: content)
    }

    // MARK: - Raw inline HTML

    /// Matches raw HTML (Raw HTML) at the `<` at `start`, returning the offset past its end.
    private mutating func matchInlineHTML(start: Int, content: borrowing ContentSpan) -> Int? {
        let end = content.endOffset
        let after = start + 1
        if after >= end {
            return nil
        }
        let c = content[after]
        switch c {
        case UInt8(ascii: "!"):
            return matchHTMLBangForm(start: start, content: content)
        case UInt8(ascii: "?"):
            return Self.matchHTMLOpenerToCloser("<?", "?>", start: start, content: content, misses: &htmlCloserMisses.processingInstruction)
        case UInt8(ascii: "/"):
            return matchHTMLTag(nameStart: start + 2, isClosing: true, content: content)
        default:
            return matchHTMLTag(nameStart: after, isClosing: false, content: content)
        }
    }

    /// Matches an open or closing tag (Raw HTML) whose name starts at `nameStart`.
    private func matchHTMLTag(nameStart: Int, isClosing: Bool, content: borrowing ContentSpan) -> Int? {
        let end = content.endOffset
        guard let nameEnd = htmlTagNameEnd(from: nameStart, end: end, byte: { content[$0] }) else {
            return nil
        }
        return htmlTagEnd(afterName: nameEnd, isClosing: isClosing, end: end) { content[$0] }
    }

    /// Dispatch `<!`-prefixed HTML forms: comment, CDATA, declaration.
    private mutating func matchHTMLBangForm(start: Int, content: borrowing ContentSpan) -> Int? {
        let end = content.endOffset
        let i = start + 2
        if i >= end {
            return nil
        }
        let next = content[i]
        if next == UInt8(ascii: "-") {
            return matchHTMLComment(start: start, content: content)
        }
        if next == UInt8(ascii: "[") {
            return Self.matchHTMLOpenerToCloser("<![CDATA[", "]]>", start: start, content: content, misses: &htmlCloserMisses.cdata)
        }
        return matchHTMLDeclaration(start: start, content: content)
    }

    /// Matches an HTML comment (Raw HTML).
    private mutating func matchHTMLComment(start: Int, content: borrowing ContentSpan) -> Int? {
        let end = content.endOffset
        if start + 4 > end {
            return nil
        }
        if content[start + 2] != UInt8(ascii: "-") || content[start + 3] != UInt8(ascii: "-") {
            return nil
        }
        let bodyStart = start + 4
        // <!-->
        if bodyStart < end, content[bodyStart] == UInt8(ascii: ">") {
            return bodyStart + 1
        }
        // <!--->
        if bodyStart + 1 < end, content[bodyStart] == UInt8(ascii: "-"), content[bodyStart + 1] == UInt8(ascii: ">") {
            return bodyStart + 2
        }
        return Self.scanRawHTMLCloser("-->", from: bodyStart, content: content, misses: &htmlCloserMisses.comment)
    }

    /// Matches a declaration (Raw HTML).
    private mutating func matchHTMLDeclaration(start: Int, content: borrowing ContentSpan) -> Int? {
        let end = content.endOffset
        var i = start + 2
        var nameLen = 0
        while i < end {
            let b = content[i]
            if b.isUppercaseASCIILetter {
                nameLen += 1
                i += 1
            } else {
                break
            }
        }
        if nameLen == 0 {
            return nil
        }
        let afterSpaces = skipSpaceChars(
            start: i, content: content
        )
        if afterSpaces == i {
            return nil
        }
        return Self.scanRawHTMLCloser(">", from: afterSpaces, content: content, misses: &htmlCloserMisses.declaration)
    }

    /// Matches a CDATA section or processing instruction (Raw HTML): the case-sensitive `opener`, then the first `closer`.
    private static func matchHTMLOpenerToCloser(_ opener: String, _ closer: String, start: Int, content: borrowing ContentSpan, misses: inout Range<Int>) -> Int? {
        let end = content.endOffset
        let openerLength = opener.utf8.count
        if start + openerLength > end {
            return nil
        }
        for (k, openerByte) in opener.utf8.enumerated() {
            if content[start + k] != openerByte {
                return nil
            }
        }
        return scanRawHTMLCloser(closer, from: start + openerLength, content: content, misses: &misses)
    }

    /// The offset past the first `closer` at or after `start`, or `nil`.
    ///
    /// A failing scan records in `misses` that every start from `start` fails, since a later start sees a subset of the same bytes and the same content end.
    private static func scanRawHTMLCloser(
        _ closer: String, from start: Int, content: borrowing ContentSpan, misses: inout Range<Int>
    ) -> Int? {
        let end = content.endOffset
        if misses.contains(start) {
            return nil
        }
        let width = closer.utf8.count
        var i = start
        while i + width <= end {
            assert(content[i] != 0, "inline content holds no NUL: the block parser replaces it with U+FFFD")
            var matched = 0
            for closerByte in closer.utf8 {
                if content[i + matched] != closerByte {
                    break
                }
                matched += 1
            }
            if matched == width {
                return i + width
            }
            i += 1
        }
        misses = start..<Int.max
        return nil
    }

    /// Skips whitespace characters (Characters and lines).
    private func skipSpaceChars(start: Int, content: borrowing ContentSpan) -> Int {
        let end = content.endOffset
        var i = start
        while i < end {
            let b = content[i]
            if !b.isASCIISpace {
                break
            }
            i += 1
        }
        return i
    }

    // MARK: - Extended autolinks

    /// The form of an extended autolink, which decides the scheme prefix its destination gets.
    private enum GFMAutolinkForm {
        case uri      // already has http:// or https:// or ftp:// prefix
        case www      // needs http:// synthesized
        case email    // needs mailto: synthesized
    }

    /// An extended autolink's visible text range and form.
    ///
    /// `emailSchemeFolded` marks an email whose range begins with a `mailto:` or `xmpp:` scheme, so the range is the
    /// destination as is.
    private struct GFMAutolinkMatch {
        var urlStart: Int
        var urlEnd: Int
        var form: GFMAutolinkForm
        var emailSchemeFolded: Bool = false
    }

    /// Matches a `://` or `www.` extended autolink at `cursor`. Emails are matched by `gfmEmailAutolinkPass`.
    private func matchGFMAutolink(trigger: UInt8, cursor: Int, content: borrowing ContentSpan) -> GFMAutolinkMatch? {
        if trigger == UInt8(ascii: ":") {
            return matchGFMSchemeAutolink(
                colon: cursor, content: content
            )
        }
        precondition(trigger == UInt8(ascii: "w") || trigger == UInt8(ascii: "W"), "a GFM autolink trial is dispatched only on `:`, `w` or `W`")
        return matchGFMWWWAutolink(
            start: cursor, content: content
        )
    }

    /// `:`-triggered: looks back for `http`/`https`/`ftp`, then forward for `//` and a URL body.
    private func matchGFMSchemeAutolink(colon: Int, content: borrowing ContentSpan) -> GFMAutolinkMatch? {
        let end = content.endOffset
        let chunkStart = content.startOffset
        if colon + 3 >= end {
            return nil
        }
        if content[colon + 1] != UInt8(ascii: "/") || content[colon + 2] != UInt8(ascii: "/") {
            return nil
        }
        guard let schemeStart = matchSchemeBackward(colon: colon, content: content) else {
            return nil
        }
        // The scheme is the whole run of ASCII letters before `://`, so a letter before `http` makes the scheme
        // something else (`xhttp://a.b` is text). Any other character may precede it.
        if schemeStart > chunkStart, content[schemeStart - 1].isASCIILetter {
            return nil
        }
        guard schemeURLDomainAccepted(afterSlashes: colon + 3, content: content) else {
            return nil
        }
        let urlEnd = scanGFMURLBody(start: colon + 3, content: content)
        let trimmedEnd = trimTrailingPunctuation(urlStart: schemeStart, urlEnd: urlEnd, content: content)
        return GFMAutolinkMatch(
            urlStart: schemeStart,
            urlEnd: trimmedEnd,
            form: .uri
        )
    }

    /// The start of a case-insensitive `http`, `https` or `ftp` ending just before `colon`.
    private func matchSchemeBackward(colon: Int, content: borrowing ContentSpan) -> Int? {
        let chunkStart = content.startOffset
        if colon - 5 >= chunkStart,
           bytesEqual(at: colon - 5, target: "https", content: content, ignoringASCIICase: true) {
            return colon - 5
        }
        if colon - 4 >= chunkStart,
           bytesEqual(at: colon - 4, target: "http", content: content, ignoringASCIICase: true) {
            return colon - 4
        }
        if colon - 3 >= chunkStart,
           bytesEqual(at: colon - 3, target: "ftp", content: content, ignoringASCIICase: true) {
            return colon - 3
        }
        return nil
    }

    /// `w`/`W`-triggered: matches `www.` followed by a URL body.
    private func matchGFMWWWAutolink(start: Int, content: borrowing ContentSpan) -> GFMAutolinkMatch? {
        let end = content.endOffset
        let chunkStart = content.startOffset
        if start > chunkStart {
            let pre = content[start - 1]
            if !isValidWWWPreceding(pre) {
                return nil
            }
        }
        if start + 4 > end {
            return nil
        }
        if !bytesEqual(at: start, target: "www.", content: content) {
            return nil
        }
        guard domainAccepted(base: start, requirePeriod: true, content: content) else {
            return nil
        }
        let urlEnd = scanGFMURLBody(start: start + 4, content: content)
        let trimmedEnd = trimTrailingPunctuation(
            urlStart: start, urlEnd: urlEnd,
            content: content
        )
        return GFMAutolinkMatch(urlStart: start, urlEnd: trimmedEnd, form: .www)
    }

    /// The length of lowercase `scheme` (`mailto:` or `xmpp:`) ending at `colon`, when it lies within
    /// `[localBound, colon]` and starts at `localBound` or after a non-alphanumeric byte, so it folds into an
    /// extended email autolink.
    private func matchEmailScheme(_ scheme: String, colon: Int, localBound: Int, content: borrowing ContentSpan) -> Int? {
        let len = scheme.utf8.count
        let schemeStart = colon + 1 - len
        if schemeStart < localBound {
            return nil
        }
        for (k, schemeByte) in scheme.utf8.enumerated() where content[schemeStart + k] != schemeByte {
            return nil
        }
        if schemeStart == localBound {
            return len
        }
        let prev = content[schemeStart - 1]
        if prev.isASCIILetter || prev.isASCIIDigit {
            return nil
        }
        return len
    }

    /// Matches an extended email autolink around the `@` at `at`, scanning back no further than `localBound`:
    /// the content start, or the end of the previous candidate.
    ///
    /// On failure `resumeAt` is past everything scanned, and every `@` before it is settled, so the pass stays
    /// linear on `@`-dense input.
    private func matchGFMEmailAutolink(at: Int, localBound: Int, content: borrowing ContentSpan, resumeAt: inout Int) -> GFMAutolinkMatch? {
        let end = content.endOffset
        // A second `@` in the domain restarts the trial there, the run between becoming the local part. The
        // scheme state and the period flag carry across the restart.
        var atSign = at
        var schemeFolded = false
        var isXmpp = false
        var hasPeriodBeforeAlphanumeric = false
        while true {
            // A `:` completing a lowercase `mailto:` or `xmpp:` at a boundary folds the scheme into the link.
            var localStart = atSign
            while localStart > localBound {
                let b = content[localStart - 1]
                if isGFMEmailLocalChar(b) {
                    localStart -= 1
                    continue
                }
                if b == UInt8(ascii: ":") {
                    if let len = matchEmailScheme("mailto:", colon: localStart - 1, localBound: localBound, content: content) {
                        schemeFolded = true
                        localStart -= len
                        continue
                    }
                    if let len = matchEmailScheme("xmpp:", colon: localStart - 1, localBound: localBound, content: content) {
                        schemeFolded = true
                        isXmpp = true
                        localStart -= len
                        continue
                    }
                }
                break
            }
            // Without a local part or a folded scheme this `@` is no email. A folded scheme alone suffices, so
            // `mailto:@a.b` is accepted.
            if localStart == atSign {
                resumeAt = atSign + 1
                return nil
            }
            // The domain is ASCII alphanumerics, `-`, `_`, and periods followed by an alphanumeric, with `/`
            // too after `xmpp:`.
            var i = atSign + 1
            var sawSecondAt = false
            while i < end {
                let b = content[i]
                if b.isASCIILetter || b.isASCIIDigit || b == UInt8(ascii: "-") || b == UInt8(ascii: "_") {
                    i += 1
                } else if b == UInt8(ascii: "."), i + 1 < end, content[i + 1].isASCIILetter || content[i + 1].isASCIIDigit {
                    hasPeriodBeforeAlphanumeric = true
                    i += 1
                } else if b == UInt8(ascii: "/"), isXmpp {
                    i += 1
                } else {
                    sawSecondAt = b == UInt8(ascii: "@")
                    break
                }
            }
            if sawSecondAt {
                atSign = i
                continue
            }
            resumeAt = i
            // The domain holds a period and ends in a letter.
            guard i > atSign + 1, hasPeriodBeforeAlphanumeric, content[i - 1].isASCIILetter else {
                return nil
            }
            return GFMAutolinkMatch(urlStart: localStart, urlEnd: i, form: .email, emailSchemeFolded: schemeFolded)
        }
    }

    /// Emits a `.link` with one `.text` child for a `://` or `www.` autolink; `www.` gets an `http://` prefix.
    private mutating func emitGFMAutolink(auto: GFMAutolinkMatch, content: borrowing ContentSpan, into parent: DocumentStorage.Index) {
        precondition(auto.form != .email, "email autolinks are emitted by gfmEmailAutolinkPass")
        let urlChunk: Chunk
        if auto.form == .uri {
            urlChunk = content.chunk(
                offset: auto.urlStart,
                length: auto.urlEnd - auto.urlStart
            )
        } else {
            urlChunk = materializeAutolinkURL(
                prefix: "http://",
                start: auto.urlStart, end: auto.urlEnd,
                content: content
            )
        }
        let textChunk = content.chunk(
            offset: auto.urlStart,
            length: auto.urlEnd - auto.urlStart
        )
        let urlRef = storage.intern(urlChunk)
        let textRef = storage.intern(textChunk)
        let linkIdx = appendInline(.link, .link(url: urlRef, title: .empty), to: parent, start: auto.urlStart, end: auto.urlEnd, content: content)
        appendInline(.text, .literal(textRef), to: linkIdx, start: auto.urlStart, end: auto.urlEnd, content: content)
    }

    /// Appends `prefix` and the content bytes `start..<end` to the arena, returning their chunk.
    private mutating func materializeAutolinkURL(prefix: String, start: Int, end: Int, content: borrowing ContentSpan) -> Chunk {
        let offset = storage.strings.count
        for b in prefix.utf8 {
            storage.strings.append(b)
        }
        for j in start..<end {
            storage.strings.append(content[j])
        }
        return arenaChunk(from: offset)
    }

    /// Scans to a URL boundary: a space, tab, line ending or `<`. `>`, line tabulation and form feed are URL bytes.
    private func scanGFMURLBody(
        start: Int,
        content: borrowing ContentSpan
    ) -> Int {
        let end = content.endOffset
        var i = start
        while i < end {
            let b = content[i]
            if b.isSpaceTabOrNewline || b == UInt8(ascii: "<") {
                break
            }
            i += 1
        }
        return i
    }

    /// Trims an extended autolink's trailing punctuation (Autolinks (extension)), right to left: `? ! . , : * _ ~ ' "`
    /// one at a time, a `)` only while the URL holds more `)` than `(`, and at a `;` a whole `&letters;` entity
    /// tail, or else just the `;`.
    private func trimTrailingPunctuation(urlStart: Int, urlEnd: Int, content: borrowing ContentSpan) -> Int {
        var opening = 0
        var closing = 0
        for j in urlStart..<urlEnd {
            switch content[j] {
            case UInt8(ascii: "("): opening += 1
            case UInt8(ascii: ")"): closing += 1
            default: break
            }
        }

        var i = urlEnd
        trim: while i > urlStart {
            switch content[i - 1] {
            case UInt8(ascii: ")"):
                if closing <= opening {
                    break trim
                }
                closing -= 1
                i -= 1
            case UInt8(ascii: "?"), UInt8(ascii: "!"), UInt8(ascii: "."), UInt8(ascii: ","),
                 UInt8(ascii: ":"), UInt8(ascii: "*"), UInt8(ascii: "_"), UInt8(ascii: "~"),
                 UInt8(ascii: "'"), UInt8(ascii: "\""):
                i -= 1
            case UInt8(ascii: ";"):
                // An entity tail needs at least one letter, so `&;` peels only the `;`.
                var entityStart = i - 2
                while entityStart > urlStart, content[entityStart].isASCIILetter {
                    entityStart -= 1
                }
                if entityStart < i - 2, content[entityStart] == UInt8(ascii: "&") {
                    i = entityStart
                } else {
                    i -= 1
                }
            default:
                break trim
            }
        }
        return i
    }

    /// Whether the domain of a www or url extended autolink at `base` is accepted.
    ///
    /// The scan runs from the domain's second character, the first being checked by the caller, over host
    /// characters, `-`, `_` and `.`, up to the first other character or the content's last character, which it
    /// never examines. A backslash makes it examine the next character instead. An underscore in either of the
    /// last two period-separated segments rejects the domain unless the scan passed more than ten periods.
    /// `requirePeriod` also demands a period.
    private func domainAccepted(base: Int, requirePeriod: Bool, content: borrowing ContentSpan) -> Bool {
        let end = content.endOffset
        let size = end - base
        var periods = 0
        var underscoresInPreviousSegment = 0
        var underscoresInLastSegment = 0
        var i = 1
        while i < size - 1 {
            if content[base + i] == UInt8(ascii: "\\"), i < size - 2 {
                i += 1
            }
            let b = content[base + i]
            if b == UInt8(ascii: "_") {
                underscoresInLastSegment += 1
            } else if b == UInt8(ascii: ".") {
                underscoresInPreviousSegment = underscoresInLastSegment
                underscoresInLastSegment = 0
                periods += 1
            } else if !isHostByte(b) && b != UInt8(ascii: "-") {
                break
            }
            i += 1
        }
        if (underscoresInPreviousSegment > 0 || underscoresInLastSegment > 0) && periods <= 10 {
            return false
        }
        return !requirePeriod || periods > 0
    }

    /// Whether a url extended autolink's domain at `afterSlashes` is accepted: its first character is a host
    /// character or a non-ASCII character that is neither whitespace nor punctuation, and `domainAccepted`
    /// accepts the rest.
    private func schemeURLDomainAccepted(afterSlashes: Int, content: borrowing ContentSpan) -> Bool {
        let first = content[afterSlashes]
        if first < 0x80 {
            if !isHostByte(first) {
                return false
            }
        } else {
            let scalar = Self.decodeUTF8Scalar(at: afterSlashes, content: content)
            if Self.isUnicodeWhitespace(scalar) || Self.isUnicodePunctuation(scalar) {
                return false
            }
        }
        return domainAccepted(base: afterSlashes, requirePeriod: false, content: content)
    }

    /// Whether `b` is a host character: ASCII other than punctuation, space, tab, line ending or form feed.
    private func isHostByte(_ b: UInt8) -> Bool {
        b < 0x80 && !b.isASCIIPunct && (b == 0x0B || !b.isASCIISpace)
    }

    /// Characters that may directly precede an extended www autolink: space, tab, line feed, carriage return, `*`,
    /// `_`, `~` and `(`.
    private func isValidWWWPreceding(_ b: UInt8) -> Bool {
        if b.isSpaceTabOrNewline {
            return true
        }
        switch b {
        case UInt8(ascii: "*"), UInt8(ascii: "_"), UInt8(ascii: "~"), UInt8(ascii: "("):
            return true
        default:
            return false
        }
    }

    /// Whether `target` is at `start`. `ignoringASCIICase` folds only the comparison; the text keeps its case.
    private func bytesEqual(at start: Int, target: String, content: borrowing ContentSpan, ignoringASCIICase: Bool = false) -> Bool {
        let mask: UInt8 = ignoringASCIICase ? 0x20 : 0
        for (k, targetByte) in target.utf8.enumerated() {
            if (content[start + k] | mask) != (targetByte | mask) {
                return false
            }
        }
        return true
    }

    /// Appends `count` bytes to `out`, returning their chunk.
    private static func appendUTF8Bytes(bytes: Bytes8, count: Int, into out: inout UniqueArray<UInt8>) -> Chunk {
        let offset = out.count
        for i in 0..<count {
            out.append(bytes[i])
        }
        return Chunk(offset: offset, length: count, inSource: false)
    }

    // MARK: - Helpers

    /// Emits a `.text` node over `start..<end` if non-empty. Every line ending flushes the run, so it lies within one segment.
    private mutating func flushPendingText(start: Int, end: Int, content: borrowing ContentSpan, into parent: DocumentStorage.Index) {
        if end <= start {
            return
        }
        precondition(content.contiguousChunk(fromVirtual: start, limit: end)?.length == end - start, "a text run lies within one segment")
        appendInline(.text, .literal(storage.intern(content.chunk(offset: start, length: end - start))), to: parent, start: start, end: end, content: content)
    }

    /// Append an inline node to `parent`, stamped with the source range of the virtual range `start..<end`.
    @discardableResult
    private mutating func appendInline(_ kind: MarkdownNode.Kind, _ data: NodeData?, to parent: DocumentStorage.Index, start: Int, end: Int, content: borrowing ContentSpan) -> DocumentStorage.Index {
        let idx = storage.appendNode(NodeRecord(kind: kind, parent: parent, data: data))
        storage.appendChild(idx, to: parent)
        stampInline(idx, start, end, content: content)
        return idx
    }

    /// Flushes the pending text before `start`, then appends a `kind` node with literal `chunk` over `start..<end`. Pending text resumes at `end`.
    @discardableResult
    private mutating func emitLiteral(_ kind: MarkdownNode.Kind, _ chunk: Chunk, start: Int, end: Int, to parent: DocumentStorage.Index, pendingTextStart: inout Int, content: borrowing ContentSpan) -> DocumentStorage.Index {
        flushPendingText(start: pendingTextStart, end: start, content: content, into: parent)
        pendingTextStart = end
        return appendInline(kind, .literal(storage.intern(chunk)), to: parent, start: start, end: end, content: content)
    }

    /// A chunk for `[start, end)`, copied into the arena only when the range spans segments, as a code span or
    /// link destination or title can.
    private mutating func materializedChunk(start: Int, end: Int, content: borrowing ContentSpan) -> Chunk {
        if let contiguous = content.contiguousChunk(fromVirtual: start, limit: end),
           contiguous.length == end - start {
            return contiguous
        }
        let outOffset = storage.strings.count
        for k in start..<end {
            storage.strings.append(content[k])
        }
        return arenaChunk(from: outOffset)
    }

    /// Stamps `node`'s source range from virtual offsets `start..<end`.
    ///
    /// The last byte, `end - 1`, is resolved, so an `end` at a line join maps to just past the preceding source byte.
    @inline(__always)
    mutating func stampInline(_ node: DocumentStorage.Index, _ start: Int, _ end: Int, content: borrowing ContentSpan) {
        guard positionsEnabled, end > start else {
            return
        }
        storage.setSourceStart(node, content.sourceOffset(ofVirtual: start))
        storage.setSourceEnd(node, content.sourceOffset(ofVirtual: end - 1) + 1)
    }

    /// Merges adjacent `.text` children throughout `root`'s inline subtree, such as the separate nodes that smart punctuation and character references emit.
    mutating func consolidateTextNodes(_ root: DocumentStorage.Index) {
        var parent = root
        var child = storage[root].firstChild
        while true {
            guard let current = child else {
                guard storage.ascend(from: &parent, resumingAt: &child, within: root) else {
                    return
                }
                continue
            }
            if storage[current].kind == .text {
                while let next = storage[current].next, storage[next].kind == .text {
                    mergeTextNode(next, into: current)
                }
            } else {
                parent = current
                child = storage[current].firstChild
                continue
            }
            child = storage[current].next
        }
    }

    /// Appends copies of `ref`'s segments to the pool.
    private mutating func appendSegments(of ref: ContentRef) {
        for i in 0..<Int(ref.count) {
            let seg = storage.segments[Int(ref.first) + i]
            storage.segments.append(seg)
        }
    }

    /// Merges `source` into the preceding text node `dest` and unlinks it.
    private mutating func mergeTextNode(_ source: DocumentStorage.Index, into dest: DocumentStorage.Index) {
        guard case .literal(let destRef) = storage[dest].data,
              case .literal(let srcRef) = storage[source].data else {
            preconditionFailure("a text node holds a literal")
        }
        // Pool-contiguous runs widen in place. A destination ending the pool grows by copies of the source's segments
        // alone, since re-copying it per sibling would make a long run quadratic. Otherwise both are copied to the pool end.
        let isContiguous = destRef.first + destRef.count == srcRef.first
        let endsPool = Int(destRef.first + destRef.count) == storage.segments.count
        let first = isContiguous || endsPool ? destRef.first : Int32(storage.segments.count)
        if !isContiguous {
            if !endsPool {
                appendSegments(of: destRef)
            }
            appendSegments(of: srcRef)
        }
        storage[dest].data = .literal(ContentRef(
            first: first,
            count: destRef.count + srcRef.count,
            totalLength: destRef.totalLength + srcRef.totalLength
        ))
        if positionsEnabled {
            let a = storage.sourceRanges[dest]
            let b = storage.sourceRanges[source]
            precondition(a.start >= 0 && b.start >= 0, "with positions tracked, every text node is stamped before it consolidates")
            // From the first node's start to the last node's end, which differs from the union only when an earlier node ends past the last.
            storage.sourceRanges[dest] = DocumentStorage.SourceByteRange(
                start: a.start,
                end: b.end
            )
        }
        storage.unlinkChild(source)
    }

    // MARK: - Extended email autolink pass

    /// Finds extended email autolinks after emphasis resolution and `consolidateTextNodes`, splitting each text node
    /// outside a link at each address. A `_` or `*` beside an email is therefore resolved before the email's boundaries are.
    ///
    /// `image` maps the leaf's content to the source when it is a single arena chunk.
    mutating func gfmEmailAutolinkPass(_ root: DocumentStorage.Index, image: ContentImage?) {
        var parent = root
        var child = storage[root].firstChild
        while true {
            guard let current = child else {
                guard storage.ascend(from: &parent, resumingAt: &child, within: root) else {
                    return
                }
                continue
            }
            // Taken before the split, so resuming here skips the nodes the split inserts.
            let next = storage[current].next
            switch storage[current].kind {
            case .text:
                splitEmailsInTextNode(current, parent: parent, image: image)
            case .link:
                // Links may not contain other links (Links).
                break
            default:
                parent = current
                child = storage[current].firstChild
                continue
            }
            child = next
        }
    }

    /// Splits a text node into `[before, link, after]` at each extended email autolink.
    ///
    /// The content is copied once to a scratch buffer and scanned left to right; the text runs are carved from the
    /// node's segments. The link spans the address's source bytes, and each text run keeps the part of the node's
    /// range on its side, so a run that isn't all source bytes, such as a smart quote, still has a range.
    private mutating func splitEmailsInTextNode(_ node: DocumentStorage.Index, parent: DocumentStorage.Index, image: ContentImage?) {
        guard case .literal(let ref) = storage[node].data else {
            preconditionFailure("a text node holds a literal")
        }
        // Most text nodes have no `@`.
        if !contentRefContains(ref, byte: UInt8(ascii: "@")) {
            return
        }
        var scratch = UniqueArray<UInt8>()
        materialize(ref, into: &scratch)
        let total = scratch.count
        // `content` borrows only `scratch`, so the storage mutations below don't affect it.
        let content = ContentSpan(span: scratch.span, base: 0, inSource: false)

        // `current` is the running text node, starting at `segStart`. `cursor` is the floor for the next
        // backward local-part scan, so a later `@` can't reach into a prior email.
        var current = node
        var segStart = 0
        var cursor = 0
        var carve = ContentRefCarvePosition()
        var didSplit = false
        var i = 0
        var resumeAt = 0
        // The split node's end, which the last text run keeps.
        let nodeEnd = positionsEnabled ? storage.sourceRanges[node].end : -1
        while i < total {
            guard scratch[i] == UInt8(ascii: "@") else {
                i += 1
                continue
            }
            guard let auto = matchGFMEmailAutolink(
                at: i, localBound: cursor, content: content, resumeAt: &resumeAt
            ) else {
                // `resumeAt > i`, skipping every `@` the trial settled. The floor moves too, or a `+` or `.`
                // that ended the domain would pull the abandoned candidate into the next local part.
                cursor = resumeAt
                i = resumeAt
                continue
            }
            // `current` becomes the text run before this email.
            let beforeRef = subContentRef(of: ref, from: segStart, to: auto.urlStart, resumingAt: &carve)
            storage[current].data = .literal(beforeRef)
            let emailRef = subContentRef(of: ref, from: auto.urlStart, to: auto.urlEnd, resumingAt: &carve)
            let email = positionsEnabled ? sourceSpan(of: emailRef, image: image) : nil
            if let email {
                let currentStart = Int(storage.sourceRanges[current].start)
                precondition(currentStart >= 0, "a text run is placed before an address splits it")
                storage.setSourceStart(current, min(currentStart, email.start))
                storage.setSourceEnd(current, email.start)
            }

            // With a folded scheme the visible run is the destination, joined in the arena if it is several
            // segments, since a URL is read as one span. A plain email gets `mailto:`.
            let urlRef: ContentRef
            if !auto.emailSchemeFolded {
                urlRef = materializeURL(prefix: "mailto:", for: emailRef)
            } else if emailRef.count > 1 {
                urlRef = materializeURL(prefix: "", for: emailRef)
            } else {
                urlRef = emailRef
            }
            let linkIdx = storage.appendNode(NodeRecord(
                kind: .link, parent: parent, data: .link(url: urlRef, title: .empty)))
            let childIdx = storage.appendNode(NodeRecord(
                kind: .text, parent: linkIdx, data: .literal(emailRef)))
            storage.appendChild(childIdx, to: linkIdx)
            storage.insertChildAfter(linkIdx, after: current)
            if let email {
                for idx in [linkIdx, childIdx] {
                    storage.setSourceStart(idx, email.start)
                    storage.setSourceEnd(idx, email.end)
                }
            }

            // A fresh tail node becomes the running run. Its content is carved once its end is known, since
            // carving the whole tail per address would re-copy a long run's segments each time.
            let tailIdx = storage.appendNode(NodeRecord(
                kind: .text, parent: parent, data: .literal(.empty)))
            storage.insertChildAfter(tailIdx, after: linkIdx)
            if let email {
                storage.setSourceStart(tailIdx, email.end)
                storage.setSourceEnd(tailIdx, max(nodeEnd, email.end))
            }

            // Drop an empty run before the address.
            if beforeRef.totalLength == 0 {
                storage.unlinkChild(current)
            }
            current = tailIdx
            segStart = auto.urlEnd
            cursor = auto.urlEnd
            i = auto.urlEnd
            didSplit = true
        }
        if didSplit {
            let afterRef = subContentRef(of: ref, from: segStart, to: total, resumingAt: &carve)
            storage[current].data = .literal(afterRef)
            if afterRef.totalLength == 0 {
                storage.unlinkChild(current)
            }
        }
    }

    /// Whether any content byte of `ref` is `target`.
    private func contentRefContains(_ ref: ContentRef, byte target: UInt8) -> Bool {
        for s in 0..<Int(ref.count) {
            let chunk = storage.segments[Int(ref.first) + s].chunk
            // Every text node is scanned, so the bytes are chosen once per segment rather than per byte.
            let bytes = chunk.inSource ? sourceBytes : storage.strings.span
            for k in chunk.range where bytes[k] == target { return true }
        }
        return false
    }

    /// Copies `ref`'s content bytes into `out`.
    private func materialize(_ ref: ContentRef, into out: inout UniqueArray<UInt8>) {
        for s in 0..<Int(ref.count) {
            let chunk = storage.segments[Int(ref.first) + s].chunk
            for k in chunk.range { out.append(readByte(at: k, in: chunk)) }
        }
    }

    /// Where the next of a left-to-right series of `subContentRef` carves resumes: the index within the ref of a
    /// segment beginning at or before the carve, and that segment's content offset.
    private struct ContentRefCarvePosition {
        var segment = 0
        var start = 0
    }

    /// Carves `[lo, hi)` of `ref`'s content into new segments over the same bytes.
    ///
    /// Resuming from `position`, carves that never start before an earlier carve's end visit each segment of `ref` a
    /// bounded number of times in total.
    private mutating func subContentRef(of ref: ContentRef, from lo: Int, to hi: Int, resumingAt position: inout ContentRefCarvePosition) -> ContentRef {
        if hi <= lo {
            return .empty
        }
        precondition(position.start <= lo, "a carve starts at or after the segment it resumes from")
        let refFirst = Int(ref.first)
        let refCount = Int(ref.count)
        let newFirst = Int32(storage.segments.count)
        var count: Int32 = 0
        var total: Int32 = 0
        var v = position.start
        for s in position.segment..<refCount {
            let seg = storage.segments[refFirst + s]
            let segLen = Int(seg.length)
            let segStart = v
            if segStart >= hi {
                break
            }
            position = ContentRefCarvePosition(segment: s, start: segStart)
            v += segLen
            let pieceLo = max(lo, segStart)
            let pieceHi = min(hi, v)
            if pieceHi <= pieceLo {
                continue
            }
            let localOffset = Int32(pieceLo - segStart)
            let pieceLen = Int32(pieceHi - pieceLo)
            storage.segments.append(Segment(
                offset: seg.offset + localOffset,
                length: pieceLen,
                inSource: seg.inSource
            ))
            count += 1
            total += pieceLen
        }
        precondition(count > 0, "a non-empty sub-range of a text node overlaps at least one of its segments")
        return ContentRef(first: newFirst, count: count, totalLength: total)
    }

    /// Copies `prefix` and `emailRef`'s bytes into the arena as one chunk, through a local buffer because they may be
    /// in the arena.
    private mutating func materializeURL(prefix: String, for emailRef: ContentRef) -> ContentRef {
        var buf = UniqueArray<UInt8>()
        for b in prefix.utf8 {
            buf.append(b)
        }
        materialize(emailRef, into: &buf)
        let offset = storage.strings.count
        for k in 0..<buf.count {
            storage.strings.append(buf[k])
        }
        return storage.intern(Chunk(offset: offset, length: buf.count, inSource: false))
    }

    /// The source extent of non-empty `ref`, from what its first byte stands for to what its last does.
    private func sourceSpan(of ref: ContentRef, image: ContentImage?) -> (start: Int, end: Int) {
        precondition(ref.count > 0 && ref.totalLength > 0, "an email address holds at least one byte")
        let firstSeg = storage.segments[Int(ref.first)]
        let lastSeg = storage.segments[Int(ref.first) + Int(ref.count) - 1]
        let first = sourceRange(of: firstSeg, local: 0, image: image)
        let last = sourceRange(of: lastSeg, local: Int(lastSeg.length) - 1, image: image)
        return (first.lowerBound, last.upperBound)
    }

    /// The source bytes that byte `local` of an address's segment `seg` stands for: a source byte, an arena byte
    /// imaged by `image`, or the character reference it was decoded from. Other arena text is punctuation, which no
    /// address holds.
    private func sourceRange(of seg: Segment, local: Int, image: ContentImage?) -> Range<Int> {
        if seg.inSource {
            let offset = Int(seg.offset) + local
            return offset..<(offset + 1)
        }
        let arena = Int(seg.offset) + local
        if let offset = image?.sourceOffset(ofArenaByte: arena) {
            return offset..<(offset + 1)
        }
        return characterReferenceSource(ofArenaByte: arena)
    }

    /// The source range of the character reference decoded into arena byte `offset` in this pass.
    private func characterReferenceSource(ofArenaByte offset: Int) -> Range<Int> {
        var lo = 0
        var hi = characterReferenceSources.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if characterReferenceSources[mid].arena.upperBound > offset {
                hi = mid
            } else {
                lo = mid + 1
            }
        }
        precondition(lo < characterReferenceSources.count && characterReferenceSources[lo].arena.contains(offset), "an address's arena byte outside the leaf's content comes from a character reference")
        return characterReferenceSources[lo].source
    }
}
