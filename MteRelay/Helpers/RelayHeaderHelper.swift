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

struct RelayOptions {
    var clientId: String
    var pairId: String
    var encodeType: String
    var urlIsEncoded: Bool
    var headersAreEncoded: Bool
    var bodyIsEncoded: Bool
}

func formatMteRelayHeader(options: RelayOptions) -> String {
    var args = [String]()
    args.append(options.clientId)
    args.append(options.pairId)
    args.append(options.encodeType == "MTE" ? "0" : "1")
    args.append(options.urlIsEncoded ? "1" : "0")
    args.append(options.headersAreEncoded ? "1" : "0")
    args.append(options.bodyIsEncoded ? "1" : "0")
    
    return args.joined(separator: ",")
}

func parseMteRelayHeader(header: String) -> RelayOptions? { 
    
    let args = header.split(separator: ",").map { String($0) }
    
    guard args.count > 0 else {
        // The header doesn't have any elements
        return nil //TODO: Handle this better
    }
        
    if args.count > 1 {
        return RelayOptions(clientId: args[0],
                            pairId: args[1],
                            encodeType: args[2] == "0" ? "MTE" : "MKE",
                            urlIsEncoded: args[3] == "1",
                            headersAreEncoded: args[4] == "1",
                            bodyIsEncoded: args[5] == "1")
    } else {
        return RelayOptions(clientId: args[0],
                            pairId: "",
                            encodeType: "",
                            urlIsEncoded: false,
                            headersAreEncoded: false,
                            bodyIsEncoded: false)
    }
}

enum EncoderType: String {
    case MTE = "MTE"
    case MKE = "MKE"
}

