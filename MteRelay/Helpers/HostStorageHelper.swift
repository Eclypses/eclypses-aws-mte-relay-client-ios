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

class HostStorageHelper {
    var hostB64: String!
    var keychainHelper: KeychainHelper!
    var storedHost: StoredHost!
    let keychainKey = "key"
    let keychainAccount: String!
    
    init(hostB64: String) async throws {
        self.hostB64 = hostB64
        self.keychainAccount = self.hostB64
        self.keychainHelper = KeychainHelper(service: keychainKey, account: keychainAccount)
        try loadStoredHost()
    }
    
    func loadStoredHost() throws {
        do {
            let storedHostData = try getStoredHost()
            storedHost = try JSONDecoder().decode(StoredHost.self, from: storedHostData)
        } catch KeychainError.itemNotFound {
            print("No stored Host data found for \(hostB64!)")
        } catch {
            throw "Error loading stored Host data: Error: \(error.localizedDescription)"
        }
    }
    
    func storeStates(hostUrlB64: String, mteHelper: MteHelper) throws {
        let statesToStore = try mteHelper.getPairDictionaryStates()
        let hostToStore = StoredHost(hostUrlB64: hostUrlB64, clientId: RelaySettings.clientId, storedPairs: statesToStore)
        let hostData = try JSONEncoder().encode(hostToStore)
        do {
            try keychainHelper.save(data: hostData)
        } catch KeychainError.duplicateItem {
            try keychainHelper.update(data: hostData)
        }
    }
    
    private func removeStoredStates() throws {
        var hostData: Data!
        do {
            storedHost.storedPairs.removeAll()
            hostData = try JSONEncoder().encode(storedHost)
        try keychainHelper.save(data: hostData)
        } catch KeychainError.duplicateItem {
            try keychainHelper.update(data: hostData)
        }
    }
    
    private func getStoredHost() throws -> Data {
        return try keychainHelper.read()
    }
    
    func removeHost() throws {
        try removeStoredStates()
    }
    
    
}
