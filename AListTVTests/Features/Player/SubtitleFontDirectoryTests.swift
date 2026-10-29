import CoreText
import XCTest
@testable import AListTV

final class SubtitleFontDirectoryTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("SubtitleFontDirectoryTests.\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        try super.tearDownWithError()
    }

    private func bundledFont() throws -> URL {
        try XCTUnwrap(Bundle.main.url(forResource: "NotoSansCJKsc-Regular", withExtension: "otf"))
    }

    func testRenamedFontJoinsLibassDefaultFamilyAndKeepsCJKGlyphs() throws {
        let renamed = try XCTUnwrap(SubtitleFontDirectory.renamingFamily(of: Data(contentsOf: bundledFont()), to: SubtitleFontDirectory.libassDefaultFamily))

        let descriptor = try XCTUnwrap((CTFontManagerCreateFontDescriptorsFromData(renamed as CFData) as? [CTFontDescriptor])?.first)
        XCTAssertEqual(CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String, "Helvetica Neue")
        let font = CTFontCreateWithFontDescriptor(descriptor, 20, nil)
        var characters: [UniChar] = Array("公主".utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        XCTAssertTrue(CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count))
    }

    func testPrepareWritesTheRenamedFontOnce() throws {
        let fontsDirectory = try XCTUnwrap(SubtitleFontDirectory.prepare(bundledFont: bundledFont(), cachesDirectory: directory))
        let files = try FileManager.default.contentsOfDirectory(at: fontsDirectory, includingPropertiesForKeys: [.contentModificationDateKey])
        XCTAssertEqual(files.map(\.lastPathComponent), ["NotoSansCJKsc-Regular-libass-default-v1.otf"])
        let written = try files[0].resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate

        XCTAssertEqual(SubtitleFontDirectory.prepare(bundledFont: try bundledFont(), cachesDirectory: directory), fontsDirectory)
        XCTAssertEqual(try files[0].resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, written)
    }

    func testRenamingRejectsDataWithoutANameTable() {
        XCTAssertNil(SubtitleFontDirectory.renamingFamily(of: Data([0, 1, 0, 0, 0, 0]), to: "Helvetica Neue"))
        XCTAssertNil(SubtitleFontDirectory.renamingFamily(of: Data([0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), to: "Helvetica Neue"))
    }
}
