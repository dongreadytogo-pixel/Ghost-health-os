import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import GhostlyCore

/// The XML half of SUBTITLE Cover: reads the exported project in place,
/// anchors the new pop-up titles as connected clips (never under a bare
/// spine — FCP silently drops those), inserts them *before* any
/// filter/marker children (DTD order — wrong order fails the whole import
/// with no warning), and self-validates before writing.
extension SubtitleCover {
    // MARK: Public API

    /// Preview: (project name, pairs) without writing anything.
    public static func analyze(path: String) throws -> (name: String, pairs: [Pair]) {
        let built = try build(path: path, overrides: [:])
        return (built.name, built.pairs)
    }

    /// Build + validate + write. `overrides[index] = (white, orange)` uses
    /// the editor's corrected text; both empty = skip that subtitle.
    @discardableResult
    public static func run(path: String,
                           overrides: [Int: (String, String)] = [:],
                           outPath: String? = nil) throws -> Output {
        let built = try build(path: path, overrides: overrides)
        let problems = validate(built.pairs)
        guard problems.isEmpty else {
            throw StudioError.validationFailure(
                detail: "ตรวจพบข้อผิดพลาด ไม่สร้างไฟล์:\n- " + problems.prefix(10).joined(separator: "\n- "))
        }
        let destination = outPath ?? FileManager.default.currentDirectoryPath + "/\(built.name)_cover.fcpxml"
        let body = built.document.rootElement()?.xmlString ?? ""
        let text = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE fcpxml>\n" + body + "\n"
        try text.write(toFile: destination, atomically: true, encoding: .utf8)
        return Output(coverCount: built.pairs.count, outPath: destination, pairs: built.pairs)
    }

    /// Pre-flight checks — empty list = 100% pass. Mirrors the original:
    /// no frame overflow, sizes in range, the two lines never touch.
    public static func validate(_ pairs: [Pair]) -> [String] {
        var problems: [String] = []
        for (i, pair) in pairs.enumerated() {
            let n = i + 1
            if pair.orange.isEmpty {
                problems.append("#\(n) บรรทัดล่างว่าง")
                continue
            }
            if Double(charLen(pair.orange) * pair.orangeSize) > maxUnits {
                problems.append("#\(n) ส้ม '\(pair.orange)' ล้นเฟรม (\(charLen(pair.orange))×\(pair.orangeSize)>\(Int(maxUnits)))")
            }
            if !(hardMin...sizeMax).contains(pair.orangeSize) {
                problems.append("#\(n) ขนาดส้ม \(pair.orangeSize) นอกเกณฑ์ [\(hardMin),\(sizeMax)]")
            }
            if !pair.white.isEmpty {
                if Double(charLen(pair.white) * pair.whiteSize) > maxUnits {
                    problems.append("#\(n) ขาว '\(pair.white)' ล้นเฟรม (\(charLen(pair.white))×\(pair.whiteSize)>\(Int(maxUnits)))")
                }
                if !(hardMin...sizeMax).contains(pair.whiteSize) {
                    problems.append("#\(n) ขนาดขาว \(pair.whiteSize) นอกเกณฑ์ [\(hardMin),\(sizeMax)]")
                }
            }
        }
        return problems
    }

    /// Debug dump (handoff §8 recommendation): every title with its effect
    /// name, fontFace, bold flag, and text — so mismatched files can be
    /// diagnosed without another round trip.
    public static func listTitles(path: String) throws -> [String] {
        let document = try loadDocument(path: path)
        var effectNames: [String: String] = [:]
        for node in try document.nodes(forXPath: "//effect") {
            guard let effect = node as? XMLElement else { continue }
            effectNames[attr(effect, "id") ?? ""] = attr(effect, "name") ?? ""
        }
        var lines: [String] = []
        for node in try document.nodes(forXPath: "//title") {
            guard let title = node as? XMLElement else { continue }
            let style = styleElement(for: title, in: document)
            let text = joinedText(title)
            let effect = effectNames[attr(title, "ref") ?? ""] ?? (attr(title, "ref") ?? "?")
            lines.append("effect=\(effect) fontFace=\(attr(style, "fontFace") ?? "-") "
                + "bold=\(attr(style, "bold") ?? "-") font=\(attr(style, "font") ?? "-") "
                + "text=\(scalarPrefix(text, 40))")
        }
        return lines
    }

    // MARK: Build

    struct Built {
        let document: XMLDocument
        let name: String
        let pairs: [Pair]
    }

    static func loadDocument(path: String) throws -> XMLDocument {
        var filePath = path
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: filePath, isDirectory: &isDirectory),
           isDirectory.boolValue, filePath.hasSuffix(".fcpxmld") {
            // .fcpxmld is a package folder; the real XML lives inside.
            filePath = (filePath as NSString).appendingPathComponent("Info.fcpxml")
        }
        guard FileManager.default.fileExists(atPath: filePath) else {
            throw StudioError.notFound(entity: "ไฟล์", id: filePath)
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        return try XMLDocument(data: data, options: [.nodePreserveWhitespace])
    }

