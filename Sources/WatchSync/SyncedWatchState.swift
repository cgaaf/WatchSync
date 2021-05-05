//
//  WatchSync.swift
//  SwiftUIWatchConnectivity
//
//  Created by Chris Gaafary on 5/1/21.
//

import SwiftUI
import WatchConnectivity
import Combine

@propertyWrapper public class SyncedWatchState<Value: Codable> {
    public static subscript<T: ObservableObject>(
        _enclosingInstance instance: T,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<T, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<T, SyncedWatchState>
    ) -> Value {
        get {
            let publisher = instance.objectWillChange as! ObservableObjectPublisher
            // This assumption is definitely not safe to make in
            // production code, but it's fine for this demo purpose:
            publisher.send()
            let valueSubject = instance[keyPath: storageKeyPath].valueSubject
            return valueSubject.value
        }
        set {
            let publisher = instance.objectWillChange as! ObservableObjectPublisher
            // This assumption is definitely not safe to make in
            // production code, but it's fine for this demo purpose:
            publisher.send()

            instance[keyPath: storageKeyPath].send(newValue)
            instance[keyPath: storageKeyPath].valueSubject.value = newValue
        }
    }
    
    private var session: WCSession
    private var cancellables = Set<AnyCancellable>()
    
    // SUBJECTS
    private let dataSubject: PassthroughSubject<Data, Never>
    private let deviceSubject = PassthroughSubject<Device, Never>()
    private let valueSubject: CurrentValueSubject<Value, Error>
    
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
    
    //
    private var receivedData: AnyPublisher<Value, Error> {
        dataSubject
            .removeDuplicates()
            .decode(type: SyncedWatchObject<Value>.self, decoder: JSONDecoder())
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
    
//    public var wrappedValue: Value {
//        get { valueSubject.value }
//        set {
//            send(newValue)
//            valueSubject.value = newValue
//        }
//    }
    @available(*, unavailable,
            message: "@Published can only be applied to classes"
        )
        public var wrappedValue: Value {
            get { fatalError() }
            set { fatalError() }
        }
    
    public var projectedValue: CurrentValueSubject<Value, Error> {
        get { valueSubject }
    }
    
    public init(wrappedValue: Value, session: WCSession = .syncedStateSession, autoRetryEvery timeInterval: TimeInterval = 2) {
        self.session = session
        self.dataSubject = SessionDelegater.syncedStateDelegate.dataSubject
        self.timer = Timer.publish(every: timeInterval, on: .main, in: .default)
        self.valueSubject = CurrentValueSubject(wrappedValue)
        
        receivedData
            .sink(receiveCompletion: valueSubject.send, receiveValue: valueSubject.send)
            .store(in: &cancellables)
    }
    
    private func send(_ object: Value) {
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

public extension CurrentValueSubject {
    func syncWithObject<Observable: ObservableObject>(_ object: Observable) -> AnyCancellable {
        let syncedObject: ObservableObjectPublisher = object.objectWillChange as! ObservableObjectPublisher
        return self
            .replaceError(with: self.value)
            .sink { _ in
                syncedObject.send()
            }
    }
}
