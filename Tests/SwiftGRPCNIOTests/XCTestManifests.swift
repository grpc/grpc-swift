#if !canImport(ObjectiveC)
import XCTest

extension ClientThrowingWhenServerReturningErrorTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__ClientThrowingWhenServerReturningErrorTests = [
        ("testBidirectionalStreaming", testBidirectionalStreaming),
        ("testClientStreaming", testClientStreaming),
        ("testServerStreaming", testServerStreaming),
        ("testUnary", testUnary),
    ]
}

extension GRPCChannelHandlerTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__GRPCChannelHandlerTests = [
        ("testImplementedMethodReturnsHeadersMessageAndStatus", testImplementedMethodReturnsHeadersMessageAndStatus),
        ("testImplementedMethodReturnsStatusForBadlyFormedProto", testImplementedMethodReturnsStatusForBadlyFormedProto),
        ("testUnimplementedMethodReturnsUnimplementedStatus", testUnimplementedMethodReturnsUnimplementedStatus),
    ]
}

extension GRPCInsecureInteroperabilityTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__GRPCInsecureInteroperabilityTests = [
        ("testCacheableUnary", testCacheableUnary),
        ("testCancelAfterBegin", testCancelAfterBegin),
        ("testCancelAfterFirstResponse", testCancelAfterFirstResponse),
        ("testClientStreaming", testClientStreaming),
        ("testCustomMetadata", testCustomMetadata),
        ("testEmptyStream", testEmptyStream),
        ("testEmptyUnary", testEmptyUnary),
        ("testLargeUnary", testLargeUnary),
        ("testPingPong", testPingPong),
        ("testServerStreaming", testServerStreaming),
        ("testSpecialStatusAndMessage", testSpecialStatusAndMessage),
        ("testStatusCodeAndMessage", testStatusCodeAndMessage),
        ("testTimeoutOnSleepingServer", testTimeoutOnSleepingServer),
        ("testUnimplementedMethod", testUnimplementedMethod),
        ("testUnimplementedService", testUnimplementedService),
    ]
}

extension GRPCSecureInteroperabilityTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__GRPCSecureInteroperabilityTests = [
        ("testCacheableUnary", testCacheableUnary),
        ("testCancelAfterBegin", testCancelAfterBegin),
        ("testCancelAfterFirstResponse", testCancelAfterFirstResponse),
        ("testClientStreaming", testClientStreaming),
        ("testCustomMetadata", testCustomMetadata),
        ("testEmptyStream", testEmptyStream),
        ("testEmptyUnary", testEmptyUnary),
        ("testLargeUnary", testLargeUnary),
        ("testPingPong", testPingPong),
        ("testServerStreaming", testServerStreaming),
        ("testSpecialStatusAndMessage", testSpecialStatusAndMessage),
        ("testStatusCodeAndMessage", testStatusCodeAndMessage),
        ("testTimeoutOnSleepingServer", testTimeoutOnSleepingServer),
        ("testUnimplementedMethod", testUnimplementedMethod),
        ("testUnimplementedService", testUnimplementedService),
    ]
}

extension GRPCStatusMessageMarshallerTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__GRPCStatusMessageMarshallerTests = [
        ("testASCIIMarshallingAndUnmarshalling", testASCIIMarshallingAndUnmarshalling),
        ("testPercentMarshallingAndUnmarshalling", testPercentMarshallingAndUnmarshalling),
        ("testUnicodeMarshalling", testUnicodeMarshalling),
    ]
}

extension HTTP1ToRawGRPCServerCodecTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__HTTP1ToRawGRPCServerCodecTests = [
        ("testInternalErrorStatusIsReturnedIfMessageCannotBeDeserialized", testInternalErrorStatusIsReturnedIfMessageCannotBeDeserialized),
        ("testInternalErrorStatusIsReturnedWhenSendingTrailersInRequest", testInternalErrorStatusIsReturnedWhenSendingTrailersInRequest),
        ("testInternalErrorStatusReturnedWhenCompressionFlagIsSet", testInternalErrorStatusReturnedWhenCompressionFlagIsSet),
        ("testMessageCanBeSentAcrossMultipleByteBuffers", testMessageCanBeSentAcrossMultipleByteBuffers),
        ("testOnlyOneStatusIsReturned", testOnlyOneStatusIsReturned),
    ]
}

extension LengthPrefixedMessageReaderTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__LengthPrefixedMessageReaderTests = [
        ("testAppendReadsAllBytes", testAppendReadsAllBytes),
        ("testNextMessageDeliveredAcrossMultipleByteBuffers", testNextMessageDeliveredAcrossMultipleByteBuffers),
        ("testNextMessageDoesNotThrowWhenCompressionFlagIsExpectedButNotSet", testNextMessageDoesNotThrowWhenCompressionFlagIsExpectedButNotSet),
        ("testNextMessageReturnsMessageForZeroLengthMessage", testNextMessageReturnsMessageForZeroLengthMessage),
        ("testNextMessageReturnsMessageIsAppendedInOneBuffer", testNextMessageReturnsMessageIsAppendedInOneBuffer),
        ("testNextMessageReturnsNilWhenNoBytesAppended", testNextMessageReturnsNilWhenNoBytesAppended),
        ("testNextMessageReturnsNilWhenNoMessageBytesAreAvailable", testNextMessageReturnsNilWhenNoMessageBytesAreAvailable),
        ("testNextMessageReturnsNilWhenNoMessageLengthIsAvailable", testNextMessageReturnsNilWhenNoMessageLengthIsAvailable),
        ("testNextMessageReturnsNilWhenNotAllMessageBytesAreAvailable", testNextMessageReturnsNilWhenNotAllMessageBytesAreAvailable),
        ("testNextMessageReturnsNilWhenNotAllMessageLengthIsAvailable", testNextMessageReturnsNilWhenNotAllMessageLengthIsAvailable),
        ("testNextMessageThrowsWhenCompressionFlagIsSetButNotExpected", testNextMessageThrowsWhenCompressionFlagIsSetButNotExpected),
        ("testNextMessageThrowsWhenCompressionMechanismIsNotSupported", testNextMessageThrowsWhenCompressionMechanismIsNotSupported),
        ("testNextMessageWhenMultipleMessagesAreBuffered", testNextMessageWhenMultipleMessagesAreBuffered),
    ]
}

extension NIOClientCancellingTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__NIOClientCancellingTests = [
        ("testBidirectionalStreaming", testBidirectionalStreaming),
        ("testClientStreaming", testClientStreaming),
        ("testServerStreaming", testServerStreaming),
        ("testUnary", testUnary),
    ]
}

extension NIOClientClosedChannelTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__NIOClientClosedChannelTests = [
        ("testBidirectionalStreamingOnClosedConnection", testBidirectionalStreamingOnClosedConnection),
        ("testBidirectionalStreamingWhenConnectionIsClosedBetweenMessages", testBidirectionalStreamingWhenConnectionIsClosedBetweenMessages),
        ("testBidirectionalStreamingWithNoPromiseWhenConnectionIsClosedBetweenMessages", testBidirectionalStreamingWithNoPromiseWhenConnectionIsClosedBetweenMessages),
        ("testClientStreamingOnClosedConnection", testClientStreamingOnClosedConnection),
        ("testClientStreamingWhenConnectionIsClosedBetweenMessages", testClientStreamingWhenConnectionIsClosedBetweenMessages),
        ("testServerStreamingOnClosedConnection", testServerStreamingOnClosedConnection),
        ("testUnaryOnClosedConnection", testUnaryOnClosedConnection),
    ]
}

extension NIOClientTLSFailureTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__NIOClientTLSFailureTests = [
        ("testClientConnectionFailsWhenHostnameIsNotValid", testClientConnectionFailsWhenHostnameIsNotValid),
        ("testClientConnectionFailsWhenProtocolCanNotBeNegotiated", testClientConnectionFailsWhenProtocolCanNotBeNegotiated),
        ("testClientConnectionFailsWhenServerIsUnknown", testClientConnectionFailsWhenServerIsUnknown),
    ]
}

extension NIOClientTimeoutTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__NIOClientTimeoutTests = [
        ("testBidirectionalStreamingTimeoutAfterSending", testBidirectionalStreamingTimeoutAfterSending),
        ("testBidirectionalStreamingTimeoutBeforeSending", testBidirectionalStreamingTimeoutBeforeSending),
        ("testClientStreamingTimeoutAfterSending", testClientStreamingTimeoutAfterSending),
        ("testClientStreamingTimeoutBeforeSending", testClientStreamingTimeoutBeforeSending),
        ("testServerStreamingTimeoutAfterSending", testServerStreamingTimeoutAfterSending),
        ("testUnaryTimeoutAfterSending", testUnaryTimeoutAfterSending),
    ]
}

extension NIOFunctionalTestsAnonymousClient {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__NIOFunctionalTestsAnonymousClient = [
        ("testBidirectionalStreamingBatched", testBidirectionalStreamingBatched),
        ("testBidirectionalStreamingLotsOfMessagesBatched", testBidirectionalStreamingLotsOfMessagesBatched),
        ("testBidirectionalStreamingLotsOfMessagesPingPong", testBidirectionalStreamingLotsOfMessagesPingPong),
        ("testBidirectionalStreamingPingPong", testBidirectionalStreamingPingPong),
        ("testClientStreaming", testClientStreaming),
        ("testClientStreamingLotsOfMessages", testClientStreamingLotsOfMessages),
        ("testServerStreaming", testServerStreaming),
        ("testServerStreamingLotsOfMessages", testServerStreamingLotsOfMessages),
        ("testUnary", testUnary),
        ("testUnaryEmptyRequest", testUnaryEmptyRequest),
        ("testUnaryLotsOfRequests", testUnaryLotsOfRequests),
        ("testUnaryWithLargeData", testUnaryWithLargeData),
    ]
}

