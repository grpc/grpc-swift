/*
 * Copyright 2022, gRPC Authors All rights reserved.
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
import DequeModule
import NIOCore

internal struct CoalescingLengthPrefixedMessageWriter {
  /// Length of the gRPC message header (1 compression byte, 4 bytes for the length).
  static let metadataLength = 5

  /// Message size above which we emit two buffers: one containing the header and one with the
  /// actual message bytes. At or below the limit we copy the message into a new buffer containing
  /// both the header and the message.
  ///
  /// Using two buffers avoids expensive copies of large messages. For smaller messages the copy
  /// is cheaper than the additional allocations and overhead required to send an extra HTTP/2 DATA
  /// frame.
  ///
  /// The value of 16k was chosen empirically. We subtract the length of the message header
  /// as `ByteBuffer` reserve capacity in powers of two and want to avoid overallocating.
  static let singleBufferSizeLimit = 16384 - Self.metadataLength

  /// The compression algorithm to use, if one should be used.
  private let compression: CompressionAlgorithm?
  /// Any compressor associated with the compression algorithm.
  private let compressor: Zlib.Deflate?

  /// Whether the compression message flag should be set.
  private var supportsCompression: Bool {
    return self.compression != nil
  }

  /// A scratch buffer that we encode messages into: if the buffer isn't held elsewhere then we
  /// can avoid having to allocate a new one.
  private var scratch: ByteBuffer

  /// Outbound buffers waiting to be written.
  private var pending: OneOrManyQueue<Pending>

  private struct Pending {
    var buffer: ByteBuffer
    var promise: EventLoopPromise<Void>?
    var compress: Bool

    init(buffer: ByteBuffer, compress: Bool, promise: EventLoopPromise<Void>?) {
      self.buffer = buffer
      self.promise = promise
      self.compress = compress
    }

    var isSmallEnoughToCoalesce: Bool {
      let limit = CoalescingLengthPrefixedMessageWriter.singleBufferSizeLimit
      return self.buffer.readableBytes <= limit
    }

    var shouldCoalesce: Bool {
      return self.isSmallEnoughToCoalesce || self.compress
    }
  }

  private enum State {
    // Coalescing pending messages.
    case coalescing
    // Emitting a non-coalesced message; the header has been written, the body
    // needs to be written next.
    case emittingLargeFrame(ByteBuffer, EventLoopPromise<Void>?)
  }

  private var state: State

  init(compression: CompressionAlgorithm? = nil, allocator: ByteBufferAllocator) {
    self.compression = compression
    self.scratch = allocator.buffer(capacity: 0)
    self.state = .coalescing
    self.pending = .init()

    switch self.compression?.algorithm {
    case .none, .some(.identity):
      self.compressor = nil
    case .some(.deflate):
      self.compressor = Zlib.Deflate(format: .deflate)
    case .some(.gzip):
      self.compressor = Zlib.Deflate(format: .gzip)
    }
  }

  /// Append a serialized message buffer to the writer.
  mutating func append(buffer: ByteBuffer, compress: Bool, promise: EventLoopPromise<Void>?) {
    let pending = Pending(
      buffer: buffer,
      compress: compress && self.supportsCompression,
      promise: promise
    )

    self.pending.append(pending)
  }

  /// Return a tuple of the next buffer to write and its associated write promise.
  mutating func next() -> (Result<ByteBuffer, Error>, EventLoopPromise<Void>?)? {
    switch self.state {
    case .coalescing:
      // Nothing pending: exit early.
      if self.pending.isEmpty {
        return nil
      }

      // First up we need to work out how many elements we're going to pop off the front
      // and coalesce.
      //
      // At the same time we'll compute how much capacity we'll need in the buffer and cascade
      // their promises.
      var messagesToCoalesce = 0
      var requiredCapacity = 0
      var promise: EventLoopPromise<Void>?

      for element in self.pending {
        if !element.shouldCoalesce {
          break
        }

        messagesToCoalesce &+= 1
        requiredCapacity += element.buffer.readableBytes + Self.metadataLength
        if let existing = promise {
          existing.futureResult.cascade(to: element.promise)
        } else {
          promise = element.promise
        }
      }

      if messagesToCoalesce == 0 {
        // Nothing to coalesce; this means the first element should be emitted with its header in
        // a separate buffer. Note: the force unwrap is okay here: we early exit if `self.pending`
        // is empty.
        let pending = self.pending.pop()!

        // Set the scratch buffer to just be a message header then store the message bytes.
        self.scratch.clear(minimumCapacity: Self.metadataLength)
        self.scratch.writeMultipleIntegers(UInt8(0), UInt32(pending.buffer.readableBytes))
        self.state = .emittingLargeFrame(pending.buffer, pending.promise)
        return (.success(self.scratch), nil)
      } else {
        self.scratch.clear(minimumCapacity: requiredCapacity)

        // Drop and encode the messages.
        while messagesToCoalesce > 0, let next = self.pending.pop() {
          messagesToCoalesce &-= 1
          do {
            try self.encode(next.buffer, compress: next.compress)
          } catch {
            return (.failure(error), promise)
          }
        }

        return (.success(self.scratch), promise)
      }

    case let .emittingLargeFrame(buffer, promise):
      // We just emitted the header, now emit the body.
      self.state = .coalescing
      return (.success(buffer), promise)
    }
  }

  private mutating func encode(_ buffer: ByteBuffer, compress: Bool) throws {
    if let compressor = self.compressor, compress {
      try self.encode(buffer, compressor: compressor)
    } else {
      try self.encode(buffer)
    }
  }

  private mutating func encode(_ buffer: ByteBuffer, compressor: Zlib.Deflate) throws {
    // Set the compression byte.
    self.scratch.writeInteger(UInt8(1))
    // Set the length to zero; we'll write the actual value in a moment.
    let payloadSizeIndex = self.scratch.writerIndex
    self.scratch.writeInteger(UInt32(0))

    let bytesWritten: Int
    do {
      var buffer = buffer
      bytesWritten = try compressor.deflate(&buffer, into: &self.scratch)
    } catch {
      throw error
    }

    self.scratch.setInteger(UInt32(bytesWritten), at: payloadSizeIndex)

    // Finally, the compression context should be reset between messages.
    compressor.reset()
  }

  private mutating func encode(_ buffer: ByteBuffer) throws {
    self.scratch.writeMultipleIntegers(UInt8(0), UInt32(buffer.readableBytes))
    self.scratch.writeImmutableBuffer(buffer)
  }
}

/// A FIFO-queue which allows for a single to be stored on the stack and defers to a
/// heap-implementation if further elements are added.
///
/// This is useful when optimising for unary streams where avoiding the cost of a heap
/// allocation is desirable.
internal struct OneOrManyQueue<Element>: Collection {
  private var backing: Backing

  private enum Backing: Collection {
    case none
    case one(Element)
    case many(Deque<Element>)

    var startIndex: Int {
      switch self {
      case .none, .one:
        return 0
      case let .many(elements):
        return elements.startIndex
      }
    }

    var endIndex: Int {
      switch self {
      case .none:
        return 0
      case .one:
        return 1
      case let .many(elements):
        return elements.endIndex
      }
    }

    subscript(index: Int) -> Element {
      switch self {
      case .none:
        fatalError("Invalid index")
      case let .one(element):
        assert(index == 0)
        return element
      case let .many(elements):
        return elements[index]
      }
    }

    func index(after index: Int) -> Int {
      switch self {
      case .none:
        return 0
      case .one:
        return 1
      case let .many(elements):
        return elements.index(after: index)
      }
    }

    var count: Int {
      switch self {
      case .none:
        return 0
      case .one:
        return 1
      case let .many(elements):
        return elements.count
      }
    }

    var isEmpty: Bool {
      switch self {
      case .none:
        return true
      case .one:
        return false
      case let .many(elements):
        return elements.isEmpty
      }
    }

    mutating func append(_ element: Element) {
      switch self {
      case .none:
        self = .one(element)
      case let .one(one):
        var elements = Deque<Element>()
        elements.reserveCapacity(16)
        elements.append(one)
        elements.append(element)
        self = .many(elements)
      case var .many(elements):
        self = .none
        elements.append(element)
        self = .many(elements)
      }
    }

    mutating func pop() -> Element? {
      switch self {
      case .none:
        return nil
      case let .one(element):
        self = .none
        return element
      case var .many(many):
        self = .none
        let element = many.popFirst()
        self = .many(many)
        return element
      }
    }
  }

  init() {
    self.backing = .none
  }

  var isEmpty: Bool {
    return self.backing.isEmpty
  }

  var count: Int {
    return self.backing.count
  }

  var startIndex: Int {
    return self.backing.startIndex
  }

  var endIndex: Int {
    return self.backing.endIndex
  }

  subscript(index: Int) -> Element {
    return self.backing[index]
  }

  func index(after index: Int) -> Int {
    return self.backing.index(after: index)
  }

  mutating func append(_ element: Element) {
    self.backing.append(element)
  }

  mutating func pop() -> Element? {
    return self.backing.pop()
  }
}
