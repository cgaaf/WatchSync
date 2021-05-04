//
//  WatchSync.swift
//  SwiftUIWatchConnectivity
//
//  Created by Chris Gaafary on 5/1/21.
//

import SwiftUI
import WatchConnectivity
import Combine

@propertyWrapper public class SyncedWatchState<T: Codable>: DynamicProperty {
    private var session: WCSession
    private let delegate: WCSessionDelegate
//    private let syncedObject: Observable?
    
    private var cancellables = Set<AnyCancellable>()
    
    // SUBJECTS
    private let dataSubject = PassthroughSubject<Data, Never>()
    private let deviceSubject = PassthroughSubject<Device, Never>()
    private let valueSubject: CurrentValueSubject<T, Error>
    
    // SYNC TIMER RELATED
    private let timer: Timer.TimerPublisher
    private var timerSubscription: AnyCancellable?
    
    // PUBLISHERS
    public var latestDevice: AnyPublisher<Device, Never> {
        deviceSubject
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
    
    // INTERNAL RECORD KEEPING
    // THIS HELPS PREVENT UNNECCESARY AND DUPLICATE NETWORK REQUESTS
    private var cacheDate = Date()
    private var cachedEncodedObjectData: Data?
    
    private var receivedData: AnyPublisher<T, Error> {
        dataSubject
            .removeDuplicates()
            .decode(type: SyncedWatchObject<T>.self, decoder: JSONDecoder())
            .handleEvents(receiveOutput: { syncedObject in
                print("Decoded received object: \(syncedObject.object)")
                print("Object modifcation date: \(syncedObject.dateModified)")
                if self.cacheDate < syncedObject.dateModified {
                    self.deviceSubject.send(.otherDevice)
                }
            })
            .filter({ dataPacket in
                let filtered = self.cacheDate < dataPacket.dateModified
                print("Incoming more recent than cached data: \(filtered)")
                return filtered
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
    
    public var projectedValue: CurrentValueSubject<T, Error> {
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
            .sink(receiveCompletion: valueSubject.send, receiveValue: valueSubject.send)
            .store(in: &cancellables)
    }
    
    public func syncWithObject<Observable: ObservableObject>(_ object: Observable) {
        let syncedObject: ObservableObjectPublisher = object.objectWillChange as! ObservableObjectPublisher
            valueSubject
                .replaceError(with: wrappedValue)
                .sink { _ in
                    syncedObject.send()
                }
                .store(in: &cancellables)
    }
    
    private func send(_ object: T) {
        let now = Date()
        let syncedObject = SyncedWatchObject(dateModified: now, object: object)
        let encodedObject = try! JSONEncoder().encode(syncedObject)
        
        cacheObject(encodedData: encodedObject, cacheDate: now)
        deviceSubject.send(.thisDevice)
        
        if session.isReachable {
            transmit(encodedObject)
        } else {
            print("Session not currently reachable, retrying sync")
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
            print("Succesul transfer: Cancel autoretry")
            self.timerSubscription?.cancel()
        } errorHandler: { error in
            print(error.localizedDescription)
        }
    }
    
    private func cacheObject(encodedData: Data, cacheDate: Date) {
        print("Caching sent data at: \(cacheDate)")
        cachedEncodedObjectData = encodedData
        self.cacheDate = cacheDate
    }
}
