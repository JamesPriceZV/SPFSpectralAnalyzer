import Foundation

struct ZipEntry: Sendable {
    let path: String
    let data: Data
}

struct ZipArchiveWriter {
    static func archive(entries: [ZipEntry]) throws -> Data {
        var output = Data()
        var centralDirectory = Data()

        for entry in entries {
            let fileNameData = Data(entry.path.utf8)
            let crc = CRC32.checksum(entry.data)
            let localHeaderOffset = output.count

            output.append(UInt32(0x04034b50).littleEndianData)
            output.append(UInt16(20).littleEndianData)
            output.append(UInt16(0).littleEndianData)
            output.append(UInt16(0).littleEndianData)
            output.append(UInt16(0).littleEndianData)
            output.append(UInt16(0).littleEndianData)
            output.append(UInt32(crc).littleEndianData)
            output.append(UInt32(entry.data.count).littleEndianData)
            output.append(UInt32(entry.data.count).littleEndianData)
            output.append(UInt16(fileNameData.count).littleEndianData)
            output.append(UInt16(0).littleEndianData)
            output.append(fileNameData)
            output.append(entry.data)

            centralDirectory.append(UInt32(0x02014b50).littleEndianData)
            centralDirectory.append(UInt16(20).littleEndianData)
            centralDirectory.append(UInt16(20).littleEndianData)
            centralDirectory.append(UInt16(0).littleEndianData)
            centralDirectory.append(UInt16(0).littleEndianData)
            centralDirectory.append(UInt16(0).littleEndianData)
            centralDirectory.append(UInt16(0).littleEndianData)
            centralDirectory.append(UInt32(crc).littleEndianData)
            centralDirectory.append(UInt32(entry.data.count).littleEndianData)
            centralDirectory.append(UInt32(entry.data.count).littleEndianData)
            centralDirectory.append(UInt16(fileNameData.count).littleEndianData)
            centralDirectory.append(UInt16(0).littleEndianData)
            centralDirectory.append(UInt16(0).littleEndianData)
            centralDirectory.append(UInt16(0).littleEndianData)
            centralDirectory.append(UInt16(0).littleEndianData)
            centralDirectory.append(UInt32(0).littleEndianData)
            centralDirectory.append(UInt32(localHeaderOffset).littleEndianData)
            centralDirectory.append(fileNameData)
        }

        let centralDirectoryOffset = output.count
        output.append(centralDirectory)
        let centralDirectorySize = centralDirectory.count

        output.append(UInt32(0x06054b50).littleEndianData)
        output.append(UInt16(0).littleEndianData)
        output.append(UInt16(0).littleEndianData)
        output.append(UInt16(entries.count).littleEndianData)
        output.append(UInt16(entries.count).littleEndianData)
        output.append(UInt32(centralDirectorySize).littleEndianData)
        output.append(UInt32(centralDirectoryOffset).littleEndianData)
        output.append(UInt16(0).littleEndianData)

        return output
    }
}

struct OOXMLWriter {
    static func writeDocx(report: String, to url: URL) throws {
        let documentXML = buildDocumentXML(report: report)
        let contentTypes = """
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">
  <Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>
  <Default Extension=\"xml\" ContentType=\"application/xml\"/>
  <Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/>
</Types>
"""
        let rels = """
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">
  <Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/>
</Relationships>
"""

        let entries = [
            ZipEntry(path: "[Content_Types].xml", data: Data(contentTypes.utf8)),
            ZipEntry(path: "_rels/.rels", data: Data(rels.utf8)),
            ZipEntry(path: "word/document.xml", data: Data(documentXML.utf8))
        ]

        let archive = try ZipArchiveWriter.archive(entries: entries)
        try archive.write(to: url, options: .atomic)
    }

    static func writeXlsx(header: [String], rows: [[String]], to url: URL) throws {
        let sheetXML = buildWorksheetXML(header: header, rows: rows)
        let contentTypes = """
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">
  <Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>
  <Default Extension=\"xml\" ContentType=\"application/xml\"/>
  <Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/>
  <Override PartName=\"/xl/worksheets/sheet1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>
</Types>
"""
        let rels = """
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">
  <Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/>
</Relationships>
"""
        let workbook = """
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">
  <sheets>
    <sheet name=\"Spectra\" sheetId=\"1\" r:id=\"rId1\"/>
  </sheets>
</workbook>
"""
        let workbookRels = """
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">
  <Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/>
</Relationships>
"""

        let entries = [
            ZipEntry(path: "[Content_Types].xml", data: Data(contentTypes.utf8)),
            ZipEntry(path: "_rels/.rels", data: Data(rels.utf8)),
            ZipEntry(path: "xl/workbook.xml", data: Data(workbook.utf8)),
            ZipEntry(path: "xl/_rels/workbook.xml.rels", data: Data(workbookRels.utf8)),
            ZipEntry(path: "xl/worksheets/sheet1.xml", data: Data(sheetXML.utf8))
        ]

        let archive = try ZipArchiveWriter.archive(entries: entries)
        try archive.write(to: url, options: .atomic)
    }

    private static func buildDocumentXML(report: String) -> String {
        let lines = report.split(separator: "\n", omittingEmptySubsequences: false)
        var paragraphs: [String] = []
        for line in lines {
            let text = xmlEscaped(String(line))
            if text.isEmpty {
                paragraphs.append("<w:p/>")
            } else {
                paragraphs.append("<w:p><w:r><w:t>\(text)</w:t></w:r></w:p>")
            }
        }

        return """
<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>
<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">
  <w:body>
    \(paragraphs.joined(separator: "\n"))
    <w:sectPr/>
  </w:body>
</w:document>
"""
    }

    private static func buildWorksheetXML(header: [String], rows: [[String]]) -> String {
        var rowXML: [String] = []
        rowXML.append(buildRowXML(index: 1, values: header))
        for (rowIndex, row) in rows.enumerated() {
            rowXML.append(buildRowXML(index: rowIndex + 2, values: row))
        }

        return """
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">
  <sheetData>
    \(rowXML.joined(separator: "\n"))
  </sheetData>
</worksheet>
"""
    }

    private static func buildRowXML(index: Int, values: [String]) -> String {
        var cells: [String] = []
        for (columnIndex, value) in values.enumerated() {
            let cellRef = "\(columnName(columnIndex + 1))\(index)"
            if Double(value) != nil {
                cells.append("<c r=\"\(cellRef)\" t=\"n\"><v>\(value)</v></c>")
            } else {
                let escaped = xmlEscaped(value)
                cells.append("<c r=\"\(cellRef)\" t=\"inlineStr\"><is><t>\(escaped)</t></is></c>")
            }
        }
        return "<row r=\"\(index)\">\(cells.joined())</row>"
    }

    private static func columnName(_ index: Int) -> String {
        var index = index
        var name = ""
        while index > 0 {
            let remainder = (index - 1) % 26
            name = String(UnicodeScalar(65 + remainder)!) + name
            index = (index - 1) / 26
        }
        return name
    }

    private static func xmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

private struct CRC32 {
    private static let table: [UInt32] = {
        (0..<256).map { i in
            var crc = UInt32(i)
            for _ in 0..<8 {
                if crc & 1 == 1 {
                    crc = 0xEDB88320 ^ (crc >> 1)
                } else {
                    crc >>= 1
                }
            }
            return crc
        }
    }()

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let idx = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = table[idx] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}

private extension FixedWidthInteger {
    var littleEndianData: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<Self>.size)
    }
}
