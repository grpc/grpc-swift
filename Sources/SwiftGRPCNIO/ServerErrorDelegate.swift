import Foundation

public protocol ServerErrorDelegate: class {
  /// Called when an error thrown in the channel pipeline.
  func observe(_ error: Error)

  /// Transforms the given error into a new error.
  ///
  /// This allows framework to transform errors which may be out of their control
  /// due to third-party libraries, for example, into more meaningful errors or
  /// `GRPCStatus` errors. Errors returned from this protocol are not passed to
  /// `observe`.
  ///
  /// - note:
  /// This defaults to returning the provided error.
  func transform(_ error: Error) -> Error
}

public extension ServerErrorDelegate {
  func transform(_ error: Error) -> Error {
    return error
  }
}