    static func build(path: String, overrides: [Int: (String, String)]) throws -> Built {
        let document = try loadDocument(path: path)

        // The pop-up template must exist in the file: new titles reference it.
        var popupID: String?
        for node in try document.nodes(forXPath: "//effect") {
            guard let effect = node as? XMLElement else { continue }
            if attr(effect, "name") == "Pop-up Text" { popupID = attr(effect, "id"); break }
        }
        guard let popupID else {
            throw StudioError.validationFailure(detail:
                "ไม่พบเทมเพลต 'Pop-up Text' ในไฟล์ — โปรเจกต์ต้นทางต้องมี title จากเทมเพลต Pop-up Text อย่างน้อยหนึ่งอัน เพื่อให้โปรแกรมใช้อ้างอิงสร้างไฮไลต์")
        }

        var timebase = 2500
        if let format = try document.nodes(forXPath: "//format").first as? XMLElement,
           let frameDuration = attr(format, "frameDuration") {
            let parts = frameDuration.trimmingCharacters(in: CharacterSet(charactersIn: "s")).split(separator: "/")
            if parts.count == 2, let denom = Int(parts[1]) { timebase = denom }
        }
        let projectElement = try document.nodes(forXPath: "//project").first as? XMLElement
        let projectName = safeName(projectElement.flatMap { attr($0, "name") })

        var pairs: [Pair] = []
        for (index, node) in try document.nodes(forXPath: "//title").enumerated() {
            guard let title = node as? XMLElement,
                  let text = subText(title, in: document) else { continue }

            // Walk up through nested spines (accumulating their offsets)
            // to the element the cover can anchor to.
            var offset = seconds(attr(title, "offset"))
            var child: XMLNode = title
            var parent = child.parent as? XMLElement
            while let p = parent, p.name == "spine" {
                offset += seconds(attr(p, "offset"))
                child = p
                parent = p.parent as? XMLElement
            }
            guard let anchor = parent, anchorable.contains(anchor.name ?? "") else { continue }

            let white: String
            let orange: String
            if let override = overrides[index] {
                white = override.0.trimmingCharacters(in: .whitespaces)
                orange = override.1.trimmingCharacters(in: .whitespaces)
                if white.isEmpty && orange.isEmpty { continue }   // deleted by the editor
            } else {
                (white, orange) = splitTwo(text)
            }

            let offsetString = rational(offset, timebase: timebase)
            let duration = attr(title, "duration") ?? "30000/150000s"
            let n = pairs.count

            // DTD order: new titles must land before filters/markers.
            let insertAt = (anchor.children ?? []).firstIndex {
                filters.contains($0.name ?? "")
            } ?? anchor.childCount

            if white.isEmpty {
                let so = fit(orange)
                let y = bottomEdge + lineHalf * Double(so) + singleRaise
                let element = makeLine(orange, isWhite: false, ref: popupID,
                                       offset: offsetString, duration: duration,
                                       styleID: "co\(n)", lane: laneOrange, size: so,
                                       position: String(format: "%@ %.1f", xOrange, y))
                anchor.insertChild(element, at: insertAt)
                pairs.append(Pair(index: index, white: "", whiteSize: 0, orange: orange, orangeSize: so))
                continue
            }

            let (sw, so) = balance(fit(white), fit(orange))
            let gap = lineHalf * Double(sw + so) + gapPad
            let orangeY = bottomEdge + lineHalf * Double(so)
            let whiteY = orangeY + gap
            let whiteElement = makeLine(white, isWhite: true, ref: popupID,
                                        offset: offsetString, duration: duration,
                                        styleID: "cw\(n)", lane: laneWhite, size: sw,
                                        position: String(format: "%@ %.1f", xWhite, whiteY))
            let orangeElement = makeLine(orange, isWhite: false, ref: popupID,
                                         offset: offsetString, duration: duration,
                                         styleID: "co\(n)", lane: laneOrange, size: so,
                                         position: String(format: "%@ %.1f", xOrange, orangeY))
            anchor.insertChild(orangeElement, at: insertAt)
            anchor.insertChild(whiteElement, at: insertAt)
            pairs.append(Pair(index: index, white: white, whiteSize: sw, orange: orange, orangeSize: so))
        }

        guard !pairs.isEmpty else {
            throw StudioError.validationFailure(detail:
                "ไม่พบซับไตเติ้ลธรรมดา (title ที่ไม่ใช่ตัวหนา) ในไฟล์นี้ — ลอง `ghostly cover <ไฟล์> --list-titles` เพื่อดูว่าโปรแกรมเห็น title อะไรบ้าง")
        }
        return Built(document: document, name: projectName, pairs: pairs)
    }

