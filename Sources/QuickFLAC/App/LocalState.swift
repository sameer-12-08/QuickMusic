import SwiftUI

/// A drop-in replacement for `@State`.
///
/// Why this exists: in recent macOS SDKs `@State` is implemented as a Swift *macro*,
/// and the macro's plugin ships with full Xcode but not with the Command Line Tools.
/// Building with only the Command Line Tools then fails with
/// "external macro implementation type 'SwiftUIMacros.StateMacro' could not be found".
///
/// This wrapper stores its value in a plain `State<Value>` (an ordinary type, no
/// macro involved), so it behaves the same: SwiftUI keeps the value alive between
/// redraws, and changing it re-draws the view. `$name` still gives you a Binding.
///
/// Swift concept: a property wrapper is a small struct that controls how a variable
/// is stored and read, a bit like a Python descriptor (`__get__` / `__set__`).
@propertyWrapper
struct LocalState<Value>: DynamicProperty {
    private var storage: State<Value>

    init(wrappedValue: Value) {
        storage = State(initialValue: wrappedValue)
    }

    var wrappedValue: Value {
        get { storage.wrappedValue }
        nonmutating set { storage.wrappedValue = newValue }
    }

    /// What `$name` returns: a get/set pair that sliders and text fields can use.
    var projectedValue: Binding<Value> { storage.projectedValue }
}

// Lets you write `@LocalState private var x: Double?` without an initial value (it starts as nil).
extension LocalState where Value: ExpressibleByNilLiteral {
    init() {
        self.init(wrappedValue: nil)
    }
}
