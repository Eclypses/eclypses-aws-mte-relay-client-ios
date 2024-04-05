//// The MIT License (MIT)
//
// Copyright (c) Eclypses, Inc.
//
// All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.


import Foundation

public enum MteRelayError: Error {
    case none
    case storeStateError
    case updateRequestError
    case mteInstantiateError
    case mteEncodeError
    case mteDecodeError
    case fileSystemError
    case networkError
}

public enum RelayStatus {
    case noAttempt
    case notPaired
    case paired
    case transmissionSuccessful
    case transmissionFailure
    case error
    case networkFailure
}

enum MteConstants {
    static let GET = "GET"
    static let POST = "POST"
    static let HEAD = "HEAD"
    
    static let RC_ERROR_SERVER_NO_LONGER_PAIRED = "400"
    static let RC_ERROR_UNABLE_TO_AUTHENTICATE = "401"
    static let RC_ERROR_INTERNAL_SERVER_ERROR = "500"
    static let RC_ERROR_ESTABLISHING_CONNECTION_WITH_SERVER = "503"
    static let RC_ERROR_RECEIVED_NO_DATA_FROM_SERVER = "550"
    static let RC_ERROR_HTTP_STATUS_CODE = "560"
}

enum RelayHeaderNames: String, CaseIterable {
    case xMteRelayPairId = "x-mte-relay-pair-id"
    case xMteRelayClientId = "x-mte-relay-client-id"
    case xMteRelayEh = "x-mte-relay-eh"
    case xMteRelay = "x-mte-relay"
}

enum MteSettings {
    static let xMteRelayEh: String = "x-mte-relay-eh"
    static let xMteRelayClientId: String = "x-mte-relay-client-id"
    static let xMteRelayPairId: String = "x-mte-relay-pair-id"
}
