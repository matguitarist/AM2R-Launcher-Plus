import Compression
import Foundation

/// Applies xdelta3 patches (VCDIFF, RFC 3284) in pure Swift, so the app needs no xdelta install.
/// Supports what xdelta3 writes: the default code table, an application header, xdelta's
/// Adler-32 window checksums, and LZMA secondary compression (decoded with Apple's Compression).
public enum VCDiff {
    public enum Failure: Error, Equatable, Sendable {
        case notVCDiff
        case unsupported(String)
        case truncated
        case corrupt(String)
        case checksumMismatch(window: Int)
    }

    /// Patches `source` with `patch` and writes the result to `output`.
    /// `progress` gets the fraction of the patch consumed (0...1).
    public static func apply(source: URL, patch: URL, output: URL, progress: ((Double) -> Void)? = nil) throws {
        let sourceData = try Data(contentsOf: source, options: .alwaysMapped)
        let patchData = try Data(contentsOf: patch, options: .alwaysMapped)
        FileManager.default.createFile(atPath: output.path, contents: nil)
        let handle = try FileHandle(forWritingTo: output)
        defer { try? handle.close() }
        try decode(source: sourceData, patch: patchData, progress: progress) { window in
            try handle.write(contentsOf: window)
        }
    }

    /// Decodes in memory (tests and small files).
    public static func apply(source: Data, patch: Data) throws -> Data {
        var result = Data()
        try decode(source: source, patch: patch, progress: nil) { result.append($0) }
        return result
    }

    // MARK: Decoder

    private static let vcdSecondary: UInt8 = 0x01
    private static let vcdCodeTable: UInt8 = 0x02
    private static let vcdAppHeader: UInt8 = 0x04
    private static let vcdSource: UInt8 = 0x01
    private static let vcdTarget: UInt8 = 0x02
    private static let vcdAdler32: UInt8 = 0x04
    private static let lzmaID: UInt8 = 2

    static func decode(source: Data, patch: Data, progress: ((Double) -> Void)?, emit: (Data) throws -> Void) throws {
        var reader = ByteReader(data: patch)
        guard try reader.byte() == 0xD6, try reader.byte() == 0xC3, try reader.byte() == 0xC4 else { throw Failure.notVCDiff }
        guard try reader.byte() == 0 else { throw Failure.unsupported("VCDIFF version") }
        let indicator = try reader.byte()
        var secondary: UInt8?
        if indicator & vcdSecondary != 0 {
            secondary = try reader.byte()
            guard secondary == lzmaID else { throw Failure.unsupported("secondary compressor \(secondary!)") }
        }
        if indicator & vcdCodeTable != 0 { throw Failure.unsupported("custom code table") }
        if indicator & vcdAppHeader != 0 {
            let length = try reader.int()
            try reader.skip(length)
        }

        let table = CodeTable.standard
        // xdelta3 keeps one LZMA stream per section type for the whole patch, flushed (never ended) per window.
        let dataStream = secondary == nil ? nil : try LZMAStream()
        let instStream = secondary == nil ? nil : try LZMAStream()
        let addrStream = secondary == nil ? nil : try LZMAStream()
        var previousTarget = Data()
        var windowIndex = 0
        while !reader.isAtEnd {
            let windowIndicator = try reader.byte()
            var segment = Data()
            if windowIndicator & (vcdSource | vcdTarget) != 0 {
                let length = try reader.int()
                let offset = try reader.int()
                if windowIndicator & vcdSource != 0 {
                    guard offset + length <= source.count else { throw Failure.corrupt("source window outside the source file") }
                    segment = source.subdata(in: source.startIndex + offset ..< source.startIndex + offset + length)
                } else {
                    guard offset + length <= previousTarget.count else { throw Failure.unsupported("target window from older windows") }
                    segment = previousTarget.subdata(in: offset ..< offset + length)
                }
            }
            _ = try reader.int() // delta encoding length
            let targetLength = try reader.int()
            let deltaIndicator = try reader.byte()
            let dataLength = try reader.int()
            let instLength = try reader.int()
            let addrLength = try reader.int()
            var checksum: UInt32?
            if windowIndicator & vcdAdler32 != 0 {
                checksum = try reader.uint32BigEndian()
            }
            var dataSection = try reader.take(dataLength)
            var instSection = try reader.take(instLength)
            var addrSection = try reader.take(addrLength)
            if let dataStream, let instStream, let addrStream {
                if deltaIndicator & 0x01 != 0 { dataSection = try dataStream.decode(section: dataSection) }
                if deltaIndicator & 0x02 != 0 { instSection = try instStream.decode(section: instSection) }
                if deltaIndicator & 0x04 != 0 { addrSection = try addrStream.decode(section: addrSection) }
            } else if deltaIndicator != 0 {
                throw Failure.unsupported("compressed sections without a secondary compressor")
            }

            let target = try decodeWindow(segment: segment, targetLength: targetLength, table: table,
                                          data: dataSection, inst: instSection, addr: addrSection)
            if let checksum, adler32(target) != checksum { throw Failure.checksumMismatch(window: windowIndex) }
            try emit(target)
            previousTarget = target
            windowIndex += 1
            progress?(Double(reader.offset) / Double(max(patch.count, 1)))
        }
    }

