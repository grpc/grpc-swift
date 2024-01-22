/*
 * Copyright 2024, gRPC Authors All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import CGRPCZlib
import GRPCCore
import NIOCore

enum Zlib {
  enum Method {
    case deflate
    case gzip

    fileprivate var windowBits: Int32 {
      switch self {
      case .deflate:
        return 15
      case .gzip:
        return 31
      }
    }
  }
}

extension Zlib {
  /// Creates a new compressor for the given compression format.
  ///
  /// This compressor is only suitable for compressing whole messages at a time. Callers
  /// must ``initialize()`` the compressor before using it.
  struct Compressor {
    private var stream: z_stream
    private let method: Method
    private var isInitialized = false

    init(method: Method) {
      self.method = method
      self.stream = z_stream()
    }

    /// Initialize the compressor.
    mutating func initialize() {
      precondition(!self.isInitialized)
      self.stream.deflateInit(windowBits: self.method.windowBits)
      self.isInitialized = true
    }

    static func initialized(_ method: Method) -> Self {
      var compressor = Compressor(method: method)
      compressor.initialize()
      return compressor
    }

    /// Compresses the data in `input` into the `output` buffer.
    ///
    /// - Parameter input: The complete data to be compressed.
    /// - Parameter output: The `ByteBuffer` into which the compressed message should be written.
    /// - Returns: The number of bytes written into the `output` buffer.
    @discardableResult
    mutating func compress(_ input: [UInt8], into output: inout ByteBuffer) throws -> Int {
      precondition(self.isInitialized)
      defer { self.reset() }
      let upperBound = self.stream.deflateBound(inputBytes: input.count)
      return try self.stream.deflate(input, into: &output, upperBound: upperBound)
    }

    /// Resets compression state.
    private mutating func reset() {
      do {
        try self.stream.deflateReset()
      } catch {
        self.end()
        self.stream = z_stream()
        self.stream.deflateInit(windowBits: self.method.windowBits)
      }
    }

    /// Deallocates any resources allocated by Zlib.
    mutating func end() {
      self.stream.deflateEnd()
    }
  }
}

extension Zlib {
  /// Creates a new decompressor for the given compression format.
  ///
  /// This decompressor is only suitable for compressing whole messages at a time. Callers
  /// must ``initialize()`` the decompressor before using it.
  struct Decompressor {
    private var stream: z_stream
    private let method: Method
    private var isInitialized = false

    init(method: Method) {
      self.method = method
      self.stream = z_stream()
    }

    mutating func initialize() {
      precondition(!self.isInitialized)
      self.stream.inflateInit(windowBits: self.method.windowBits)
      self.isInitialized = true
    }

    /// Returns the decompressed bytes from ``input``.
    ///
    /// - Parameters:
    ///   - input: The buffer read compressed bytes from.
    ///   - limit: The largest size a decompressed payload may be.
    mutating func decompress(_ input: inout ByteBuffer, limit: Int) throws -> [UInt8] {
      precondition(self.isInitialized)
      defer { self.reset() }
      return try self.stream.inflate(input: &input, limit: limit)
    }

    /// Resets decompression state.
    private mutating func reset() {
      do {
        try self.stream.inflateReset()
      } catch {
        self.end()
        self.stream = z_stream()
        self.stream.inflateInit(windowBits: self.method.windowBits)
      }
    }

    /// Deallocates any resources allocated by Zlib.
    mutating func end() {
      self.stream.inflateEnd()
    }
  }
}

struct ZlibError: Error, Hashable {
  /// Error code returned from Zlib.
  var code: Int
  /// Error message produced by Zlib.
  var message: String

  init(code: Int, message: String) {
    self.code = code
    self.message = message
  }
}

extension z_stream {
  mutating func inflateInit(windowBits: Int32) {
    self.zfree = nil
    self.zalloc = nil
    self.opaque = nil

    let rc = CGRPCZlib_inflateInit2(&self, windowBits)
    // Possible return codes:
    // - Z_OK
    // - Z_MEM_ERROR: not enough memory
    //
    // If we can't allocate memory then we can't progress anyway so not throwing an error here is
    // okay.
    precondition(rc == Z_OK, "inflateInit2 failed with error (\(rc)) \(self.lastError ?? "")")
  }

  mutating func inflateReset() throws {
    let rc = CGRPCZlib_inflateReset(&self)

    // Possible return codes:
    // - Z_OK
    // - Z_STREAM_ERROR: the source stream state was inconsistent.
    switch rc {
    case Z_OK:
      ()
    case Z_STREAM_ERROR:
      throw ZlibError(code: Int(rc), message: self.lastError ?? "")
    default:
      preconditionFailure("inflateReset returned unexpected code (\(rc))")
    }
  }

  mutating func inflateEnd() {
    _ = CGRPCZlib_inflateEnd(&self)
  }

  mutating func deflateInit(windowBits: Int32) {
    self.zfree = nil
    self.zalloc = nil
    self.opaque = nil

    let rc = CGRPCZlib_deflateInit2(
      &self,
      Z_DEFAULT_COMPRESSION,  // compression level
      Z_DEFLATED,  // compression method (this must be Z_DEFLATED)
      windowBits,  // window size, i.e. deflate/gzip
      8,  // memory level (this is the default value in the docs)
      Z_DEFAULT_STRATEGY  // compression strategy
    )

    // Possible return codes:
    // - Z_OK
    // - Z_MEM_ERROR: not enough memory
    // - Z_STREAM_ERROR: a parameter was invalid
    //
    // If we can't allocate memory then we can't progress anyway, and we control the parameters
    // so not throwing an error here is okay.
    precondition(rc == Z_OK, "deflateInit2 failed with error (\(rc)) \(self.lastError ?? "")")
  }

  mutating func deflateReset() throws {
    let rc = CGRPCZlib_deflateReset(&self)

    // Possible return codes:
    // - Z_OK
    // - Z_STREAM_ERROR: the source stream state was inconsistent.
    switch rc {
    case Z_OK:
      ()
    case Z_STREAM_ERROR:
      throw ZlibError(code: Int(rc), message: self.lastError ?? "")
    default:
      preconditionFailure("deflateReset returned unexpected code (\(rc))")
    }
  }

  mutating func deflateEnd() {
    _ = CGRPCZlib_deflateEnd(&self)
  }

  mutating func deflateBound(inputBytes: Int) -> Int {
    let bound = CGRPCZlib_deflateBound(&self, UInt(inputBytes))
    return Int(bound)
  }

  mutating func setNextInputBuffer(_ buffer: UnsafeMutableBufferPointer<UInt8>) {
    if let baseAddress = buffer.baseAddress {
      self.next_in = baseAddress
      self.avail_in = UInt32(buffer.count)
    } else {
      self.next_in = nil
      self.avail_in = 0
    }
  }

  mutating func setNextInputBuffer(_ buffer: UnsafeMutableRawBufferPointer?) {
    if let buffer = buffer, let baseAddress = buffer.baseAddress {
      self.next_in = CGRPCZlib_castVoidToBytefPointer(baseAddress)
      self.avail_in = UInt32(buffer.count)
    } else {
      self.next_in = nil
      self.avail_in = 0
    }
  }

  mutating func setNextOutputBuffer(_ buffer: UnsafeMutableBufferPointer<UInt8>) {
    if let baseAddress = buffer.baseAddress {
      self.next_out = baseAddress
      self.avail_out = UInt32(buffer.count)
    } else {
      self.next_out = nil
      self.avail_out = 0
    }
  }

  mutating func setNextOutputBuffer(_ buffer: UnsafeMutableRawBufferPointer?) {
    if let buffer = buffer, let baseAddress = buffer.baseAddress {
      self.next_out = CGRPCZlib_castVoidToBytefPointer(baseAddress)
      self.avail_out = UInt32(buffer.count)
    } else {
      self.next_out = nil
      self.avail_out = 0
    }
  }

  /// Number of bytes available to read `self.nextInputBuffer`. See also: `z_stream.avail_in`.
  var availableInputBytes: Int {
    get {
      Int(self.avail_in)
    }
    set {
      self.avail_in = UInt32(newValue)
    }
  }

  /// The remaining writable space in `nextOutputBuffer`. See also: `z_stream.avail_out`.
  var availableOutputBytes: Int {
    get {
      Int(self.avail_out)
    }
    set {
      self.avail_out = UInt32(newValue)
    }
  }

  /// The total number of bytes written to the output buffer. See also: `z_stream.total_out`.
  var totalOutputBytes: Int {
    Int(self.total_out)
  }

  /// The last error message that zlib wrote. No message is guaranteed on error, however, `nil` is
  /// guaranteed if there is no error. See also `z_stream.msg`.
  var lastError: String? {
    self.msg.map { String(cString: $0) }
  }

  mutating func inflate(input: inout ByteBuffer, limit: Int) throws -> [UInt8] {
    return try input.readWithUnsafeMutableReadableBytes { inputPointer in
      self.setNextInputBuffer(inputPointer)
      defer {
        self.setNextInputBuffer(nil)
        self.setNextOutputBuffer(nil)
      }

      // Assume the output will be twice as large as the input.
      var output = [UInt8](repeating: 0, count: min(inputPointer.count * 2, limit))
      var offset = 0

      while true {
        let (finished, written) = try output[offset...].withUnsafeMutableBytes { outPointer in
          self.setNextOutputBuffer(outPointer)

          let finished: Bool

          // Possible return codes:
          // - Z_OK: some progress has been made
          // - Z_STREAM_END: the end of the compressed data has been reached and all uncompressed
          //   output has been produced
          // - Z_NEED_DICT: a preset dictionary is needed at this point
          // - Z_DATA_ERROR: the input data was corrupted
          // - Z_STREAM_ERROR: the stream structure was inconsistent
          // - Z_MEM_ERROR there was not enough memory
          // - Z_BUF_ERROR if no progress was possible or if there was not enough room in the output
          //   buffer when Z_FINISH is used.
          //
          // Note that Z_OK is not okay here since we always flush with Z_FINISH and therefore
          // use Z_STREAM_END as our success criteria.
          let rc = CGRPCZlib_inflate(&self, Z_FINISH)
          switch rc {
          case Z_STREAM_END:
            finished = true
          case Z_BUF_ERROR:
            finished = false
          default:
            throw RPCError(
              code: .internalError,
              message: "Decompression error",
              cause: ZlibError(code: Int(rc), message: self.lastError ?? "")
            )
          }

          let size = outPointer.count - self.availableOutputBytes
          return (finished, size)
        }

        if finished {
          output.removeLast(output.count - self.totalOutputBytes)
          let bytesRead = inputPointer.count - self.availableInputBytes
          return (bytesRead, output)
        } else {
          offset += written
          let newSize = min(output.count * 2, limit)
          if newSize == output.count {
            throw RPCError(code: .resourceExhausted, message: "Message is too large to decompress.")
          } else {
            output.append(contentsOf: repeatElement(0, count: newSize - output.count))
          }
        }
      }
    }
  }

  mutating func deflate(
    _ input: [UInt8],
    into output: inout ByteBuffer,
    upperBound: Int
  ) throws -> Int {
    defer {
      self.setNextInputBuffer(nil)
      self.setNextOutputBuffer(nil)
    }

    var input = input
    return try input.withUnsafeMutableBytes { input in
      self.setNextInputBuffer(input)

      return try output.writeWithUnsafeMutableBytes(minimumWritableBytes: upperBound) { output in
        self.setNextOutputBuffer(output)

        let rc = CGRPCZlib_deflate(&self, Z_FINISH)

        // Possible return codes:
        // - Z_OK: some progress has been made
        // - Z_STREAM_END: all input has been consumed and all output has been produced (only when
        //   flush is set to Z_FINISH)
        // - Z_STREAM_ERROR: the stream state was inconsistent
        // - Z_BUF_ERROR: no progress is possible
        //
        // The documentation notes that Z_BUF_ERROR is not fatal, and deflate() can be called again
        // with more input and more output space to continue compressing. However, we
        // call `deflateBound()` before `deflate()` which guarantees that the output size will not be
        // larger than the value returned by `deflateBound()` if `Z_FINISH` flush is used. As such,
        // the only acceptable outcome is `Z_STREAM_END`.
        guard rc == Z_STREAM_END else {
          throw RPCError(
            code: .internalError,
            message: "Compression error",
            cause: ZlibError(code: Int(rc), message: self.lastError ?? "")
          )
        }

        return output.count - self.availableOutputBytes
      }
    }
  }
}
