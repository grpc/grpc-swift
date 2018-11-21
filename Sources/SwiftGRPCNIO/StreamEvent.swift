import SwiftProtobuf

/// An event that can occur on a client-streaming RPC. Provided to the event observer registered for that call.
public enum StreamEvent<Message: SwiftProtobuf.Message> {
  case message(Message)
  case end
  //! FIXME: Also support errors in this type, to propagate them to the event handler.
}
