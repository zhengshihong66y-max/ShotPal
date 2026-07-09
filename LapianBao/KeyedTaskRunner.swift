//
//  KeyedTaskRunner.swift
//  LapianBao
//
//  统一管理 LibraryStore 上按 key 记账的后台任务,收敛原先手工维护的
//  [Key: Task<Void, Never>] 字典:启动去重、取消、完成清账走同一套语义。
//

import Foundation

@MainActor
final class KeyedTaskRunner<Key: Hashable> {
    private var tasks: [Key: Task<Void, Never>] = [:]
    private var generationByKey: [Key: UInt64] = [:]
    private var generation: UInt64 = 0

    var count: Int { tasks.count }
    var isEmpty: Bool { tasks.isEmpty }
    var keys: Dictionary<Key, Task<Void, Never>>.Keys { tasks.keys }

    func isRunning(_ key: Key) -> Bool {
        tasks[key] != nil
    }

    /// 同 key 已有任务时不启动,返回 false。任务体结束后自动清账。
    @discardableResult
    func start(_ key: Key, operation: @escaping @MainActor () async -> Void) -> Bool {
        guard tasks[key] == nil else { return false }
        let token = nextToken(for: key)
        tasks[key] = Task { [weak self] in
            await operation()
            self?.clearIfCurrent(key, token: token)
        }
        return true
    }

    /// 与 start 相同,但任务脱离 MainActor 运行,用于纯计算型后台工作。
    @discardableResult
    func startDetached(
        _ key: Key,
        priority: TaskPriority? = nil,
        operation: @escaping @Sendable () async -> Void
    ) -> Bool where Key: Sendable {
        guard tasks[key] == nil else { return false }
        let token = nextToken(for: key)
        tasks[key] = Task.detached(priority: priority) { [weak self] in
            await operation()
            await self?.clearIfCurrent(key, token: token)
        }
        return true
    }

    /// 先取消同 key 的现有任务再启动新任务。
    func replace(_ key: Key, operation: @escaping @MainActor () async -> Void) {
        cancel(key)
        start(key, operation: operation)
    }

    /// 取消并清账。返回是否确实有任务被取消,供调用方判断状态是否变化。
    @discardableResult
    func cancel(_ key: Key) -> Bool {
        guard let task = tasks[key] else { return false }
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
    func finish(_ key: Key) -> Bool {
        guard tasks[key] != nil else { return false }
        clear(key)
        return true
    }

    /// 等待某个 key 的任务结束;没有任务时立即返回。
    func wait(for key: Key) async {
        await tasks[key]?.value
    }

    private func nextToken(for key: Key) -> UInt64 {
        generation &+= 1
        generationByKey[key] = generation
        return generation
    }

    private func clear(_ key: Key) {
        tasks[key] = nil
        generationByKey[key] = nil
    }

    private func clearIfCurrent(_ key: Key, token: UInt64) {
        guard generationByKey[key] == token else { return }
        clear(key)
    }
}
