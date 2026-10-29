import Foundation

/// Fonts for VLC's ASS/SSA renderer (libass), which ignores `--freetype-font`.
///
/// When a script names a font the device lacks (e.g. `方正黑体_GBK`), libass
/// uses its default family "Helvetica Neue", which has no CJK glyphs, and the
/// fallback CoreText then suggests (PingFang UI) is a private font FreeType
/// cannot open, so every Chinese glyph renders as a box. libass also loads each
/// font in `--ssa-fontsdir`; a copy of the bundled CJK font renamed to that
/// default family joins it there and supplies the missing glyphs.
enum SubtitleFontDirectory {
    static let libassDefaultFamily = "Helvetica Neue"

    /// Returns the directory to pass as `--ssa-fontsdir`, writing the renamed
    /// font into `cachesDirectory` the first time.
    static func prepare(bundledFont: URL, cachesDirectory: URL) -> URL? {
        let directory = cachesDirectory.appendingPathComponent("SubtitleFonts", isDirectory: true)
        let fontURL = directory.appendingPathComponent("\(bundledFont.deletingPathExtension().lastPathComponent)-libass-default-v1.\(bundledFont.pathExtension)")
        if FileManager.default.fileExists(atPath: fontURL.path) { return directory }
        do {
            let font = try Data(contentsOf: bundledFont, options: .mappedIfSafe)
            guard let renamed = renamingFamily(of: font, to: libassDefaultFamily) else { return nil }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try renamed.write(to: fontURL, options: .atomic)
            return directory
        } catch {
            return nil
        }
    }

    /// Rewrites the family, full and typographic family names (name IDs 1, 4
    /// and 16) of an OpenType font. The rebuilt `name` table is appended and
    /// its table record repointed; the rest of the font is untouched.
    static func renamingFamily(of font: Data, to family: String) -> Data? {
        var bytes = [UInt8](font)
        func u16(_ offset: Int) -> Int { Int(bytes[offset]) << 8 | Int(bytes[offset + 1]) }
        func u32(_ offset: Int) -> Int { u16(offset) << 16 | u16(offset + 2) }
        func putU16(_ value: Int, into buffer: inout [UInt8]) { buffer += [UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)] }
        func setU32(_ value: Int, at offset: Int) {
            for index in 0..<4 { bytes[offset + index] = UInt8(value >> (24 - index * 8) & 0xFF) }
        }

        guard bytes.count >= 12 else { return nil }
        let tableCount = u16(4)
        guard bytes.count >= 12 + tableCount * 16,
              let tableRecord = (0..<tableCount).map({ 12 + $0 * 16 }).first(where: { Array(bytes[$0..<$0 + 4]) == Array("name".utf8) }) else { return nil }
        let tableOffset = u32(tableRecord + 8)
        let tableLength = u32(tableRecord + 12)
        guard tableLength >= 6, tableOffset + tableLength <= bytes.count else { return nil }
        let recordCount = u16(tableOffset + 2)
        let storageOffset = tableOffset + u16(tableOffset + 4)
        guard 6 + recordCount * 12 <= tableLength else { return nil }

        let utf16Family = family.utf16.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] }
        var records: [UInt8] = []
        var strings: [UInt8] = []
        for index in 0..<recordCount {
            let record = tableOffset + 6 + index * 12
            let value: [UInt8]
            if [1, 4, 16].contains(u16(record + 6)) {
                // Macintosh-platform names are single-byte; the rest are UTF-16BE.
                value = u16(record) == 1 ? Array(family.utf8) : utf16Family
            } else {
                let start = storageOffset + u16(record + 10)
                let end = start + u16(record + 8)
                guard end <= bytes.count else { return nil }
                value = Array(bytes[start..<end])
            }
            records += bytes[record..<record + 8]
            putU16(value.count, into: &records)
            putU16(strings.count, into: &records)
            strings += value
        }

        var table: [UInt8] = []
        putU16(0, into: &table)
        putU16(recordCount, into: &table)
        putU16(6 + recordCount * 12, into: &table)
        table += records + strings
        let newLength = table.count
        table += [UInt8](repeating: 0, count: (4 - newLength % 4) % 4)
        let checksum = stride(from: 0, to: table.count, by: 4).reduce(0) { sum, offset in
            (sum + (Int(table[offset]) << 24 | Int(table[offset + 1]) << 16 | Int(table[offset + 2]) << 8 | Int(table[offset + 3]))) & 0xFFFF_FFFF
        }

        bytes += [UInt8](repeating: 0, count: (4 - bytes.count % 4) % 4)
        let newOffset = bytes.count
        bytes += table
        setU32(checksum, at: tableRecord + 4)
        setU32(newOffset, at: tableRecord + 8)
        setU32(newLength, at: tableRecord + 12)
        return Data(bytes)
    }
}
