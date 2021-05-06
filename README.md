# WatchSync
WatchSync provides a property wrapper to encapsulate basic sharing of a codable object between an iPhone and AppleWatch using Apple's WatchConnectivity framework. 

## How to use
WatchSync exposes the property wrapper @SyncedWatchState which will use Apple's WatchConnectivity framework to pass updates automatically to each device when the value is changed.

Currently, @SyncedWatchState must be used within a class that comforms to the ObservableObject protocol. Consider this as a version of Apple's @Published property wrapper that also publishes changes to the connected device.

In the example below, we have a a Counter object that contains a syncedCount parameter. This class targets both iOS and watchOS and is used by each to update the shared syncedCount variable. SwiftUI views will automatically update when this value is changed (just like @Published).  

```swift
import WatchSync

class Counter: ObservableObject {
    @SyncedWatchState var syncedCount: Int = 0
    
    func increment() {
        syncedCount += 1
    }
    
    func decrement() {
        syncedCount -= 1
    }
}
```

The following SwiftUI View can use this object by accessing the Counter object

```swift
import SwiftUI
import WatchSync

struct ContentView: View {
    @StateObject var counter = Counter()
    
    var labelStyle: some LabelStyle {
        #if os(watchOS)
        return IconOnlyLabelStyle()
        #else
        return DefaultLabelStyle()
        #endif
    }
    
    var body: some View {
        VStack {
            Text("\(counter.syncedCount)")
                .font(.largeTitle)
            
            HStack {
                Button(action: counter.decrement) {
                    Label("Decrement", systemImage: "minus.circle")
                }
                .padding()
                
                Button(action: counter.increment) {
                    Label("Increment", systemImage: "plus.circle.fill")
                }
                .padding()
            }
            .font(.headline)
            .labelStyle(IconOnlyLabelStyle())
        }
    }
}
```

## Limitations
Currently this has been built only with the intent to have one instance per project. It's possible creating multiple instances of the @SyncedWatchState property wrapper but this has not been tested.

Use at your own risk if you intend to use in production. This project is brand new so reliability is unclear. 
