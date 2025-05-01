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

private let logger = PackageLogger.makeLogger(for: PairPool.self)

struct PairPool {
    private var availablePairs: [(key: String, value: Pair)] = []
    private var inUsePairs: [String: Pair] = [:]

    mutating func refill(with pairs: [String: Pair]) {
        availablePairs = pairs.map { ($0.key, $0.value) }
        inUsePairs.removeAll()
    }

    mutating func createNew(count: Int) throws {
        availablePairs.removeAll()
        inUsePairs.removeAll()
        for _ in 0..<count {
            let pair = try Pair()
            availablePairs.append((key: pair.pairId, value: pair))
        }
    }

    mutating func getNextAvailablePair() throws -> (Pair, Bool) {
        if !availablePairs.isEmpty {
            let pairTuple = availablePairs.removeFirst()
            inUsePairs[pairTuple.key] = pairTuple.value
            return (pairTuple.value, false)
        } else {
            let newPair = try Pair()
            inUsePairs[newPair.pairId] = newPair
            return (newPair, true)
        }
    }

    func pair(for id: String) -> Pair? {
        return inUsePairs[id] ?? availablePairs.first(where: { $0.key == id })?.value
    }

    mutating func moveToAvailable(pairId: String) {
        if let pair = inUsePairs.removeValue(forKey: pairId) {
            
            availablePairs.append((key: pairId, value: pair))
            logger.info("Placing Pair \(pairId) in availablePairs")
            if availablePairs.count > Settings.pairPoolSize {
                logger.info("There are \(availablePairs.count - Settings.pairPoolSize) more pairs in use than the PairPool size setting of \(Settings.pairPoolSize).")
            }
        }
    }

    func allPairs() -> [String: Pair] {
        var dict = Dictionary(uniqueKeysWithValues: availablePairs)
        for (key, value) in inUsePairs {
            dict[key] = value
        }
        return dict
    }

    mutating func insertIntoInUse(_ pair: Pair) {
        inUsePairs[pair.pairId] = pair
    }
}