    private static func decodeWindow(segment: Data, targetLength: Int, table: CodeTable,
                                     data: Data, inst: Data, addr: Data) throws -> Data {
        var target = [UInt8](repeating: 0, count: targetLength)
        let source = [UInt8](segment)
        let sourceLength = source.count
        var dataReader = ByteReader(data: data)
        var instReader = ByteReader(data: inst)
        var addrReader = ByteReader(data: addr)
        var cache = AddressCache()
        var position = 0

        func run(_ instruction: CodeTable.Instruction, size givenSize: Int) throws {
            var size = givenSize
            if size == 0 { size = try instReader.int() }
            guard position + size <= targetLength else { throw Failure.corrupt("instruction writes past the window") }
            switch instruction.kind {
            case .noop:
                return
            case .add:
                let bytes = try dataReader.take(size)
                bytes.withUnsafeBytes { raw in
                    for i in 0..<size { target[position + i] = raw[i] }
                }
            case .run:
                let byte = try dataReader.byte()
                for i in 0..<size { target[position + i] = byte }
            case .copy:
                let here = sourceLength + position
                let address = try cache.decode(mode: instruction.mode, here: here, reader: &addrReader)
                guard address < here else { throw Failure.corrupt("copy address ahead of the cursor") }
                for i in 0..<size {
                    let from = address + i
                    target[position + i] = from < sourceLength ? source[from] : target[from - sourceLength]
                }
            }
            position += size
        }

        while !instReader.isAtEnd {
            let entry = table.entries[Int(try instReader.byte())]
            if entry.first.kind != .noop { try run(entry.first, size: entry.firstSize) }
            if entry.second.kind != .noop { try run(entry.second, size: entry.secondSize) }
        }
        guard position == targetLength else { throw Failure.corrupt("window decoded to \(position) of \(targetLength) bytes") }
        return Data(target)
    }

    static func adler32(_ data: Data) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0
        data.withUnsafeBytes { raw in
            var index = 0
            let count = raw.count
            while index < count {
                let end = min(index + 5552, count) // largest block before the sums can overflow
                while index < end {
                    a += UInt32(raw[index])
                    b += a
                    index += 1
                }
                a %= 65521
                b %= 65521
            }
        }
        return (b << 16) | a
    }
}

/// One of xdelta3's LZMA secondary streams: an .xz stream that continues across windows.
/// A section holds the decoded size (VCDIFF integer) followed by the next compressed bytes.
final class LZMAStream {
    private var stream = compression_stream(dst_ptr: UnsafeMutablePointer<UInt8>(bitPattern: 1)!, dst_size: 0,
                                            src_ptr: UnsafePointer<UInt8>(bitPattern: 1)!, src_size: 0, state: nil)

    init() throws {
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_LZMA) == COMPRESSION_STATUS_OK else {
            throw VCDiff.Failure.unsupported("LZMA decoder unavailable")
        }
    }

    deinit { compression_stream_destroy(&stream) }

    func decode(section: Data) throws -> Data {
        var reader = ByteReader(data: section)
        let size = try reader.int()
        guard size > 0 else { throw VCDiff.Failure.corrupt("empty LZMA section") }
        let input = [UInt8](section[(section.startIndex + reader.offset)...])
        var output = [UInt8](repeating: 0, count: size)
        try input.withUnsafeBufferPointer { inBuffer in
            try output.withUnsafeMutableBufferPointer { outBuffer in
                stream.src_ptr = inBuffer.baseAddress ?? UnsafePointer(bitPattern: 1)!
                stream.src_size = inBuffer.count
                stream.dst_ptr = outBuffer.baseAddress!
                stream.dst_size = size
                while stream.dst_size > 0 {
                    let before = (stream.src_size, stream.dst_size)
                    let status = compression_stream_process(&stream, 0)
                    guard status != COMPRESSION_STATUS_ERROR else { throw VCDiff.Failure.corrupt("LZMA data") }
                    if (stream.src_size, stream.dst_size) == before { break }
                }
            }
        }
        guard stream.dst_size == 0 else { throw VCDiff.Failure.corrupt("LZMA section decoded to \(size - stream.dst_size) of \(size) bytes") }
        return Data(output)
    }
}

