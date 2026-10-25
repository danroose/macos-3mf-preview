import Foundation
import Compression

/// Minimal read-only ZIP reader (stored + deflate, ZIP64 aware). 3MF files are ZIP packages.
struct ZipArchive {
    struct Entry {
        let name: String
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    enum ZipError: Error { case notZip, corrupt, unsupported(UInt16), inflateFailed }

    private let data: Data
    private(set) var entries: [String: Entry] = [:]

    init(url: URL) throws {
        data = try Data(contentsOf: url, options: .alwaysMapped)
        try readCentralDirectory()
    }

    var names: [String] { Array(entries.keys) }

    func contains(_ name: String) -> Bool { entry(named: name) != nil }

    /// Looks an entry up by name, tolerating a leading slash and case differences.
    func entry(named name: String) -> Entry? {
        let trimmed = name.hasPrefix("/") ? String(name.dropFirst()) : name
        if let e = entries[trimmed] { return e }
        let lower = trimmed.lowercased()
        return entries.first { $0.key.lowercased() == lower }?.value
    }

    func read(_ name: String) throws -> Data? {
        guard let e = entry(named: name) else { return nil }
        return try extract(e)
    }

    // MARK: - Parsing

    private func u16(_ o: Int) -> Int { Int(data[data.startIndex + o]) | Int(data[data.startIndex + o + 1]) << 8 }
    private func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
    private func u64(_ o: Int) -> Int { u32(o) | u32(o + 4) << 32 }

    private mutating func readCentralDirectory() throws {
        let count = data.count
        guard count >= 22 else { throw ZipError.notZip }
        var eocd = -1
        var i = count - 22
        let floor = max(0, count - 22 - 65_535)
        while i >= floor {
            if u32(i) == 0x0605_4b50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError.notZip }

        var total = u16(eocd + 10)
        var cdOffset = u32(eocd + 16)
        // ZIP64 end of central directory locator sits just before the EOCD record.
        if (total == 0xFFFF || cdOffset == 0xFFFF_FFFF), eocd >= 20, u32(eocd - 20) == 0x0706_4b50 {
            let z64 = u64(eocd - 20 + 8)
            if z64 + 56 <= count, u32(z64) == 0x0606_4b50 {
                total = u64(z64 + 32)
                cdOffset = u64(z64 + 48)
            }
        }

        var p = cdOffset
        for _ in 0..<total {
            guard p + 46 <= count, u32(p) == 0x0201_4b50 else { throw ZipError.corrupt }
            let method = UInt16(u16(p + 10))
            var comp = u32(p + 20)
            var uncomp = u32(p + 24)
            let nameLen = u16(p + 28)
            let extraLen = u16(p + 30)
            let commentLen = u16(p + 32)
            var local = u32(p + 42)
            let nameStart = data.startIndex + p + 46
            let name = String(decoding: data[nameStart..<nameStart + nameLen], as: UTF8.self)

            // ZIP64 extra field: values present only for fields that overflowed, in fixed order.
            var x = p + 46 + nameLen
            let xEnd = x + extraLen
            while x + 4 <= xEnd {
                let id = u16(x), size = u16(x + 2)
                if id == 0x0001 {
                    var f = x + 4
                    if uncomp == 0xFFFF_FFFF { uncomp = u64(f); f += 8 }
                    if comp == 0xFFFF_FFFF { comp = u64(f); f += 8 }
                    if local == 0xFFFF_FFFF { local = u64(f) }
                }
                x += 4 + size
            }

            entries[name] = Entry(name: name, method: method, compressedSize: comp,
                                  uncompressedSize: uncomp, localHeaderOffset: local)
            p += 46 + nameLen + extraLen + commentLen
        }
    }

    private func extract(_ e: Entry) throws -> Data {
        let h = e.localHeaderOffset
        guard h + 30 <= data.count, u32(h) == 0x0403_4b50 else { throw ZipError.corrupt }
        let start = h + 30 + u16(h + 26) + u16(h + 28)
        guard start + e.compressedSize <= data.count else { throw ZipError.corrupt }
        let src = data[(data.startIndex + start)..<(data.startIndex + start + e.compressedSize)]

        switch e.method {
        case 0:
            return Data(src)
        case 8:
            var out = Data(count: e.uncompressedSize)
            let written = out.withUnsafeMutableBytes { dst in
                src.withUnsafeBytes { s in
                    compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, e.uncompressedSize,
                                              s.bindMemory(to: UInt8.self).baseAddress!, e.compressedSize,
                                              nil, COMPRESSION_ZLIB)
                }
            }
            guard written == e.uncompressedSize || (written > 0 && e.uncompressedSize > 0) else {
                throw ZipError.inflateFailed
            }
            if written < e.uncompressedSize { out.count = written }
            return out
        default:
            throw ZipError.unsupported(e.method)
        }
    }
}
