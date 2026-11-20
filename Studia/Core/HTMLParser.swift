import Foundation

// MARK: - Arbre DOM minimal

final class HTMLNode {
    enum NodeType { case element(String), text(String) }
    let type: NodeType
    var attributes: [String: String]
    var children: [HTMLNode] = []
    weak var parent: HTMLNode?

    init(type: NodeType, attributes: [String: String] = [:]) {
        self.type = type
        self.attributes = attributes
    }

    var tag: String? {
        if case .element(let t) = type { return t.lowercased() } else { return nil }
    }

    var textContent: String {
        switch type {
        case .text(let t): return t
        case .element: return children.map(\.textContent).joined()
        }
    }

    /// Texte lisible : espaces et sauts de ligne normalisés.
    var cleanedText: String {
        textContent
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    func attr(_ name: String) -> String? {
        attributes[name.lowercased()]
    }

    var href: String? { attr("href") }

    func descendants(where predicate: (HTMLNode) -> Bool) -> [HTMLNode] {
        var out: [HTMLNode] = []
        for c in children {
            if predicate(c) { out.append(c) }
            out.append(contentsOf: c.descendants(where: predicate))
        }
        return out
    }

    func elements(named tag: String) -> [HTMLNode] {
        let t = tag.lowercased()
        return descendants { $0.tag == t }
    }

    var isBlock: Bool {
        guard let t = tag else { return false }
        return ["div", "p", "li", "tr", "ul", "ol", "td", "th", "h1", "h2", "h3", "h4",
                "section", "article", "table", "dt", "dd", "header", "footer", "nav"].contains(t)
    }

    /// Texte visible découpé en lignes. Les éléments blocs et les <br> créent des sauts.
    func visibleLines() -> [String] {
        var tokens: [String] = []
        func walk(_ node: HTMLNode, lastWasBlock: Bool) {
            switch node.type {
            case .text(let t):
                let pieces = t.replacingOccurrences(of: "\u{00A0}", with: " ")
                    .components(separatedBy: .whitespacesAndNewlines)
                    .filter { !$0.isEmpty }
                if !pieces.isEmpty && lastWasBlock { tokens.append("\n") }
                tokens.append(contentsOf: pieces)
            case .element(let tag):
                if tag == "br" { tokens.append("\n"); return }
                let blockStart = node.isBlock && node.cleanedText.isEmpty == false
                for c in node.children {
                    walk(c, lastWasBlock: blockStart)
                }
                if node.isBlock { tokens.append("\n") }
            }
        }
        for c in children { walk(c, lastWasBlock: true) }
        let raw = tokens.joined()
        return raw
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    struct Link { var text: String; var href: String }
    func links() -> [Link] {
        anchors.map { Link(text: $0.cleanedText, href: $0.href ?? "") }
    }

    var anchors: [HTMLNode] {
        var out: [HTMLNode] = []
        for c in children {
            if c.tag == "a" { out.append(c) }
            out.append(contentsOf: c.anchors)
        }
        return out
    }

    func tables() -> [[HTMLNode]] {
        [descendants { $0.tag == "tr" }]
    }
}

// MARK: - Parseur HTML tolérant

enum HTMLParser {
    static func parse(_ html: String) -> HTMLNode {
        let root = HTMLNode(type: .element("html"))
        var stack: [HTMLNode] = [root]
        var text: [String] = []

        func flush() {
            guard let cur = stack.last, !text.isEmpty else { text = []; return }
            let t = decodeEntities(text.joined())
            let node = HTMLNode(type: .text(t))
            node.parent = cur
            cur.children.append(node)
            text = []
        }

        var index = html.startIndex
        let n = html.endIndex

        while index < n {
            if html[index] == "<" {
                if html[index...].prefix(4) == "<!--" {
                    flush()
                    if let end = html.range(of: "-->", range: index..<n) { index = end.upperBound } else { break }
                    continue
                }
                guard let close = html.range(of: ">", range: index..<n) else { break }
                var tagContent = String(html[html.index(after: index)..<close.lowerBound])
                index = close.upperBound
                var isClosing = false
                if tagContent.hasPrefix("/") { isClosing = true; tagContent.removeFirst() }
                tagContent = tagContent.trimmingCharacters(in: .whitespaces)
                let lowered = tagContent.lowercased()
                if lowered.hasPrefix("script") {
                    flush()
                    if let end = html.range(of: "</script", options: .caseInsensitive, range: index..<n) {
                        if let endTag = html.range(of: ">", range: end.upperBound..<n) { index = endTag.upperBound } else { index = n }
                    }
                    continue
                }
                if lowered.hasPrefix("style") {
                    flush()
                    if let end = html.range(of: "</style", options: .caseInsensitive, range: index..<n) {
                        if let endTag = html.range(of: ">", range: end.upperBound..<n) { index = endTag.upperBound } else { index = n }
                    }
                    continue
                }
                if lowered.hasPrefix("!doctype") { continue }
                let tagName = tagContent
                    .components(separatedBy: CharacterSet(charactersIn: " \t\n\r/>"))
                    .first?.lowercased() ?? ""
                guard !tagName.isEmpty, tagName.count < 30 else { continue }

                if isClosing {
                    flush()
                    if let pos = stack.lastIndex(where: { $0.tag == tagName }), pos > 0 {
                        stack.removeSubrange(pos...)
                    }
                    continue
                }
                let attrs = parseAttributes(tagContent)
                let isVoid = ["br", "img", "input", "meta", "hr", "link"].contains(tagName)
                flush()
                let node = HTMLNode(type: .element(tagName), attributes: attrs)
                node.parent = stack.last
                stack.last?.children.append(node)
                if !isVoid { stack.append(node) }
            } else {
                var end = index
                while end < n && html[end] != "<" { end = html.index(after: end) }
                text.append(String(html[index..<end]))
                index = end
            }
        }
        flush()
        return root
    }

    static func decodeEntities(_ s: String) -> String {
        s
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#39" , with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#34;", with: "\"")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&#60;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&#62;", with: ">")
            .replacingOccurrences(of: "&#233;", with: "é")
            .replacingOccurrences(of: "&#232;", with: "è")
            .replacingOccurrences(of: "&#224;", with: "à")
            .replacingOccurrences(of: "&#231;", with: "ç")
            .replacingOccurrences(of: "&#234;", with: "ê")
            .replacingOccurrences(of: "&#8217;", with: "'")
            .replacingOccurrences(of: "&#8211;", with: "–")
            .replacingOccurrences(of: "&#8230;", with: "…")
            .replacingOccurrences(of: "&eacute;", with: "é")
            .replacingOccurrences(of: "&egrave;", with: "è")
            .replacingOccurrences(of: "&agrave;", with: "à")
            .replacingOccurrences(of: "&ccedil;", with: "ç")
            .replacingOccurrences(of: "&ecirc;", with: "ê")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    static func parseAttributes(_ raw: String) -> [String: String] {
        var out: [String: String] = [:]
        let pattern = "([a-zA-Z-]+)\\s*=\\s*(\"[^\"]*\"|'[^']*'|[^\\s>]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return out }
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        for m in regex.matches(in: raw, range: range) {
            guard let keyRange = Range(m.range(at: 1), in: raw),
                  let valRange = Range(m.range(at: 2), in: raw) else { continue }
            var val = decodeEntities(String(raw[valRange]))
            if val.hasPrefix("\"") || val.hasPrefix("'") {
                val.removeFirst()
                if val.hasSuffix("\"") || val.hasSuffix("'") { val.removeLast() }
            }
            out[String(raw[keyRange]).lowercased()] = val
        }
        return out
    }
}