extension NIOFunctionalTestsInsecureTransport {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__NIOFunctionalTestsInsecureTransport = [
        ("testBidirectionalStreamingBatched", testBidirectionalStreamingBatched),
        ("testBidirectionalStreamingLotsOfMessagesBatched", testBidirectionalStreamingLotsOfMessagesBatched),
        ("testBidirectionalStreamingLotsOfMessagesPingPong", testBidirectionalStreamingLotsOfMessagesPingPong),
        ("testBidirectionalStreamingPingPong", testBidirectionalStreamingPingPong),
        ("testClientStreaming", testClientStreaming),
        ("testClientStreamingLotsOfMessages", testClientStreamingLotsOfMessages),
        ("testServerStreaming", testServerStreaming),
        ("testServerStreamingLotsOfMessages", testServerStreamingLotsOfMessages),
        ("testUnary", testUnary),
        ("testUnaryEmptyRequest", testUnaryEmptyRequest),
        ("testUnaryLotsOfRequests", testUnaryLotsOfRequests),
        ("testUnaryWithLargeData", testUnaryWithLargeData),
    ]
}

extension NIOFunctionalTestsMutualAuthentication {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__NIOFunctionalTestsMutualAuthentication = [
        ("testBidirectionalStreamingBatched", testBidirectionalStreamingBatched),
        ("testBidirectionalStreamingLotsOfMessagesBatched", testBidirectionalStreamingLotsOfMessagesBatched),
        ("testBidirectionalStreamingLotsOfMessagesPingPong", testBidirectionalStreamingLotsOfMessagesPingPong),
        ("testBidirectionalStreamingPingPong", testBidirectionalStreamingPingPong),
        ("testClientStreaming", testClientStreaming),
        ("testClientStreamingLotsOfMessages", testClientStreamingLotsOfMessages),
        ("testServerStreaming", testServerStreaming),
        ("testServerStreamingLotsOfMessages", testServerStreamingLotsOfMessages),
        ("testUnary", testUnary),
        ("testUnaryEmptyRequest", testUnaryEmptyRequest),
        ("testUnaryLotsOfRequests", testUnaryLotsOfRequests),
        ("testUnaryWithLargeData", testUnaryWithLargeData),
    ]
}

extension NIOServerWebTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__NIOServerWebTests = [
        ("testServerStreaming", testServerStreaming),
        ("testUnary", testUnary),
        ("testUnaryLotsOfRequests", testUnaryLotsOfRequests),
        ("testUnaryWithoutRequestMessage", testUnaryWithoutRequestMessage),
    ]
}

extension ServerDelayedThrowingTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__ServerDelayedThrowingTests = [
        ("testBidirectionalStreaming", testBidirectionalStreaming),
        ("testClientStreaming", testClientStreaming),
        ("testServerStreaming", testServerStreaming),
        ("testUnary", testUnary),
    ]
}

extension ServerErrorTransformingTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__ServerErrorTransformingTests = [
        ("testBidirectionalStreaming", testBidirectionalStreaming),
        ("testClientStreaming", testClientStreaming),
        ("testServerStreaming", testServerStreaming),
        ("testUnary", testUnary),
    ]
}

extension ServerThrowingTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__ServerThrowingTests = [
        ("testBidirectionalStreaming", testBidirectionalStreaming),
        ("testClientStreaming", testClientStreaming),
        ("testServerStreaming", testServerStreaming),
        ("testUnary", testUnary),
    ]
}

public func __allTests() -> [XCTestCaseEntry] {
    return [
        testCase(ClientThrowingWhenServerReturningErrorTests.__allTests__ClientThrowingWhenServerReturningErrorTests),
        testCase(GRPCChannelHandlerTests.__allTests__GRPCChannelHandlerTests),
        testCase(GRPCInsecureInteroperabilityTests.__allTests__GRPCInsecureInteroperabilityTests),
        testCase(GRPCSecureInteroperabilityTests.__allTests__GRPCSecureInteroperabilityTests),
        testCase(GRPCStatusMessageMarshallerTests.__allTests__GRPCStatusMessageMarshallerTests),
        testCase(HTTP1ToRawGRPCServerCodecTests.__allTests__HTTP1ToRawGRPCServerCodecTests),
        testCase(LengthPrefixedMessageReaderTests.__allTests__LengthPrefixedMessageReaderTests),
        testCase(NIOClientCancellingTests.__allTests__NIOClientCancellingTests),
        testCase(NIOClientClosedChannelTests.__allTests__NIOClientClosedChannelTests),
        testCase(NIOClientTLSFailureTests.__allTests__NIOClientTLSFailureTests),
        testCase(NIOClientTimeoutTests.__allTests__NIOClientTimeoutTests),
        testCase(NIOFunctionalTestsAnonymousClient.__allTests__NIOFunctionalTestsAnonymousClient),
        testCase(NIOFunctionalTestsInsecureTransport.__allTests__NIOFunctionalTestsInsecureTransport),
        testCase(NIOFunctionalTestsMutualAuthentication.__allTests__NIOFunctionalTestsMutualAuthentication),
        testCase(NIOServerWebTests.__allTests__NIOServerWebTests),
        testCase(ServerDelayedThrowingTests.__allTests__ServerDelayedThrowingTests),
        testCase(ServerErrorTransformingTests.__allTests__ServerErrorTransformingTests),
        testCase(ServerThrowingTests.__allTests__ServerThrowingTests),
    ]
}
#endif
