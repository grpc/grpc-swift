/*
 * Copyright 2020, gRPC Authors All rights reserved.
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
import NIO
import struct Foundation.Data

/// Provides minimally configurable wrappers around zlib's compression and decompression
/// functionality.
///
/// See also: https://www.zlib.net/manual.html
enum Zlib {
  // MARK: Deflate (compression)

  /// Creates a new compressor for the given compression format.
  ///
  /// This compressor is only suitable for compressing whole messages at a time. Callers
  /// must `reset()` the compressor between subsequent calls to `deflate`.
  ///
  /// - Parameter format:The expected compression type.
  class Deflate {
    private var stream: ZStream
    private let format: CompressionFormat

    init(format: CompressionFormat) {
      self.stream = ZStream()
      self.format = format
      self.initialize()
    }

    deinit {
      self.end()
    }

    /// Compresses the data in `input` into the `output` buffer.
    ///
    /// - Parameter input: The complete data to be compressed.
    /// - Parameter output: The `ByteBuffer` into which the compressed message should be written.
    /// - Returns: The number of bytes written into the `output` buffer.
    func deflate(_ input: inout ByteBuffer, into output: inout ByteBuffer) throws -> Int {
      // Note: This is only valid because we always use Z_FINISH to flush.
      //
      // From the documentation:
      //   Note that it is possible for the compressed size to be larger than the value returned
      //   by deflateBound() if flush options other than Z_FINISH or Z_NO_FLUSH are used.
      let upperBound = CGRPCZlib_deflateBound(&self.stream.zstream, UInt(input.readableBytes))

      return try input.withUnsafeMutableReadableBytes { inputPointer in
        try output.writeWithUnsafeMutableBytes(minimumWritableBytes: Int(upperBound)) { outputPointer in
          try self.stream.deflate(
            inputBuffer: CGRPCZlib_castVoidToBytefPointer(inputPointer.baseAddress!),
            inputBufferSize: inputPointer.count,
            outputBuffer: CGRPCZlib_castVoidToBytefPointer(outputPointer.baseAddress!),
            outputBufferSize: outputPointer.count
          )
        }
      }
    }

    /// Resets compression state. This must be called after each call to `deflate` if more
    /// messages are to be compressed by this instance.
    func reset() {
      let rc = CGRPCZlib_deflateReset(&self.stream.zstream)

      // Possible return codes:
      // - Z_OK
      // - Z_STREAM_ERROR: the source stream state was inconsistent.
      //
      // If we're in an inconsistent state we can just replace the stream and initialize it.
      switch rc {
      case Z_OK:
        ()

      case Z_STREAM_ERROR:
        self.end()
        self.stream = ZStream()
        self.initialize()

      default:
        preconditionFailure("deflateReset: unexpected return code rc=\(rc)")
      }
    }

    /// Initialize the `z_stream` used for deflate.
    private func initialize() {
      let rc = CGRPCZlib_deflateInit2(
        &self.stream.zstream,
        Z_DEFAULT_COMPRESSION,  // compression level
        Z_DEFLATED,             // compression method (this must be Z_DEFLATED)
        self.format.windowBits, // window size, i.e. deflate/gzip
        8,                      // memory level (this is the default value in the docs)
        Z_DEFAULT_STRATEGY      // compression strategy
      )

      // Possible return codes:
      // - Z_OK
      // - Z_MEM_ERROR: not enough memory
      // - Z_STREAM_ERROR: a parameter was invalid
      //
      // If we can't allocate memory then we can't progress anyway, and we control the parameters
      // so not throwing an error here is okay.
      assert(rc == Z_OK, "deflateInit2 error: rc=\(rc) \(self.stream.lastErrorMessage ?? "")")
    }

    /// Calls `deflateEnd` on the underlying `z_stream` to deallocate resources allocated by zlib.
    private func end() {
      let _ = CGRPCZlib_deflateEnd(&self.stream.zstream)

      // Possible return codes:
      // - Z_OK
      // - Z_STREAM_ERROR: the source stream state was inconsistent.
      //
      // Since we're going away there's no reason to fail here.
    }
  }

  // MARK: Inflate (decompression)

  /// Creates a new decompressor for the given compression format.
  ///
  /// This decompressor is only suitable for decompressing whole messages at a time. Callers
  /// must `reset()` the decompressor between subsequent calls to `inflate`.
  ///
  /// - Parameter format:The expected compression type.
  class Inflate {
    private var stream: ZStream
    private let format: CompressionFormat

    init(format: CompressionFormat) {
      self.stream = ZStream()
      self.format = format
      self.initialize()
    }

    deinit {
      self.end()
    }

    /// Resets decompression state. This must be called after each call to `inflate` if more
    /// messages are to be decompressed by this instance.
    func reset() {
      let rc = CGRPCZlib_inflateReset(&self.stream.zstream)

      // Possible return codes:
      // - Z_OK
      // - Z_STREAM_ERROR: the source stream state was inconsistent.
      //
      // If we're in an inconsistent state we can just replace the stream and initialize it.
      switch rc {
      case Z_OK:
        ()

      case Z_STREAM_ERROR:
        self.end()
        self.stream = ZStream()
        self.initialize()

      default:
        preconditionFailure("inflateReset: unexpected return code rc=\(rc)")
      }
    }

    /// Inflate the readable bytes from the `input` buffer into the `output` buffer.
    ///
    /// - Parameters:
    ///   - input: The buffer read compressed bytes from.
    ///   - output: The buffer to write the decompressed bytes into.
    /// - Returns: The number of bytes written into `output`.
    @discardableResult
    func inflate(_ input: inout ByteBuffer, into output: inout ByteBuffer) throws -> Int {
      return try input.readWithUnsafeMutableReadableBytes { inputPointer -> (Int, Int) in
        // Setup the input buffer.
        self.stream.availableInputBytes = inputPointer.count
        self.stream.nextInputBuffer = CGRPCZlib_castVoidToBytefPointer(inputPointer.baseAddress!)

        defer {
          self.stream.availableInputBytes = 0
          self.stream.nextInputBuffer = nil
        }

        // We don't know how large the output will be; we'll try 2x the input size.
        var outBufferSize = inputPointer.count * 2

        var inflated = false
        var bytesWritten = 0

        while !inflated {
          bytesWritten = try output.writeWithUnsafeMutableBytes(minimumWritableBytes: outBufferSize) { outputPointer in
            let inflateResult = try self.stream.inflate(
              outputBuffer: CGRPCZlib_castVoidToBytefPointer(outputPointer.baseAddress!),
              outputBufferSize: outputPointer.count
            )

            switch inflateResult.outcome {
            case .complete:
              inflated = true
            case .outputBufferTooSmall:
              outBufferSize *= 2
            }

            return inflateResult.bytesWritten
          }
        }

        assert(inflated)

        let bytesRead = inputPointer.count - self.stream.availableInputBytes
        return (bytesRead, bytesWritten)
      }
    }

    private func initialize() {
      let rc = CGRPCZlib_inflateInit2(&self.stream.zstream, self.format.windowBits)

      // Possible return codes:
      // - Z_OK
      // - Z_MEM_ERROR: not enough memory
      //
      // If we can't allocate memory then we can't progress anyway so not throwing an error here is
      // okay.
      precondition(rc == Z_OK, "inflateInit2 error: rc=\(rc) \(self.stream.lastErrorMessage ?? "")")
    }

    func end() {
      let _ = CGRPCZlib_inflateEnd(&self.stream.zstream)

      // Possible return codes:
      // - Z_OK
      // - Z_STREAM_ERROR: the source stream state was inconsistent.
      //
      // Since we're going away there's no reason to fail here.
    }
  }

  enum InflateResult {
    case complete
    case outputBufferTooSmall
  }

  // MARK: ZStream

  /// This wraps a zlib `z_stream` to provide more Swift-like access to the underlying C-struct.
  struct ZStream {
    var zstream: z_stream

    init() {
      self.zstream = z_stream()

      self.zstream.next_in = nil
      self.zstream.avail_in = 0

      self.zstream.next_out = nil
      self.zstream.avail_out = 0

      self.zstream.zalloc = nil
      self.zstream.zfree = nil
      self.zstream.opaque = nil
    }

    /// Number of bytes available to read `self.nextInputBuffer`. See also: `z_stream.avail_in`.
    var availableInputBytes: Int {
      get {
        return Int(self.zstream.avail_in)
      }
      set {
        self.zstream.avail_in = UInt32(newValue)
      }
    }

    /// The next input buffer that zlib should read from. See also: `z_stream.next_in`.
    var nextInputBuffer: UnsafeMutablePointer<Bytef>! {
      get {
        return self.zstream.next_in
      }
      set {
        self.zstream.next_in = newValue
      }
    }

    /// The remaining writable space in `nextOutputBuffer`. See also: `z_stream.avail_out`.
    var availableOutputBytes: Int {
      get {
        return Int(self.zstream.avail_out)
      }
      set {
        return self.zstream.avail_out = UInt32(newValue)
      }
    }

    /// The next output buffer where zlib should write bytes to. See also: `z_stream.next_out`.
    var nextOutputBuffer: UnsafeMutablePointer<Bytef>! {
      get {
        return self.zstream.next_out
      }
      set {
        self.zstream.next_out = newValue
      }
    }

    /// The last error message that zlib wrote. No message is guaranteed on error, however, `nil` is
    /// guaranteed if there is no error. See also `z_stream.msg`.
    var lastErrorMessage: String? {
      guard let bytes = self.zstream.msg else {
        return nil
      }
      return String(cString: bytes)
    }

    enum InflateOutcome {
      /// The data was successfully inflated.
      case complete

      /// A larger output buffer is required.
      case outputBufferTooSmall
    }

    struct InflateResult {
      var bytesWritten: Int
      var outcome: InflateOutcome
    }

    /// Decompress the stream into the given output buffer.
    ///
    /// - Parameter outputBuffer: The buffer into which to write the decompressed data.
    /// - Parameter outputBufferSize: The space available in `outputBuffer`.
    /// - Returns: The result of the `inflate`, whether it was successful or whether a larger
    ///   output buffer is required.
    mutating func inflate(
      outputBuffer: UnsafeMutablePointer<UInt8>,
      outputBufferSize: Int
    ) throws -> InflateResult {
      self.nextOutputBuffer = outputBuffer
      self.availableOutputBytes = outputBufferSize

      defer {
        self.nextOutputBuffer = nil
        self.availableOutputBytes = 0
      }

      let rc = CGRPCZlib_inflate(&self.zstream, Z_FINISH)
      let outcome: InflateOutcome

      // Possible return codes:
      // - Z_OK: some progress has been made
      // - Z_STREAM_END: the end of the compressed data has been reached and all uncompressed output
      //   has been produced
      // - Z_NEED_DICT: a preset dictionary is needed at this point
      // - Z_DATA_ERROR: the input data was corrupted
      // - Z_STREAM_ERROR: the stream structure was inconsistent
      // - Z_MEM_ERROR there was not enough memory
      // - Z_BUF_ERROR if no progress was possible or if there was not enough room in the output
      //   buffer when Z_FINISH is used.
      //
      // Note that Z_OK is not okay here since we always flush with Z_FINISH and therefore
      // use Z_STREAM_END as our success criteria.

      switch rc {
      case Z_STREAM_END:
        outcome = .complete

      case Z_BUF_ERROR:
        outcome = .outputBufferTooSmall

      default:
        throw GRPCError.ZlibCompressionFailure(code: rc, message: self.lastErrorMessage).captureContext()
      }

      return InflateResult(
        bytesWritten: outputBufferSize - self.availableOutputBytes,
        outcome: outcome
      )
    }

    /// Compresses the `inputBuffer` into the `outputBuffer`.
    ///
    /// `outputBuffer` must be large enough to store the compressed data, `deflateBound()` provides
    /// an upper bound for this value.
    ///
    /// - Parameter inputBuffer: The buffer from which to read the data.
    /// - Parameter inputBufferSize: The number of bytes available to read in `inputBuffer`.
    /// - Parameter outputBuffer: The buffer into which to write the compressed data.
    /// - Parameter outputBufferSize: The space available in `outputBuffer`.
    /// - Returns: The number of bytes written into the `outputBuffer`.
    mutating func deflate(
      inputBuffer: UnsafeMutablePointer<UInt8>,
      inputBufferSize: Int,
      outputBuffer: UnsafeMutablePointer<UInt8>,
      outputBufferSize: Int
    ) throws -> Int {
      self.nextInputBuffer = inputBuffer
      self.availableInputBytes = inputBufferSize
      self.nextOutputBuffer = outputBuffer
      self.availableOutputBytes = outputBufferSize

      defer {
        self.nextInputBuffer = nil
        self.availableInputBytes = 0
        self.nextOutputBuffer = nil
        self.availableOutputBytes = 0
      }

      let rc = CGRPCZlib_deflate(&self.zstream, Z_FINISH)

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
        throw GRPCError.ZlibCompressionFailure(code: rc, message: self.lastErrorMessage).captureContext()
      }

      return outputBufferSize - self.availableOutputBytes
    }
  }

  enum CompressionFormat {
    case deflate
    case gzip

    var windowBits: Int32 {
      switch self {
      case .deflate:
        return 15
      case .gzip:
        return 31
      }
    }
  }
}
