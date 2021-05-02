//
//  WatchSync.swift
//  SwiftUIWatchConnectivity
//
//  Created by Chris Gaafary on 5/1/21.
//

import Foundation
import WatchConnectivity
import Combine

@propertyWrapper public class WatchSync<T: Codable> {
    private var session: WCSession
    private let delegate: WCSessionDelegate
    
    var cancellables = Set<AnyCancellable>()
    
    // SUBJECTS
    private let dataSubject = PassthroughSubject<Data, Never>()
    private let deviceSubject = PassthroughSubject<WCSession.Device, Never>()
    private let valueSubject: CurrentValueSubject<T, Never>
    
    // SYNC TIMER RELATED
    let timer: Timer.TimerPublisher
    var timerSubscription: AnyCancellable?
    
    // PUBLISHERS
    var mostRecentDataChangedByDevice: AnyPublisher<WCSession.Device, Never> {
        deviceSubject
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
    
    // INTERNAL RECORD KEEPING
    // THIS HELPS PREVENT UNNECCESARY AND DUPLICATE NETWORK REQUESTS
    var cacheDate = Date()
    var cachedEncodedObjectData: Data?
    
    var receivedData: AnyPublisher<T, Error> {
        dataSubject
            .removeDuplicates()
            .decode(type: SyncedWatchObject<T>.self, decoder: JSONDecoder())
            .handleEvents(receiveOutput: { syncedObject in
                print("Received data")
                if self.cacheDate < syncedObject.dateModified {
                    self.deviceSubject.send(.otherDevice)
                }
            })
            .filter({ dataPacket in
                self.cacheDate < dataPacket.dateModified
            })
            .map(\.object)
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
    
    public var wrappedValue: T {
        get { valueSubject.value }
        set {
            send(newValue)
            valueSubject.value = newValue
        }
    }
    
    public var projectedValue: CurrentValueSubject<T, Never> {
        get { valueSubject }
    }
    
    public init(wrappedValue: T, session: WCSession = .default, autoRetryFor timeInterval: TimeInterval = 2) {
        self.delegate = SessionDelegater(subject: dataSubject)
        self.session = session
        self.session.delegate = self.delegate
        self.session.activate()
        
        self.timer = Timer.publish(every: timeInterval, on: .main, in: .default)
        
        self.valueSubject = CurrentValueSubject(wrappedValue)
        
        receivedData
            .sink { _ in
                fatalError("This should not error, Figure out error handling")
            } receiveValue: { value in
                self.valueSubject.value = value
            }
            .store(in: &cancellables)

    }
    
    private func send(_ object: T) {
        let syncedObject = SyncedWatchObject(dateModified: cacheDate, object: object)
        let encodedObject = try! JSONEncoder().encode(syncedObject)
        cacheData(encodedObject)
        deviceSubject.send(.thisDevice)
        
        if session.isReachable {
            transmit(encodedObject)
        } else {
            print("Session not current reachable, starting timer")
            timerSubscription = timer
                .autoconnect()
                .sink { _ in
                    if let latestPacketSent = self.cachedEncodedObjectData {
                        self.transmit(latestPacketSent)
                    }
                }
        }
    }
    
    private func transmit(_ data: Data) {
        print("Transmitting")
        session.sendMessageData(data) { _ in
            print("Succesul transfer: Cancel timer")
            self.timerSubscription?.cancel()
        } errorHandler: { error in
            print(error.localizedDescription)
        }
    }
    
    func cacheData(_ data: Data) {
        cachedEncodedObjectData = data
        cacheDate = Date()
    }
}