    // MARK: Subtitle detection

    /// A plain subtitle = a title that is not a highlight. Highlights /
    /// price tags / CTAs in this workflow are bold **and heavy-faced**;
    /// FCP Custom titles sometimes carry bold="1" with a Light/ExtraLight
    /// face, so bold alone is not enough (handoff §8 fix).
    static func subText(_ title: XMLElement, in document: XMLDocument) -> String? {
        guard let style = styleElement(for: title, in: document) else { return nil }
        if attr(style, "bold") == "1" && isHeavyFace(attr(style, "fontFace")) { return nil }
        let name = attr(title, "name") ?? ""
        if name.hasSuffix(" - COVER") { return nil }   // our own earlier output
        let text = joinedText(title)
        guard !text.isEmpty, !text.hasPrefix("**"), !text.contains("ผลลัพธ์อาจเปลี่ยนแปลง") else { return nil }
        return text
    }

    static func isHeavyFace(_ face: String?) -> Bool {
        guard let face, !face.isEmpty else { return true }   // bold=1 + no face → heavy
        let light: Set<String> = ["Light", "ExtraLight", "Ultralight", "UltraLight",
                                  "Thin", "Regular", "Medium Light"]
        return !light.contains(face)
    }

    /// The title's text style: inline `text-style-def` first, else resolve
    /// the `<text-style ref=…>` through defs elsewhere in the document
    /// (handoff §8 fallback for Custom-title structures).
    static func styleElement(for title: XMLElement, in document: XMLDocument) -> XMLElement? {
        if let inline = (try? title.nodes(forXPath: ".//text-style-def/text-style"))?.first as? XMLElement {
            return inline
        }
        guard let refNode = (try? title.nodes(forXPath: ".//text/text-style"))?.first as? XMLElement,
              let ref = attr(refNode, "ref") else { return nil }
        let defs = (try? document.nodes(forXPath: "//text-style-def[@id='\(ref)']/text-style")) ?? []
        return defs.first as? XMLElement
    }

    static func joinedText(_ title: XMLElement) -> String {
        let nodes = (try? title.nodes(forXPath: ".//text/text-style")) ?? []
        return nodes.compactMap { $0.stringValue }.joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Element factory (parameter keys copied from real FCP output)

    static func makeLine(_ text: String, isWhite: Bool, ref: String,
                         offset: String, duration: String,
                         styleID: String, lane: Int, size: Int,
                         position: String) -> XMLElement {
        let title = element("title", [
            ("ref", ref), ("lane", String(lane)), ("offset", offset),
            ("name", scalarPrefix(text + " - COVER", 40)),
            ("start", "3600s"), ("duration", duration),
        ])
        let kr = "9999/3296420352/3296420351/3001891230/3296421440"
        func param(_ name: String, _ key: String, _ value: String) {
            title.addChild(element("param", [("name", name), ("key", key), ("value", value)]))
        }
        param("Build In", "9999/3001891228/2/101", "1")
        param("Build Out", "9999/3001891228/2/102", "1")
        param("Position", kr + "/1/100/101", position)
        param("Size", kr + "/5/3336715400/3", String(size))
        param("Speed", "9999/3296420352/3296420351/4/3296420944/201", "14")
        param("Speed", "9999/3296420352/3296420351/4/3296420952/200", "15")
        param("Global Scale", "9999/3296421148/3/3296421147/1", "0.05")
        param("Global Angle", "9999/3296421148/3/3296421147/2", "90")
        param("Global Position", "9999/3296421148/3/3296421147/3", globalPos)

        let textElement = element("text", [])
        let styleRef = element("text-style", [("ref", styleID)])
        styleRef.stringValue = text
        textElement.addChild(styleRef)
        title.addChild(textElement)

        var attrs: [(String, String)] = [
            ("font", "Anakotmai"), ("fontSize", String(size)),
            ("fontColor", isWhite ? cWhite : cOrange), ("bold", "1"),
            ("shadowColor", "0 0 0 1"), ("shadowOffset", "1 315"),
            ("shadowBlurRadius", "9.12"), ("alignment", "center"),
            ("lineSpacing", "-30"),
        ]
        if !isWhite {
            attrs.append(("strokeColor", "1 1 1 1"))
            attrs.append(("strokeWidth", "-5"))
        }
        let def = element("text-style-def", [("id", styleID)])
        def.addChild(element("text-style", attrs))
        title.addChild(def)
        return title
    }

    // MARK: XML utilities

    static func attr(_ e: XMLElement?, _ name: String) -> String? {
        e?.attribute(forName: name)?.stringValue
    }

    static func element(_ name: String, _ attrs: [(String, String)]) -> XMLElement {
        let e = XMLElement(name: name)
        for (key, value) in attrs {
            e.addAttribute(XMLNode.attribute(withName: key, stringValue: value) as! XMLNode)
        }
        return e
    }
}