// MARK: - Code table and address cache (RFC 3284 sections 5.1 to 5.6)

struct CodeTable {
    enum Kind { case noop, add, run, copy }

    struct Instruction {
        var kind: Kind
        var mode: Int = 0
    }

    struct Entry {
        var first: Instruction
        var firstSize: Int
        var second: Instruction = Instruction(kind: .noop)
        var secondSize: Int = 0
    }

    let entries: [Entry]

    static let standard: CodeTable = {
        var entries: [Entry] = []
        entries.append(Entry(first: Instruction(kind: .run), firstSize: 0))
        entries.append(Entry(first: Instruction(kind: .add), firstSize: 0))
        for size in 1...17 { entries.append(Entry(first: Instruction(kind: .add), firstSize: size)) }
        for mode in 0..<9 {
            entries.append(Entry(first: Instruction(kind: .copy, mode: mode), firstSize: 0))
            for size in 4...18 { entries.append(Entry(first: Instruction(kind: .copy, mode: mode), firstSize: size)) }
        }
        for mode in 0..<6 {
            for addSize in 1...4 {
                for copySize in 4...6 {
                    entries.append(Entry(first: Instruction(kind: .add), firstSize: addSize,
                                         second: Instruction(kind: .copy, mode: mode), secondSize: copySize))
                }
            }
        }
        for mode in 6..<9 {
            for addSize in 1...4 {
                entries.append(Entry(first: Instruction(kind: .add), firstSize: addSize,
                                     second: Instruction(kind: .copy, mode: mode), secondSize: 4))
            }
        }
        for mode in 0..<9 {
            entries.append(Entry(first: Instruction(kind: .copy, mode: mode), firstSize: 4,
                                 second: Instruction(kind: .add), secondSize: 1))
        }
        precondition(entries.count == 256)
        return CodeTable(entries: entries)
    }()
}

struct AddressCache {
    static let nearSize = 4
    static let sameSize = 3
    private var near = [Int](repeating: 0, count: nearSize)
    private var nextSlot = 0
    private var same = [Int](repeating: 0, count: sameSize * 256)

    mutating func decode(mode: Int, here: Int, reader: inout ByteReader) throws -> Int {
        let address: Int
        switch mode {
        case 0: address = try reader.int()
        case 1: address = here - (try reader.int())
        case 2 ..< 2 + Self.nearSize: address = near[mode - 2] + (try reader.int())
        default:
            let m = mode - (2 + Self.nearSize)
            address = same[m * 256 + Int(try reader.byte())]
        }
        near[nextSlot] = address
        nextSlot = (nextSlot + 1) % Self.nearSize
        same[address % (Self.sameSize * 256)] = address
        return address
    }
}

struct ByteReader {
    let data: Data
    private(set) var offset = 0

    init(data: Data) { self.data = data }

    var isAtEnd: Bool { offset >= data.count }

    mutating func byte() throws -> UInt8 {
        guard offset < data.count else { throw VCDiff.Failure.truncated }
        defer { offset += 1 }
        return data[data.startIndex + offset]
    }

    /// VCDIFF integer: big-endian base 128, high bit set on every byte but the last.
    mutating func int() throws -> Int {
        var value = 0
        for _ in 0..<10 {
            let b = try byte()
            value = (value << 7) | Int(b & 0x7F)
            if b & 0x80 == 0 { return value }
        }
        throw VCDiff.Failure.corrupt("integer too long")
    }

    mutating func uint32BigEndian() throws -> UInt32 {
        var value: UInt32 = 0
        for _ in 0..<4 { value = (value << 8) | UInt32(try byte()) }
        return value
    }

    mutating func take(_ count: Int) throws -> Data {
        guard count >= 0, offset + count <= data.count else { throw VCDiff.Failure.truncated }
        defer { offset += count }
        return data.subdata(in: data.startIndex + offset ..< data.startIndex + offset + count)
    }

    mutating func skip(_ count: Int) throws { _ = try take(count) }
}
