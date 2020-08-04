//
//  DayCodes.swift
//  C19X-SENSOR-iOS
//
//  Created by Freddy Choi on 25/07/2020.
//  Copyright © 2020 C19X. All rights reserved.
//

import Foundation

/**
 Day codes are derived from a shared secret that has been agreed with the central server on registration.
 Given a shared secret, a sequence of forward secure day codes is created by recursively hashing (SHA)
 the hash of the shared secret, and using the hashes in reverse order; a day code is generated by taking
 the first eight bytes of a hash as a long value code. It is cryptographically challenging to predict the next
 code given the previous codes. Each day is allocated a day code up to a finite number of days for simplicity.
 */
protocol DayCodes {
    func day(_ timestamp: Timestamp) -> Day?
    func get(_ timestamp: Timestamp) -> DayCode?
    func seed(_ timestamp: Timestamp) -> (BeaconCodeSeed, Day)?
}

typealias SharedSecret = Data
typealias DayCode = Int64
typealias Day = UInt
typealias BeaconCodeSeed = Int64
typealias Timestamp = Date

class ConcreteDayCodes : DayCodes {
    private let logger = ConcreteSensorLogger(subsystem: "Sensor", category: "Payload.C19X.ConcreteDayCodes")
    private let epoch = ConcreteDayCodes.timeIntervalSince1970("2020-01-01T00:00:00+0000")!
    private var values:[DayCode]
    
    init(_ sharedSecret: SharedSecret) {
        let days = 365 * 5
        values = ConcreteDayCodes.dayCodes(sharedSecret, days: days)
    }
    
    static func timeIntervalSince1970(_ from: String) -> UInt64? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXX"
        guard let date = formatter.date(from: from) else {
            return nil
        }
        return UInt64(date.timeIntervalSince1970)
    }
    
    static func dayCodes(_ sharedSecret: SharedSecret, days: Int) -> [DayCode] {
        var hash = SHA.hash(data: sharedSecret)
        var values = [DayCode](repeating: 0, count: days)
        for i in (0 ... (days - 1)).reversed() {
            values[i] = JavaData.byteArrayToLong(digest: hash)
            let hashData = Data(hash)
            hash = SHA.hash(data: hashData)
        }
        return values
    }
    
    static func beaconCodeSeed(_ dayCode: DayCode) -> BeaconCodeSeed {
        let data = withUnsafeBytes(of: dayCode) { Data($0) }
        let reversed: [UInt8] = [data[0], data[1], data[2], data[3], data[4], data[5], data[6], data[7]]
        let hash = SHA.hash(data: Data(reversed))
        let seed = BeaconCodeSeed(JavaData.byteArrayToLong(digest: hash))
        return seed
    }
    
    func day(_ timestamp: Timestamp) -> Day? {
        let time = UInt64(NSDate(timeIntervalSince1970: timestamp.timeIntervalSince1970).timeIntervalSince1970)
        let (epochDay,_) = (time - epoch).dividedReportingOverflow(by: UInt64(24 * 60 * 60))
        let day = Day(epochDay)
        guard day >= 0, day < values.count else {
            logger.fault("Day out of range")
            return nil
        }
        return day
    }
    
    func get(_ timestamp: Timestamp) -> DayCode? {
        guard let day = day(timestamp) else {
            logger.fault("Day out of range")
            return nil
        }
        return values[Int(day)]
    }
    
    func seed(_ timestamp: Timestamp) -> (BeaconCodeSeed, Day)? {
        guard let day = day(timestamp), let dayCode = get(timestamp) else {
            logger.fault("Day out of range")
            return nil
        }
        let seed = ConcreteDayCodes.beaconCodeSeed(dayCode)
        return (seed, day)
    }
}
