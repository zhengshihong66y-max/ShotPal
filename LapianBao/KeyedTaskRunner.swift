//
//  KeyedTaskRunner.swift
//  LapianBao
//
//  统一管理 LibraryStore 上按 key 记账的后台任务,收敛原先手工维护的
//  [Key: Task<Void, Never>] 字典:启动去重、取消、完成清账走同一套语义。
//

import Foundation

@MainActor
final class KeyedTaskRunner {
    // Type-erased keys keep the runner itself non-generic. Swift 6.3.2 crashes
    // while optimizing the synthesized destructor of the former generic class.
    private var tasks: [AnyHashable: Task<Void, Never>] = [:]
    private var generationByKey: [AnyHashable: UInt64] = [:]
    private var generation: UInt64 = 0

    var count: Int { tasks.count }
    var isEmpty: Bool { tasks.isEmpty }

    func keys<Key: Hashable>(of type: Key.Type) -> [Key] {
        tasks.keys.compactMap { $0.base as? Key }
    }

    func isRunning<Key: Hashable>(_ key: Key) -> Bool {
        tasks[AnyHashable(key)] != nil
    }

    /// 同 key 已有任务时不启动,返回 false。任务体结束后自动清账。
    @discardableResult
    func start<Key: Hashable>(_ key: Key, operation: @escaping @MainActor () async -> Void) -> Bool {
        guard tasks[AnyHashable(key)] == nil else { return false }
        let token = nextToken(for: key)
        tasks[AnyHashable(key)] = Task { [weak self] in
            await operation()
            self?.clearIfCurrent(key, token: token)
        }
        return true
    }

    /// 与 start 相同,但任务脱离 MainActor 运行,用于纯计算型后台工作。
    @discardableResult
    func startDetached<Key: Hashable & Sendable>(
        _ key: Key,
        priority: TaskPriority? = nil,
        operation: @escaping @Sendable () async -> Void
    ) -> Bool {
        guard tasks[AnyHashable(key)] == nil else { return false }
        let token = nextToken(for: key)
        tasks[AnyHashable(key)] = Task.detached(priority: priority) { [weak self] in
            await operation()
            await self?.clearIfCurrent(key, token: token)
        }
        return true
    }

    /// 先取消同 key 的现有任务再启动新任务。
    func replace<Key: Hashable>(_ key: Key, operation: @escaping @MainActor () async -> Void) {
        cancel(key)
        start(key, operation: operation)
    }

    /// 取消并清账。返回是否确实有任务被取消,供调用方判断状态是否变化。
    @discardableResult
    func cancel<Key: Hashable>(_ key: Key) -> Bool {
        guard let task = tasks[AnyHashable(key)] else { return false }
        task.cancel()
        clear(key)
        return true
    }

    func cancelAll() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        generationByKey.removeAll()
    }

    /// 不取消、只清账。供把"字典里还有条目"当作仍在进行令牌的完成回调使用,
    /// 返回是否存在条目,对应原先的 `tasks[key] != nil` 判断。
    @discardableResult
    func finish<Key: Hashable>(_ key: Key) -> Bool {
        guard tasks[AnyHashable(key)] != nil else { return false }
        clear(key)
        return true
    }

    /// 等待某个 key 的任务结束;没有任务时立即返回。
    func wait<Key: Hashable>(for key: Key) async {
        await tasks[AnyHashable(key)]?.value
    }

    private func nextToken<Key: Hashable>(for key: Key) -> UInt64 {
        generation &+= 1
        generationByKey[AnyHashable(key)] = generation
        return generation
    }

    private func clear<Key: Hashable>(_ key: Key) {
        tasks[AnyHashable(key)] = nil
        generationByKey[AnyHashable(key)] = nil
    }

    private func clearIfCurrent<Key: Hashable>(_ key: Key, token: UInt64) {
        guard generationByKey[AnyHashable(key)] == token else { return }
        clear(key)
    }
}
