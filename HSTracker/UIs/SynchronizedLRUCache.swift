import Foundation

final class SynchronizedLRUCache<Key: Hashable, Value> {
    private let capacity: Int
    private let lock = UnfairLock()
    private var values = [Key: Value]()
    private var accessOrder = [Key]()

    init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    subscript(key: Key) -> Value? {
        get {
            lock.around {
                guard let value = values[key] else {
                    return nil
                }

                touch(key)
                return value
            }
        }
        set {
            lock.around {
                guard let value = newValue else {
                    values.removeValue(forKey: key)
                    accessOrder.removeAll { $0 == key }
                    return
                }

                values[key] = value
                touch(key)

                while values.count > capacity, let leastRecentlyUsed = accessOrder.first {
                    accessOrder.removeFirst()
                    values.removeValue(forKey: leastRecentlyUsed)
                }
            }
        }
    }

    func removeAll() {
        lock.around {
            values.removeAll(keepingCapacity: true)
            accessOrder.removeAll(keepingCapacity: true)
        }
    }

    private func touch(_ key: Key) {
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
    }
}
