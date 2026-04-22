import AppKit
import ApplicationServices

// MARK: - Window Grouping
//
// ウインドウグループの状態管理・連動処理を担当する AppState 拡張。
// stored property は AppState.swift 本体に置かれている（`windowGroups`,
// `groupIndexByWindow`, `pendingGroupCandidates`, `groupLinkBadgeController`,
// `windowObservationService`, `isApplyingGroupTransform`, `isApplyingGroupRaise`）。

extension AppState {

    // MARK: - Installation

    /// `start()` から呼ばれる。AX 観察サービスの生成と AppState への接続。
    func installGroupObservation() {
        guard windowObservationService == nil else { return }
        let service = WindowObservationService()
        service.onEvent = { [weak self] event in
            self?.handleGroupObservationEvent(event)
        }
        windowObservationService = service
        installGroupClickMonitor()
    }

    /// `stop()` から呼ばれる。全観察の解除。
    func uninstallGroupObservation() {
        groupPollingTimer?.cancel()
        groupPollingTimer = nil
        groupPollingSourceID = nil
        groupPollingIntendedSourceID = nil
        windowObservationService?.stopAll()
        windowObservationService = nil
        uninstallGroupClickMonitor()
        groupLinkBadgeController?.hide()
        groupLinkBadgeController = nil
        windowGroups.removeAll()
        groupIndexByWindow.removeAll()
        pendingGroupCandidates.removeAll()
    }

    // MARK: - Click monitor (catches intra-app window switches)

    /// CGEventTap でマウスダウンイベントを監視する。
    /// AX 通知（kAXFocusedWindowChangedNotification / kAXMainWindowChangedNotification）は
    /// 一部のシナリオ（特に同一アプリ内のウインドウ切替）で発火しないため、マウスクリック
    /// を直接監視して、クリック直後にフォーカス中ウインドウがグループメンバーかチェックする。
    private func installGroupClickMonitor() {
        guard groupClickEventTap == nil else { return }
        let mask = (1 << CGEventType.leftMouseDown.rawValue)
                 | (1 << CGEventType.rightMouseDown.rawValue)
                 | (1 << CGEventType.leftMouseUp.rawValue)
                 | (1 << CGEventType.rightMouseUp.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let appState = Unmanaged<AppState>.fromOpaque(refcon).takeUnretainedValue()
                let isMouseUp = (type == .leftMouseUp || type == .rightMouseUp)
                DispatchQueue.main.async {
                    if isMouseUp {
                        appState.handleSystemMouseUp()
                    } else {
                        appState.handleSystemMouseDown()
                    }
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        )
        guard let tap = tap else {
            debugLog("WindowGrouping: CGEventTap creation failed (accessibility permission?)")
            return
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        groupClickEventTap = tap
        groupClickEventTapSource = source
        debugLog("WindowGrouping: click monitor installed (mouse down + up)")
    }

    private func uninstallGroupClickMonitor() {
        if let tap = groupClickEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = groupClickEventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        groupClickEventTap = nil
        groupClickEventTapSource = nil
    }

    /// マウスダウン直後に呼ばれる。少し遅延してフォーカス中ウインドウを確認し、
    /// グループメンバーなら raise 連動を発動する。
    func handleSystemMouseDown() {
        // グループが無ければ何もしない（CPU 節約）。
        guard !windowGroups.isEmpty else { return }
        // クリック処理が完了するのを待つ。50ms 程度で十分。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.checkFrontmostForGroupRaise()
        }
    }

    /// マウスアップ直後に呼ばれる。グループドラッグセッション中なら、
    /// 200ms idle を待たず**即座に**ポーリングを停止して resolve を発動する。
    /// これにより release 時のオーバーラップ補正が高速に走る。
    func handleSystemMouseUp() {
        guard groupPollingTimer != nil else { return }
        // 50ms 後にポーリング停止 → resolve。最後の AX イベントが届く時間を確保。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            // まだ動作中なら停止（その間に新しい drag が始まっていなければ）
            if self.groupPollingTimer != nil {
                self.stopGroupPollingTimer()
            }
        }
    }

    /// 現在のフォーカス中ウインドウを取得し、グループメンバーであれば raise 連動を発動。
    private func checkFrontmostForGroupRaise() {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else { return }
        let pid = frontmostApp.processIdentifier
        if pid == getpid() { return }  // Tiley 自身のクリックはスキップ
        guard let cgID = resolveFocusedWindowID(for: pid) else { return }
        guard groupIndexByWindow[cgID] != nil else { return }
        handleGroupMemberRaised(id: cgID)
    }

    // MARK: - Preset apply hook

    /// プリセット適用完了後に呼ばれる。接する辺を検出して候補バッジを提示する。
    /// 既存グループの adjacency は現状のフレームで再計算し、接していないペアは削除する。
    ///
    /// `targetWindowIDs`: プリセットで実際に移動・配置されたウインドウの CGWindowID。
    /// これを指定して、背景にある他の無関係なウインドウ同士の「偶然の接触」を候補から除外する。
    func refreshGroupCandidatesAfterPresetApply(targetWindowIDs: [CGWindowID]) {
        guard accessibilityGranted else {
            debugLog("WindowGrouping: skipping candidate refresh — AX permission not granted")
            return
        }

        debugLog("WindowGrouping: refreshGroupCandidatesAfterPresetApply scheduled (targets=\(targetWindowIDs))")
        // 少し遅延させて AX 側の反映を待つ。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.recomputeGroupsAndCandidates(targetWindowIDs: targetWindowIDs)
        }
    }

    /// 現在のウインドウフレーム（AppKit 座標）を CGWindowID キーで取得する。
    /// **ライブ** AX 値を読む。`target.frame` はキャッシュ値で古いことがあるので使わない。
    private func frameSnapshot(for ids: Set<CGWindowID>) -> [CGWindowID: CGRect] {
        let all = allAvailableFrames()
        var result: [CGWindowID: CGRect] = [:]
        for id in ids {
            if let f = all[id] { result[id] = f }
        }
        return result
    }

    /// 全 `availableWindowTargets` の**ライブ**フレーム（AX から現在値を読む）を
    /// CGWindowID キーで取得する。`target.frame` はキャッシュ値であり、
    /// レイアウトプリセット適用直後は古い値のままの可能性があるので必ずライブ値を使う。
    private func allAvailableFrames() -> [CGWindowID: CGRect] {
        var result: [CGWindowID: CGRect] = [:]
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? 0
        for target in availableWindowTargets where target.cgWindowID != 0 {
            guard let window = target.windowElement else {
                result[target.cgWindowID] = target.frame
                continue
            }
            let (axPos, size) = accessibilityService.readPositionAndSize(of: window)
            guard size.width > 0, size.height > 0 else {
                result[target.cgWindowID] = target.frame
                continue
            }
            let frame = CGRect(
                x: axPos.x,
                y: primaryMaxY - axPos.y - size.height,
                width: size.width,
                height: size.height
            )
            result[target.cgWindowID] = frame
        }
        return result
    }

    /// 既存グループの adjacency を更新、新たな候補バッジを算出してオーバーレイを更新する。
    ///
    /// `targetWindowIDs` が nil の場合は既存グループの再検証のみ行う（候補追加はしない）。
    /// nil でない場合、候補検出はそれらのウインドウ + 既存グループメンバーの範囲に限定する。
    private func recomputeGroupsAndCandidates(targetWindowIDs: [CGWindowID]? = nil) {
        // 対象の絞り込み: プリセットで動かしたウインドウ + 既存グループメンバー
        var candidateScope: Set<CGWindowID> = Set(targetWindowIDs ?? [])
        for group in windowGroups.values {
            candidateScope.formUnion(group.members)
        }

        let frames = allAvailableFrames()
        debugLog("WindowGrouping: recomputeGroupsAndCandidates — totalFrames=\(frames.count) scope=\(candidateScope.count)")
        for (wid, f) in frames where candidateScope.isEmpty || candidateScope.contains(wid) {
            debugLog("WindowGrouping:   window \(wid) frame=\(f)")
        }

        // 既存グループの adjacency を現在のフレームで再検証し、接さなくなったものを削除。
        for (gid, var group) in windowGroups {
            // 存在しない member を除去。
            group.members = group.members.filter { frames[$0] != nil }
            if group.members.count < 2 {
                dissolveGroup(gid)
                continue
            }
            // 内部接触を再計算。
            var retained: [WindowAdjacency] = []
            for adj in group.adjacencies {
                guard let fA = frames[adj.windowA], let fB = frames[adj.windowB] else { continue }
                if let newAdj = WindowAdjacencyDetector.adjacency(a: adj.windowA, frameA: fA, b: adj.windowB, frameB: fB) {
                    retained.append(newAdj)
                }
            }
            group.adjacencies = retained
            // 接触が 1 つも残らない場合はグループ解体。
            if retained.isEmpty {
                dissolveGroup(gid)
                continue
            }
            group.lastKnownFrames = frameSnapshot(for: group.members)
            windowGroups[gid] = group
        }

        // 候補検出: 対象ウインドウに限定した frame 部分集合を使う。
        // gap 設定があるウインドウ配置でも検出できるよう、許容誤差を gap+4pt に広げる。
        let epsilon = max(WindowAdjacencyDetector.defaultEdgeEpsilon, gap + 4.0)

        // targetWindowIDs が nil（空集合）なら候補は検出しない（既存グループの再検証のみ）。
        if targetWindowIDs != nil {
            let scopedFrames = frames.filter { candidateScope.contains($0.key) }
            let detected = WindowAdjacencyDetector.detect(frames: scopedFrames, edgeEpsilon: epsilon)
            debugLog("WindowGrouping: detected \(detected.count) adjacency pair(s) (epsilon=\(epsilon), scopedFrames=\(scopedFrames.count))")
            for adj in detected {
                debugLog("WindowGrouping:   adj windowA=\(adj.windowA) windowB=\(adj.windowB) edgeOfA=\(adj.edgeOfA.rawValue) mid=\(adj.midpoint)")
            }
            // マージ: 既存の pending に新たに検出されたものを追加し、
            // 既存グループ内の adjacency は除外する。
            var merged: [AdjacencyKey: WindowAdjacency] = [:]
            for adj in pendingGroupCandidates {
                merged[adj.unorderedKey] = adj
            }
            for adj in detected {
                let aInGroup = groupIndexByWindow[adj.windowA]
                let bInGroup = groupIndexByWindow[adj.windowB]
                if let a = aInGroup, let b = bInGroup, a == b { continue }
                merged[adj.unorderedKey] = adj
            }
            pendingGroupCandidates = Array(merged.values)
            // 新規候補ごとに検出タイムスタンプを記録し、5秒後のフェードアウトを予約する。
            // また、候補ウインドウの AX を観察開始（移動/リサイズ検知で隣接喪失を即座に反映）。
            let now = CFAbsoluteTimeGetCurrent()
            for adj in pendingGroupCandidates {
                let key = adj.unorderedKey
                if pendingCandidateTimestamps[key] == nil {
                    pendingCandidateTimestamps[key] = now
                    let work = DispatchWorkItem { [weak self] in
                        self?.expirePendingCandidate(key: key)
                    }
                    pendingCandidateFadeItems[key] = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: work)
                }
                observeWindowForCandidate(cgWindowID: adj.windowA)
                observeWindowForCandidate(cgWindowID: adj.windowB)
            }
        }
        debugLog("WindowGrouping: pending candidates after filtering: \(pendingGroupCandidates.count)")

        refreshBadgeOverlays()
    }

    /// タイムアウトまたは隣接喪失により、指定された候補を削除する。
    func expirePendingCandidate(key: AdjacencyKey) {
        let before = pendingGroupCandidates.count
        pendingGroupCandidates.removeAll { $0.unorderedKey == key }
        pendingCandidateTimestamps.removeValue(forKey: key)
        pendingCandidateFadeItems.removeValue(forKey: key)
        if pendingGroupCandidates.count != before {
            refreshBadgeOverlays()
        }
    }

    // MARK: - Link / Unlink

    /// ユーザーが未リンクバッジをタップしたときに呼ぶ。
    /// 既存グループとトランジティブにマージする（merge-on-link）。
    func linkAdjacency(_ adj: WindowAdjacency) {
        let existingA = groupIndexByWindow[adj.windowA]
        let existingB = groupIndexByWindow[adj.windowB]

        let frames = allAvailableFrames()
        let memberMetaA = memberMeta(for: adj.windowA)
        let memberMetaB = memberMeta(for: adj.windowB)
        guard let metaA = memberMetaA, let metaB = memberMetaB else { return }

        switch (existingA, existingB) {
        case (nil, nil):
            // 新規グループを作る。
            let group = WindowGroup(
                members: [adj.windowA, adj.windowB],
                adjacencies: [adj],
                memberMeta: [adj.windowA: metaA, adj.windowB: metaB],
                lastKnownFrames: frameSnapshot(for: [adj.windowA, adj.windowB])
            )
            _ = frames  // reserved for future use
            windowGroups[group.id] = group
            groupIndexByWindow[adj.windowA] = group.id
            groupIndexByWindow[adj.windowB] = group.id
            observeGroupMembers(group)

        case (let gid?, nil):
            windowGroups[gid]?.members.insert(adj.windowB)
            windowGroups[gid]?.adjacencies.append(adj)
            windowGroups[gid]?.memberMeta[adj.windowB] = metaB
            if let frame = frames[adj.windowB] {
                windowGroups[gid]?.lastKnownFrames[adj.windowB] = frame
            }
            groupIndexByWindow[adj.windowB] = gid
            if let group = windowGroups[gid] { observeGroupMembers(group) }

        case (nil, let gid?):
            windowGroups[gid]?.members.insert(adj.windowA)
            windowGroups[gid]?.adjacencies.append(adj)
            windowGroups[gid]?.memberMeta[adj.windowA] = metaA
            if let frame = frames[adj.windowA] {
                windowGroups[gid]?.lastKnownFrames[adj.windowA] = frame
            }
            groupIndexByWindow[adj.windowA] = gid
            if let group = windowGroups[gid] { observeGroupMembers(group) }

        case (let gidA?, let gidB?):
            if gidA == gidB {
                // 既に同一グループ。adjacency だけ追加。
                windowGroups[gidA]?.adjacencies.append(adj)
            } else {
                // 2 つのグループをマージ。
                mergeGroups(into: gidA, from: gidB, bridgingAdjacency: adj)
            }
        }

        pendingGroupCandidates.removeAll {
            $0.unorderedKey == adj.unorderedKey
        }
        refreshBadgeOverlays()
    }

    /// バッジの x を押したとき、もしくはウインドウが閉じられたときに呼ぶ。
    func dissolveGroup(_ groupID: UUID) {
        guard let group = windowGroups.removeValue(forKey: groupID) else { return }
        for id in group.members {
            groupIndexByWindow.removeValue(forKey: id)
            windowObservationService?.stopObserving(cgWindowID: id)
        }
        // 解体後、残るウインドウ同士の接触は再度候補として提示する。
        recomputeGroupsAndCandidates()
    }

    private func mergeGroups(into keepID: UUID, from removeID: UUID, bridgingAdjacency: WindowAdjacency) {
        guard var keep = windowGroups[keepID], let remove = windowGroups[removeID] else { return }
        keep.members.formUnion(remove.members)
        keep.adjacencies.append(contentsOf: remove.adjacencies)
        keep.adjacencies.append(bridgingAdjacency)
        for (k, v) in remove.memberMeta { keep.memberMeta[k] = v }
        for (k, v) in remove.lastKnownFrames { keep.lastKnownFrames[k] = v }
        windowGroups[keepID] = keep
        windowGroups.removeValue(forKey: removeID)
        for id in remove.members { groupIndexByWindow[id] = keepID }
    }

    private func observeGroupMembers(_ group: WindowGroup) {
        guard let service = windowObservationService else { return }
        for id in group.members {
            if let target = availableWindowTargets.first(where: { $0.cgWindowID == id }) {
                service.observe(target: target)
            }
        }
    }

    /// 未リンク候補のウインドウを監視対象に加える。
    /// 移動/リサイズで隣接喪失を検知してバッジを即座にフェードアウトするため。
    private func observeWindowForCandidate(cgWindowID: CGWindowID) {
        guard let service = windowObservationService else { return }
        guard let target = availableWindowTargets.first(where: { $0.cgWindowID == cgWindowID }) else { return }
        service.observe(target: target)
    }

    private func memberMeta(for cgWindowID: CGWindowID) -> WindowGroupMember? {
        guard let target = availableWindowTargets.first(where: { $0.cgWindowID == cgWindowID }) else { return nil }
        return WindowGroupMember(cgWindowID: cgWindowID, processIdentifier: target.processIdentifier)
    }

    // MARK: - Badge overlays

    /// バッジ位置を算出し、オーバーレイを更新する。
    /// バッジごとに個別の小 NSWindow を使うためフルスクリーン透過ウインドウではない。
    ///
    /// フロントモストアプリがグループ/候補の**いずれかのメンバーのアプリ**でない場合、
    /// そのグループ/候補のバッジは隠す。つまり「関連ウインドウが背面に隠れたとき」
    /// バッジも消える。
    /// また、未リンク候補は 5 秒経過すると自動で消える／隣接でなくなると即座に消える。
    /// リンク済バッジはドラッグ/リサイズ中は非表示にする。
    /// `fastHide` が true の場合、バッジが消える際のフェードアウト時間を短縮する
    /// （ドラッグ/リサイズ開始時のように即座に消したいケース用）。
    func refreshBadgeOverlays(fastHide: Bool = false) {
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let now = CFAbsoluteTimeGetCurrent()
        var badges: [GroupLinkBadge] = []

        // リンク済バッジを非表示にすべきか？ → ドラッグ/リサイズ中（ポーリングが動作中）は隠す。
        let isInteracting = groupPollingTimer != nil

        // 隣接判定用にライブフレームを取得。
        let liveFrames = allAvailableFrames()
        let epsilon = max(WindowAdjacencyDetector.defaultEdgeEpsilon, gap + 4.0)

        // 候補（未リンク）
        var expiredKeys: [AdjacencyKey] = []
        for adj in pendingGroupCandidates {
            // タイムアウト判定。
            if let ts = pendingCandidateTimestamps[adj.unorderedKey], now - ts > 5.0 {
                expiredKeys.append(adj.unorderedKey)
                continue
            }
            // 隣接性の再検証: 現在もまだ辺が接しているか。
            if let fA = liveFrames[adj.windowA], let fB = liveFrames[adj.windowB] {
                if WindowAdjacencyDetector.adjacency(a: adj.windowA, frameA: fA, b: adj.windowB, frameB: fB, edgeEpsilon: epsilon) == nil {
                    expiredKeys.append(adj.unorderedKey)
                    continue
                }
            }
            // 前面アプリ判定。
            guard isAdjacencyInFrontmostApp(adj, frontmostPID: frontmostPID) else { continue }
            badges.append(GroupLinkBadge(
                id: adj.unorderedKey, state: .unlinked, center: adj.midpoint, adjacency: adj
            ))
        }
        // 期限切れ/隣接喪失の候補を削除。
        for key in expiredKeys {
            pendingGroupCandidates.removeAll { $0.unorderedKey == key }
            pendingCandidateTimestamps.removeValue(forKey: key)
            pendingCandidateFadeItems.removeValue(forKey: key)?.cancel()
        }

        // グループ内（リンク済）: いずれかのメンバーの PID が frontmost なら表示。
        // ただしドラッグ/リサイズ中は隠す。
        if !isInteracting {
            for group in windowGroups.values {
                let groupIsActive = group.members.contains { cgWindowID in
                    availableWindowTargets.first(where: { $0.cgWindowID == cgWindowID })?.processIdentifier == frontmostPID
                }
                guard groupIsActive else { continue }
                for adj in group.adjacencies {
                    badges.append(GroupLinkBadge(
                        id: adj.unorderedKey, state: .linked, center: adj.midpoint, adjacency: adj
                    ))
                }
            }
        }
        debugLog("WindowGrouping: refreshBadgeOverlays total badges=\(badges.count) frontmostPID=\(frontmostPID ?? -1) isInteracting=\(isInteracting)")

        if groupLinkBadgeController == nil {
            let controller = GroupLinkBadgeController()
            controller.onBadgeClick = { [weak self] badge in
                self?.handleBadgeClick(badge)
            }
            groupLinkBadgeController = controller
        }
        groupLinkBadgeController?.update(badges: badges, fadeOutDuration: fastHide ? 0.15 : nil)
    }

    private func isAdjacencyInFrontmostApp(_ adj: WindowAdjacency, frontmostPID: pid_t?) -> Bool {
        guard let frontmostPID else { return false }
        let pidA = availableWindowTargets.first(where: { $0.cgWindowID == adj.windowA })?.processIdentifier
        let pidB = availableWindowTargets.first(where: { $0.cgWindowID == adj.windowB })?.processIdentifier
        return pidA == frontmostPID || pidB == frontmostPID
    }

    private func handleBadgeClick(_ badge: GroupLinkBadge) {
        switch badge.state {
        case .unlinked:
            linkAdjacency(badge.adjacency)
        case .linked:
            unlinkAdjacency(badge.adjacency)
        }
    }

    /// 指定された adjacency のみをグループから削除する。
    /// 削除後にグループが非連結になった場合は、連結成分ごとに分離する。
    /// 連結成分のメンバーが 1 つしかない場合は（= 孤立した）グループから除外する。
    func unlinkAdjacency(_ adj: WindowAdjacency) {
        guard let gid = groupIndexByWindow[adj.windowA] ?? groupIndexByWindow[adj.windowB] else { return }
        guard var group = windowGroups[gid] else { return }

        // 該当 adjacency を削除。
        group.adjacencies.removeAll { $0.unorderedKey == adj.unorderedKey }

        // 残りの adjacency で連結成分を求める。
        let components = connectedComponents(members: group.members, adjacencies: group.adjacencies)

        if components.count == 1 {
            // 依然として完全に連結 → そのまま更新。
            windowGroups[gid] = group
        } else {
            // 複数の連結成分に分裂 → グループを分離して再構築。
            windowGroups.removeValue(forKey: gid)
            for id in group.members {
                groupIndexByWindow.removeValue(forKey: id)
            }
            for component in components {
                let componentAdjacencies = group.adjacencies.filter {
                    component.contains($0.windowA) && component.contains($0.windowB)
                }
                if component.count >= 2 && !componentAdjacencies.isEmpty {
                    // 新しいグループとして再構築。
                    let newGroup = WindowGroup(
                        id: UUID(),
                        members: component,
                        adjacencies: componentAdjacencies,
                        memberMeta: group.memberMeta.filter { component.contains($0.key) },
                        lastKnownFrames: group.lastKnownFrames.filter { component.contains($0.key) }
                    )
                    windowGroups[newGroup.id] = newGroup
                    for id in component {
                        groupIndexByWindow[id] = newGroup.id
                    }
                } else {
                    // 孤立メンバー → グループ所属を解除、監視停止。
                    for id in component {
                        windowObservationService?.stopObserving(cgWindowID: id)
                    }
                }
            }
        }
        refreshBadgeOverlays()
    }

    /// メンバー集合と adjacency のリストから、各連結成分（互いに隣接関係で繋がる部分集合）を返す。
    private func connectedComponents(members: Set<CGWindowID>, adjacencies: [WindowAdjacency]) -> [Set<CGWindowID>] {
        var visited: Set<CGWindowID> = []
        var components: [Set<CGWindowID>] = []
        for start in members {
            if visited.contains(start) { continue }
            var component: Set<CGWindowID> = []
            var stack: [CGWindowID] = [start]
            while let current = stack.popLast() {
                if visited.contains(current) { continue }
                visited.insert(current)
                component.insert(current)
                for adj in adjacencies {
                    if adj.windowA == current && !visited.contains(adj.windowB) {
                        stack.append(adj.windowB)
                    } else if adj.windowB == current && !visited.contains(adj.windowA) {
                        stack.append(adj.windowA)
                    }
                }
            }
            components.append(component)
        }
        return components
    }

    // MARK: - AX Event handling

    /// `WindowObservationService` からのイベントをルーティングする。
    ///
    /// 移動・リサイズ系イベントは**ポーリングのトリガーとして使うだけ**で、
    /// 実際の連動処理は `pollGroupSource()` が 60Hz で走査する。
    /// AX 通知は粗い間隔（100～400ms）で届き、ドラッグ中の連続追従には不十分なため。
    ///
    /// 未リンク候補（pendingGroupCandidates）のウインドウが動いた場合は
    /// `refreshBadgeOverlays()` を呼んで隣接性を再評価し、接していなければ
    /// 候補から削除する（= バッジがフェードアウト）。
    func handleGroupObservationEvent(_ event: WindowObservationService.Event) {
        switch event {
        case .moved(let id, _), .resized(let id, _):
            if isApplyingGroupTransform { return }
            // AX エコー判定：直近で setFrame したウインドウの event で、かつ live frame が
            // 我々が設定した frame と一致するなら、それはエコー。process しない。
            // 一致しない場合（ユーザーが動かした）は通常通り処理。
            if let entry = recentlySetFrames[id], CFAbsoluteTimeGetCurrent() - entry.time < 2.0 {
                if let live = liveFrame(of: id), Self.framesMatch(live, entry.frame, tolerance: 2) {
                    return  // echo
                }
                // 一致しない＝ユーザー入力で上書きされた。エントリを削除して以降通常処理。
                recentlySetFrames.removeValue(forKey: id)
            }
            let isGroupMember = groupIndexByWindow[id] != nil
            let isPendingCandidate = pendingGroupCandidates.contains { $0.windowA == id || $0.windowB == id }

            if isGroupMember {
                // 新規セッション開始時、intended source を記録（mid-session で変わらない）。
                if groupPollingTimer == nil {
                    groupPollingIntendedSourceID = id
                }
                groupPollingSourceID = id
                startOrResetGroupPollingTimer()
            } else if isPendingCandidate {
                // 候補の片方が動いた → 隣接性の再評価（非隣接なら候補から除外）。
                refreshBadgeOverlays()
            }
        case .destroyed(let id):
            // グループメンバーと候補のどちらで参照されていても整理する。
            if groupIndexByWindow[id] != nil {
                handleMemberDestroyed(id: id)
            }
            let removedAny = pendingGroupCandidates.contains { $0.windowA == id || $0.windowB == id }
            if removedAny {
                pendingGroupCandidates.removeAll { $0.windowA == id || $0.windowB == id }
                refreshBadgeOverlays()
            }
        case .raised(let id):
            handleGroupMemberRaised(id: id)
        }
    }

    // MARK: - Polling-based linkage

    private func startOrResetGroupPollingTimer() {
        groupPollingLastChangeAt = CFAbsoluteTimeGetCurrent()
        if groupPollingTimer != nil { return }
        groupPollingTickCount = 0
        let timer = DispatchSource.makeTimerSource(queue: .main)
        // 8ms ≒ 120Hz でポーリング。tick あたりの作業はバッジ更新を省略して軽くする。
        timer.schedule(deadline: .now(), repeating: .milliseconds(8), leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in
            self?.pollGroupSource()
        }
        timer.resume()
        groupPollingTimer = timer
        // 対話開始時、リンク済バッジを**高速に**隠す。
        refreshBadgeOverlays(fastHide: true)
    }

    private func stopGroupPollingTimer() {
        // **真のドラッグ元** (intended source) を release 時の補正に使う。
        // groupPollingSourceID は AX echo で mid-session に follower 等に切り替わる
        // ことがあるが、intendedSourceID はセッション開始時の値で固定されるため、
        // ユーザーが実際にドラッグした窓を確実に指す。
        let lastSourceID = groupPollingIntendedSourceID ?? groupPollingSourceID
        groupPollingTimer?.cancel()
        groupPollingTimer = nil
        groupPollingSourceID = nil
        groupPollingIntendedSourceID = nil

        // ドラッグ中に source がフォロワーの最小幅/高さを超えて食い込んでいた場合
        // （ウインドウが重なり合っている状態）、ドラッグ離したタイミングで
        // source 側を縮めて接点まで戻す。
        if let lastSourceID {
            resolveAdjacencyOverlapsOnRelease(lastSourceID: lastSourceID)
        }

        // **重要**: ドラッグ中はフォロワーの `lastKnownFrames` に「理想値」（min-width
        // クランプ前の負の幅など）を保存しているが、ドラッグ離した時点でそれを実際の
        // フレームに同期しないと、次のドラッグ開始時の delta 計算が誤差（overshoot/gap）
        // を含む。source は `resolveAdjacencyOverlapsOnRelease` で補正済みの値が
        // 既にキャッシュに入っているので上書きしない（AX の反映遅延で live が古いため）。
        for (gid, var group) in windowGroups {
            for member in group.members where member != lastSourceID {
                if let live = liveFrame(of: member) {
                    group.lastKnownFrames[member] = live
                }
            }
            windowGroups[gid] = group
        }

        // 対話終了後、各グループの adjacency 座標を最新フレームで再計算してから
        // 隠されていたリンク済バッジを再表示する（バッジ位置が新しい辺位置に追従する）。
        for gid in windowGroups.keys {
            recomputeAdjacenciesForGroup(gid)
        }
        refreshBadgeOverlays()
    }

    /// ドラッグ離し時の 2 パターンの補正：
    ///
    /// **A. source が follower に食い込んで重なり**（follower が min 幅に達し、
    ///    source がそれを超えて押し込んだ場合）→ source を接点まで戻す
    ///
    /// **B. source の拡大で follower が min 幅に達し、アプリがサイズ強制で follower の
    ///    非接触辺（maxX/minX/maxY/minY）を元の位置から押し出した**（例：左を広げて
    ///    右ウインドウが最小幅まで縮んだ後、右端が右にはみ出す）
    ///    → follower を非接触辺が元位置に戻るようシフトし、source の接触辺を follower の
    ///       新しい接触辺に合わせる
    private func resolveAdjacencyOverlapsOnRelease(lastSourceID: CGWindowID) {
        guard let gid = groupIndexByWindow[lastSourceID],
              var group = windowGroups[gid] else { return }

        var didFix = false
        for adj in group.adjacencies {
            guard adj.windowA == lastSourceID || adj.windowB == lastSourceID else { continue }
            let otherID = (adj.windowA == lastSourceID) ? adj.windowB : adj.windowA
            let sourceEdge: WindowAdjacency.Edge = (adj.windowA == lastSourceID) ? adj.edgeOfA : adj.edgeOfA.opposite

            guard let sourceFrame = liveFrame(of: lastSourceID),
                  let otherFrame = liveFrame(of: otherID),
                  let otherCached = group.lastKnownFrames[otherID] else { continue }

            // === パターン B: follower が非接触辺をオーバーシュート ===
            // follower の「固定されているはず」の辺（source から遠い側）が、キャッシュの
            // 元位置から外れていたら、follower をシフトして元位置に戻す。
            var followerFixed = otherFrame
            var followerShifted = false
            switch sourceEdge {
            case .right:
                // follower は右側。maxX は固定されているべき。
                // アプリの min width 強制で maxX が右へ押し出されると otherFrame.maxX > otherCached.maxX
                if otherFrame.maxX > otherCached.maxX + 1 {
                    followerFixed.origin.x = otherCached.maxX - otherFrame.width
                    followerShifted = true
                }
            case .left:
                // follower は左側。minX は固定されているべき。
                if otherFrame.minX < otherCached.minX - 1 {
                    followerFixed.origin.x = otherCached.minX
                    // follower が左へ押し出された場合、origin を戻すだけで maxX も追随
                    followerShifted = true
                }
            case .top:
                // follower は上側。maxY は固定。
                if otherFrame.maxY > otherCached.maxY + 1 {
                    followerFixed.origin.y = otherCached.maxY - otherFrame.height
                    followerShifted = true
                }
            case .bottom:
                // follower は下側。minY は固定。
                if otherFrame.minY < otherCached.minY - 1 {
                    followerFixed.origin.y = otherCached.minY
                    followerShifted = true
                }
            }

            if followerShifted {
                debugLog("WindowGrouping: follower overshoot — shifting \(otherID) to \(followerFixed)")
                isApplyingGroupTransform = true
                moveMemberWindow(cgWindowID: otherID, to: followerFixed)
                group.lastKnownFrames[otherID] = followerFixed
                didFix = true
            }

            // === パターン A + B の合流: 接触辺のミスマッチ補正 ===
            // 2 つのケースを区別する：
            //   - **オーバーラップ**: source の接触辺が follower 領域に食い込んでいる → source を縮める
            //   - **ギャップ**: source と follower の間に隙間がある → follower を広げる（source を広げない）
            let targetFollower = followerShifted ? followerFixed : otherFrame

            // 接触辺の補正：最大 3 回リトライして、各回で live follower を再読み取り
            // して contact を再計算（フォロワーがアプリの動的レイアウトで微動した
            // 場合に対応）。
            let tol: CGFloat = 0.5
            for retry in 0..<3 {
                guard let liveFollower = liveFrame(of: otherID),
                      let liveSource = liveFrame(of: lastSourceID) else { break }
                let liveTarget = followerShifted ? followerFixed : liveFollower

                var srcCorr: CGRect? = nil
                var followerCorr: CGRect? = nil

                switch sourceEdge {
                case .right:
                    let sourceContact = liveSource.maxX
                    let followerContact = liveTarget.minX
                    if sourceContact > followerContact + tol {
                        var c = liveSource
                        c.size.width = max(50, followerContact - liveSource.minX)
                        srcCorr = c
                    } else if sourceContact < followerContact - tol {
                        var c = liveTarget
                        c.origin.x = sourceContact
                        c.size.width = max(50, liveTarget.maxX - sourceContact)
                        followerCorr = c
                    }
                case .left:
                    let sourceContact = liveSource.minX
                    let followerContact = liveTarget.maxX
                    if sourceContact < followerContact - tol {
                        var c = liveSource
                        c.origin.x = followerContact
                        c.size.width = max(50, liveSource.maxX - followerContact)
                        srcCorr = c
                    } else if sourceContact > followerContact + tol {
                        var c = liveTarget
                        c.size.width = max(50, sourceContact - liveTarget.minX)
                        followerCorr = c
                    }
                case .top:
                    let sourceContact = liveSource.maxY
                    let followerContact = liveTarget.minY
                    if sourceContact > followerContact + tol {
                        var c = liveSource
                        c.size.height = max(50, followerContact - liveSource.minY)
                        srcCorr = c
                    } else if sourceContact < followerContact - tol {
                        var c = liveTarget
                        c.origin.y = sourceContact
                        c.size.height = max(50, liveTarget.maxY - sourceContact)
                        followerCorr = c
                    }
                case .bottom:
                    let sourceContact = liveSource.minY
                    let followerContact = liveTarget.maxY
                    if sourceContact < followerContact - tol {
                        var c = liveSource
                        c.origin.y = followerContact
                        c.size.height = max(50, liveSource.maxY - followerContact)
                        srcCorr = c
                    } else if sourceContact > followerContact + tol {
                        var c = liveTarget
                        c.size.height = max(50, sourceContact - liveTarget.minY)
                        followerCorr = c
                    }
                }

                if srcCorr == nil && followerCorr == nil {
                    debugLog("WindowGrouping: resolve stable after retry=\(retry)")
                    break  // 既に整合
                }
                isApplyingGroupTransform = true
                if let c = srcCorr {
                    debugLog("WindowGrouping: resolve overlap (\(sourceEdge.rawValue)) retry=\(retry) source=\(lastSourceID) corrected=\(c)")
                    robustMoveWindow(cgWindowID: lastSourceID, to: c)
                    group.lastKnownFrames[lastSourceID] = c
                }
                if let c = followerCorr {
                    debugLog("WindowGrouping: resolve gap (\(sourceEdge.rawValue)) retry=\(retry) follower=\(otherID) corrected=\(c)")
                    robustMoveWindow(cgWindowID: otherID, to: c)
                    group.lastKnownFrames[otherID] = c
                }
                didFix = true
            }
        }
        windowGroups[gid] = group

        // AX エコー吸収のため 300ms フラグを保持してから解除。
        if didFix {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.isApplyingGroupTransform = false
            }
        }
    }

    /// 60Hz で呼ばれる。ソースウインドウのライブフレームを読み、
    /// 前回からの差分があればフォロワーに連動反映する。
    private func pollGroupSource() {
        guard let sourceID = groupPollingSourceID else {
            stopGroupPollingTimer()
            return
        }
        guard let gid = groupIndexByWindow[sourceID],
              var group = windowGroups[gid] else {
            stopGroupPollingTimer()
            return
        }
        if isApplyingGroupTransform { return }
        guard let newFrame = liveFrame(of: sourceID) else { return }
        guard let oldFrame = group.lastKnownFrames[sourceID] else {
            group.lastKnownFrames[sourceID] = newFrame
            windowGroups[gid] = group
            return
        }

        let originChanged = abs(oldFrame.origin.x - newFrame.origin.x) > 0.5
            || abs(oldFrame.origin.y - newFrame.origin.y) > 0.5
        let sizeChanged = abs(oldFrame.size.width - newFrame.size.width) > 0.5
            || abs(oldFrame.size.height - newFrame.size.height) > 0.5

        if !originChanged && !sizeChanged {
            // アイドル。最後の変化から 200ms 経過したら停止。
            if CFAbsoluteTimeGetCurrent() - groupPollingLastChangeAt > 0.2 {
                stopGroupPollingTimer()
            }
            return
        }

        groupPollingLastChangeAt = CFAbsoluteTimeGetCurrent()
        groupPollingTickCount += 1
        isApplyingGroupTransform = true
        defer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.isApplyingGroupTransform = false
            }
        }

        if sizeChanged {
            applyGroupResize(&group, sourceID: sourceID, oldFrame: oldFrame, newFrame: newFrame)
        } else {
            let delta = CGSize(
                width: newFrame.origin.x - oldFrame.origin.x,
                height: newFrame.origin.y - oldFrame.origin.y
            )
            applyGroupTranslation(&group, sourceID: sourceID, delta: delta)
        }

        // ソースのフレームは live 値で更新（ユーザー操作の直接結果）。
        group.lastKnownFrames[sourceID] = newFrame
        windowGroups[gid] = group

        // バッジは対話中は隠れているので、座標再計算とバッジ更新は省略する
        // （tick 軽量化）。対話終了時の `stopGroupPollingTimer` で再計算する。
    }

    /// 指定ウインドウの現フレーム（AppKit 座標、ライブ AX 値）を返す。
    private func liveFrame(of cgWindowID: CGWindowID) -> CGRect? {
        guard let target = availableWindowTargets.first(where: { $0.cgWindowID == cgWindowID }),
              let window = target.windowElement else { return nil }
        let (axPos, size) = accessibilityService.readPositionAndSize(of: window)
        guard size.width > 0, size.height > 0 else { return nil }
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(
            x: axPos.x,
            y: primaryMaxY - axPos.y - size.height,
            width: size.width,
            height: size.height
        )
    }

    private func applyGroupTranslation(_ group: inout WindowGroup, sourceID: CGWindowID, delta: CGSize) {
        for member in group.members where member != sourceID {
            guard let oldFrame = group.lastKnownFrames[member] else { continue }
            let newFrame = oldFrame.offsetBy(dx: delta.width, dy: delta.height)
            moveMemberWindow(cgWindowID: member, to: newFrame)
            // プログラム的に適用したフレームを即座にキャッシュへ反映。
            // AX の反映遅延でライブ値を読むと古い値が返って累積誤差となるため。
            group.lastKnownFrames[member] = newFrame
        }
        // 4 tick に 1 回だけ Z-order の補正を入れて軽量化（4 × 8ms = 32ms ≒ 30Hz）。
        if groupPollingTickCount % 4 == 0 {
            for member in group.members where member != sourceID {
                orderFollowerBelowSource(followerID: member, sourceID: sourceID)
            }
            raiseSourceWindow(sourceID: sourceID)
        }
    }

    private func applyGroupResize(_ group: inout WindowGroup, sourceID: CGWindowID, oldFrame sourceOld: CGRect, newFrame sourceNew: CGRect) {
        let dLeft = sourceNew.minX - sourceOld.minX
        let dRight = sourceNew.maxX - sourceOld.maxX
        let dTop = sourceNew.maxY - sourceOld.maxY
        let dBottom = sourceNew.minY - sourceOld.minY
        debugLog("WindowGrouping:   resize deltas dLeft=\(dLeft) dRight=\(dRight) dTop=\(dTop) dBottom=\(dBottom)")

        // 「接する辺と同じ長さ」を判定する許容誤差。
        let parallelMatchTolerance: CGFloat = max(WindowAdjacencyDetector.defaultEdgeEpsilon, gap + 4.0)

        // ソースに接する adjacency を先に処理。
        for adj in group.adjacencies {
            let (otherID, sourceEdge): (CGWindowID, WindowAdjacency.Edge)
            if adj.windowA == sourceID {
                otherID = adj.windowB
                sourceEdge = adj.edgeOfA
            } else if adj.windowB == sourceID {
                otherID = adj.windowA
                sourceEdge = adj.edgeOfA.opposite
            } else {
                continue
            }
            guard let otherOld = group.lastKnownFrames[otherID] else { continue }

            var newMinX = otherOld.minX
            var newMaxX = otherOld.maxX
            var newMinY = otherOld.minY
            var newMaxY = otherOld.maxY

            // 1. 接する辺（adjacent edge）の連動
            switch sourceEdge {
            case .right:
                newMinX = otherOld.minX + dRight
            case .left:
                newMaxX = otherOld.maxX + dLeft
            case .top:
                newMinY = otherOld.minY + dTop
            case .bottom:
                newMaxY = otherOld.maxY + dBottom
            }

            // 2. 垂直方向の辺の連動（「接する辺と同じ長さ」の場合）
            switch sourceEdge {
            case .right, .left:
                let sharesBottom = abs(sourceOld.minY - otherOld.minY) <= parallelMatchTolerance
                let sharesTop = abs(sourceOld.maxY - otherOld.maxY) <= parallelMatchTolerance
                if sharesBottom { newMinY = otherOld.minY + dBottom }
                if sharesTop { newMaxY = otherOld.maxY + dTop }
            case .top, .bottom:
                let sharesLeft = abs(sourceOld.minX - otherOld.minX) <= parallelMatchTolerance
                let sharesRight = abs(sourceOld.maxX - otherOld.maxX) <= parallelMatchTolerance
                if sharesLeft { newMinX = otherOld.minX + dLeft }
                if sharesRight { newMaxX = otherOld.maxX + dRight }
            }

            // 4 辺からフレームを再構築。適用用は 50pt でクランプ、キャッシュは
            // クランプ前の理想値を保存（戻しドラッグ時の誤差回避のため）。
            let idealWidth = newMaxX - newMinX
            let idealHeight = newMaxY - newMinY
            let idealFrame = CGRect(x: newMinX, y: newMinY, width: idealWidth, height: idealHeight)

            let applyWidth = max(50, idealWidth)
            let applyHeight = max(50, idealHeight)
            let desiredFrame = CGRect(x: newMinX, y: newMinY, width: applyWidth, height: applyHeight)

            // 「非接触辺を厳密に保つ」セッターを使う：
            // size を先にセット → アプリが実際に採用した size を読み取り → そのサイズで
            // 非接触辺が固定されるよう position を計算してセット。
            // これでアプリが min サイズを強制してきても follower の固定辺がドリフトしない。
            let preservedEdgeValue: CGFloat
            switch sourceEdge {
            case .right:  preservedEdgeValue = otherOld.maxX
            case .left:   preservedEdgeValue = otherOld.minX
            case .top:    preservedEdgeValue = otherOld.maxY
            case .bottom: preservedEdgeValue = otherOld.minY
            }
            guard let target = availableWindowTargets.first(where: { $0.cgWindowID == otherID }),
                  let window = target.windowElement else { continue }
            _ = accessibilityService.setFrameLightweightPreservingEdge(
                desiredFrame,
                preservingEdge: sourceEdge,
                edgeValue: preservedEdgeValue,
                on: target.screenFrame,
                for: window
            )
            // AX エコー抑制用に最終的に適用した frame を記録。
            // setFrameLightweightPreservingEdge は size を先に setting し
            // actualSize を読み取って position を決めるので、最終 frame は
            // (preservedEdge - actualSize) からは正確には分からない。
            // 簡易的に desiredFrame を記録（許容誤差内で echo 判定可能）。
            recentlySetFrames[otherID] = (desiredFrame, CFAbsoluteTimeGetCurrent())
            group.lastKnownFrames[otherID] = idealFrame

            // 検証＋補正パス：size-first 法でも一部のアプリでは AX 読み取りが
            // 即時反映されないため、適用後に live を読んで非接触辺がずれていれば
            // 強制的にシフトで戻す。最大 3 回リトライして安定させる。
            for _ in 0..<3 {
                guard let live = liveFrame(of: otherID) else { break }
                let actualEdge: CGFloat
                switch sourceEdge {
                case .right:  actualEdge = live.maxX
                case .left:   actualEdge = live.minX
                case .top:    actualEdge = live.maxY
                case .bottom: actualEdge = live.minY
                }
                if abs(actualEdge - preservedEdgeValue) <= 0.5 { break }  // 安定
                var c = live
                switch sourceEdge {
                case .right:  c.origin.x = preservedEdgeValue - live.width
                case .left:   c.origin.x = preservedEdgeValue
                case .top:    c.origin.y = preservedEdgeValue - live.height
                case .bottom: c.origin.y = preservedEdgeValue
                }
                accessibilityService.setFrameLightweight(c, on: target.screenFrame, for: window)
            }
        }
        // source オーバードラッグ（follower への食い込み）は per-tick では補正しない。
        // ドラッグ離し時に `resolveAdjacencyOverlapsOnRelease` で一括補正する。
        // per-tick で補正すると：
        //   - source とアプリ（ユーザーの mouse）の間で fight が発生
        //   - cache-source が overwrite されて source の delta が誤差を含む
        //   - follower の補正にも悪影響を与える

        // 4 tick に 1 回だけ Z-order 補正と raise を行う（軽量化）。
        if groupPollingTickCount % 4 == 0 {
            for adj in group.adjacencies {
                let otherID = (adj.windowA == sourceID) ? adj.windowB : adj.windowA
                if otherID != sourceID {
                    orderFollowerBelowSource(followerID: otherID, sourceID: sourceID)
                }
            }
            raiseSourceWindow(sourceID: sourceID)
        }
    }

    /// ソースウインドウを AXRaise で最前面に保つ。
    /// ポーリング中の move/resize で呼ばれる。ソースのアプリは既にアクティブなので
    /// クロスアプリの切替は起こらず、ちらつきもない。
    private func raiseSourceWindow(sourceID: CGWindowID) {
        guard let target = availableWindowTargets.first(where: { $0.cgWindowID == sourceID }) else { return }
        guard let window = target.windowElement else { return }
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }

    /// ドラッグ離し時の補正など、**確実にアプリに適用させたい**セット用。
    /// `setFrame`（pre-nudge + bounce + 位置補正などの dance）を使い、
    /// 適用後に live を読み取って verify、ずれていればリトライする。
    private func robustMoveWindow(cgWindowID: CGWindowID, to frame: CGRect) {
        guard let target = availableWindowTargets.first(where: { $0.cgWindowID == cgWindowID }),
              let window = target.windowElement else { return }
        // 最大 3 回リトライしてアプリに確実に適用させる。
        for attempt in 0..<3 {
            do {
                try accessibilityService.setFrame(frame, on: target.screenFrame, for: window)
            } catch {
                debugLog("robustMoveWindow attempt=\(attempt) error: \(error)")
            }
            // verify
            if let live = liveFrame(of: cgWindowID) {
                let match = Self.framesMatch(live, frame, tolerance: 2)
                debugLog("robustMoveWindow attempt=\(attempt) target=\(frame) live=\(live) match=\(match)")
                if match { break }
            }
        }
        recentlySetFrames[cgWindowID] = (frame, CFAbsoluteTimeGetCurrent())
    }

    private func moveMemberWindow(cgWindowID: CGWindowID, to frame: CGRect) {
        guard let target = availableWindowTargets.first(where: { $0.cgWindowID == cgWindowID }),
              let window = target.windowElement else { return }
        // ドラッグ中の連続適用向けに軽量セットを使う。
        // 通常の `setFrame` は pre-nudge/bounce など多くの AX 呼び出しを行うため、
        // 60Hz で繰り返すとフォロワーが視覚的にチラつく。
        accessibilityService.setFrameLightweight(frame, on: target.screenFrame, for: window)
        // AX エコー抑制用に setFrame した内容を記録（handleGroupObservationEvent で
        // フレーム比較によって echo を判定する）。
        recentlySetFrames[cgWindowID] = (frame, CFAbsoluteTimeGetCurrent())
    }

    /// 2 つのフレームが許容誤差内で一致するか判定する。AX エコー検出用。
    static func framesMatch(_ a: CGRect, _ b: CGRect, tolerance: CGFloat) -> Bool {
        return abs(a.minX - b.minX) <= tolerance
            && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance
            && abs(a.height - b.height) <= tolerance
    }

    /// フォロワー移動後、ソースの直下に Z-order を置き直す。
    /// AX 経由の移動で一部アプリがウインドウを自動的に前面化することがあり、
    /// これを即座に是正することでユーザーのドラッグ対象がちらつかず前面を保てる。
    private func orderFollowerBelowSource(followerID: CGWindowID, sourceID: CGWindowID) {
        guard CGSPrivate.isOrderWindowAvailable else { return }
        CGSPrivate.orderWindow(followerID, mode: CGSPrivate.kCGSOrderBelow, relativeTo: sourceID)
    }

    private func recomputeAdjacenciesForGroup(_ groupID: UUID) {
        guard var group = windowGroups[groupID] else { return }
        let frames = frameSnapshot(for: group.members)
        var updated: [WindowAdjacency] = []
        // 既存 adjacency は**ドロップしない**。リサイズ中はフォロワーの AX 反映が遅れて
        // 一時的に辺が離れて見えるが、我々のリンク関係は維持したい。
        // 各 adjacency の contactCoordinate / overlap は現在のフレームから再計算する
        // （バッジ位置追従用）。検出ロジックが接触と認めない場合でも、
        // エッジ関係 (edgeOfA) は保持したまま座標だけ近似的に更新する。
        for adj in group.adjacencies {
            guard let fA = frames[adj.windowA], let fB = frames[adj.windowB] else {
                updated.append(adj)
                continue
            }
            updated.append(recomputedCoordinate(for: adj, frameA: fA, frameB: fB))
        }
        group.adjacencies = updated
        windowGroups[groupID] = group
    }

    /// 与えた adjacency のエッジ関係 (edgeOfA) を保持しつつ、
    /// 現在のフレームから `contactCoordinate` と `overlapStart/End` を更新した
    /// 新しい `WindowAdjacency` を返す。
    private func recomputedCoordinate(for adj: WindowAdjacency, frameA: CGRect, frameB: CGRect) -> WindowAdjacency {
        let contact: CGFloat
        let overlapStart: CGFloat
        let overlapEnd: CGFloat

        switch adj.edgeOfA {
        case .right:
            contact = (frameA.maxX + frameB.minX) / 2
            overlapStart = max(frameA.minY, frameB.minY)
            overlapEnd = min(frameA.maxY, frameB.maxY)
        case .left:
            contact = (frameB.maxX + frameA.minX) / 2
            overlapStart = max(frameA.minY, frameB.minY)
            overlapEnd = min(frameA.maxY, frameB.maxY)
        case .top:
            contact = (frameA.maxY + frameB.minY) / 2
            overlapStart = max(frameA.minX, frameB.minX)
            overlapEnd = min(frameA.maxX, frameB.maxX)
        case .bottom:
            contact = (frameB.maxY + frameA.minY) / 2
            overlapStart = max(frameA.minX, frameB.minX)
            overlapEnd = min(frameA.maxX, frameB.maxX)
        }

        return WindowAdjacency(
            windowA: adj.windowA,
            windowB: adj.windowB,
            edgeOfA: adj.edgeOfA,
            overlapStart: overlapStart,
            overlapEnd: overlapEnd,
            contactCoordinate: contact
        )
    }

    private func handleMemberDestroyed(id: CGWindowID) {
        guard let gid = groupIndexByWindow[id] else { return }
        guard var group = windowGroups[gid] else { return }
        group.members.remove(id)
        group.adjacencies.removeAll { $0.windowA == id || $0.windowB == id }
        group.memberMeta.removeValue(forKey: id)
        group.lastKnownFrames.removeValue(forKey: id)
        groupIndexByWindow.removeValue(forKey: id)
        windowObservationService?.stopObserving(cgWindowID: id)

        if group.members.count < 2 {
            // メンバー 1 つに減ったら解体。
            for remaining in group.members {
                groupIndexByWindow.removeValue(forKey: remaining)
                windowObservationService?.stopObserving(cgWindowID: remaining)
            }
            windowGroups.removeValue(forKey: gid)
        } else {
            windowGroups[gid] = group
        }
        refreshBadgeOverlays()
    }

    /// 指定 PID のアプリで現在フォーカスされているウインドウの CGWindowID を返す。
    /// AX に直接問い合わせて availableWindowTargets のキャッシュ順に依存しない。
    func resolveFocusedWindowID(for pid: pid_t) -> CGWindowID? {
        let appElement = AXUIElementCreateApplication(pid)
        var focused: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focused)
        guard err == .success,
              let focusedCF = focused,
              CFGetTypeID(focusedCF) == AXUIElementGetTypeID() else {
            return nil
        }
        let focusedWindow = focusedCF as! AXUIElement
        // availableWindowTargets 内で AXUIElement が一致するエントリを探す。
        for target in availableWindowTargets where target.processIdentifier == pid {
            if let te = target.windowElement, CFEqual(te, focusedWindow) {
                return target.cgWindowID
            }
        }
        return nil
    }

    // MARK: - Z-order linkage

    /// グループメンバーが前面化したとき、他メンバーも直下のレイヤーに上げる。
    /// CLAUDE.md の「Window Z-Order 制御の知見」に厳密準拠:
    ///   activate → AXRaise を全メンバーに → raised のアプリを activate → CGSOrderWindow
    func handleGroupMemberRaised(id: CGWindowID) {
        if isApplyingGroupRaise {
            debugLog("WindowGrouping: raise short-circuit (isApplyingGroupRaise=true) id=\(id)")
            return
        }
        // ドラッグ/リサイズ中は Z-order 連動をトリガーしない。
        // 我々のフォロワー移動が didActivate を起こして再帰カスケードするのを防ぐため。
        if isApplyingGroupTransform {
            debugLog("WindowGrouping: raise short-circuit (isApplyingGroupTransform=true) id=\(id)")
            return
        }
        guard let gid = groupIndexByWindow[id] else {
            debugLog("WindowGrouping: raise id=\(id) not in any group")
            return
        }
        guard let group = windowGroups[gid] else {
            debugLog("WindowGrouping: raise group \(gid) not found for id=\(id)")
            return
        }
        guard group.members.count >= 2 else {
            debugLog("WindowGrouping: raise group has < 2 members")
            return
        }
        // 他メンバーが既に視覚的に見えている（他ウインドウに隠されていない）場合は
        // raise 不要 → スキップしてフォーカスのちらつきを防ぐ。
        if areAllOtherMembersVisible(group: group, sourceID: id) {
            debugLog("WindowGrouping: raise skipped — all other members already visible")
            return
        }
        debugLog("WindowGrouping: raise triggered for id=\(id), group members=\(group.members.count)")

        isApplyingGroupRaise = true
        // 長めにフラグを保持。activate() 呼び出しは非同期で didActivate を複数起こすため、
        // 短いと再帰カスケードに陥る。
        defer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.isApplyingGroupRaise = false
            }
        }

        // ハイブリッド方式：
        //   - **同一アプリ**のメンバー：既に raised のアプリがアクティブなので AXRaise が
        //     ちらつかない。異アプリ interloper による app ブロック分断を解消するため必要。
        //   - **異なるアプリ**のメンバー：フォーカスを必ず奪うので AXRaise + フォーカス書き戻し。
        //
        // 構造：
        //   1) 全ての他メンバー（同アプリ＋異アプリ）に AXRaise
        //   2) raised に AXRaise（last-raised wins で最前面へ）
        //   3) 異アプリ分のフォーカス書き戻し
        //   4) **最後にまとめて** CGSOrderWindow で他メンバーを raised の直下に配置
        //
        // CGSOrderWindow を**最後に一括適用**することで、途中の AXRaise/activate で
        // 乱れた Z-order を確定的に補正する。3+ メンバーで「最後に AXRaise された他メンバーが
        // 最前面に残る」現象を防ぐ。
        let raisedTarget = availableWindowTargets.first(where: { $0.cgWindowID == id })
        let raisedPID = raisedTarget?.processIdentifier
        let raisedWindow = raisedTarget?.windowElement

        var sameAppMembers: [CGWindowID] = []
        var diffAppMembers: [(cgID: CGWindowID, target: WindowTarget)] = []
        for member in group.members where member != id {
            guard let t = availableWindowTargets.first(where: { $0.cgWindowID == member }) else {
                debugLog("WindowGrouping:   member \(member) not in availableWindowTargets")
                continue
            }
            if t.processIdentifier == raisedPID {
                sameAppMembers.append(member)
            } else {
                diffAppMembers.append((member, t))
            }
        }
        debugLog("WindowGrouping:   sameApp=\(sameAppMembers.count) diffApp=\(diffAppMembers.count)")

        // 1. 同一アプリの他メンバーを AXRaise（前面レイヤーに引き上げ、app ブロック再構築）。
        for member in sameAppMembers {
            guard let target = availableWindowTargets.first(where: { $0.cgWindowID == member }),
                  let window = target.windowElement else { continue }
            let axResult = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            debugLog("WindowGrouping:   [sameApp] AXRaise(\(member)) → \(axResult.rawValue)")
        }
        // 2. 異なるアプリの他メンバーを activate + AXRaise。
        //    activate なしでは AXRaise が返り値成功でも実際には前面化されない
        //    （対象アプリが非アクティブだとウインドウサーバが前面レイヤーに引き上げない）。
        //    cross-app のフォーカスちらつきは回避不可能。
        for entry in diffAppMembers {
            if let app = NSRunningApplication(processIdentifier: entry.target.processIdentifier) {
                let result = app.activate(options: [])
                debugLog("WindowGrouping:   [diffApp] activate(pid=\(entry.target.processIdentifier)) → \(result)")
            }
            guard let window = entry.target.windowElement else { continue }
            let axResult = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            debugLog("WindowGrouping:   [diffApp] AXRaise(\(entry.cgID)) → \(axResult.rawValue)")
        }
        // 3. raised を AXRaise で最前面に（他メンバーの AXRaise が乱した順序を補正）。
        if let rw = raisedWindow {
            AXUIElementPerformAction(rw, kAXRaiseAction as CFString)
        }
        // 4. 異アプリメンバーがあった場合、フォーカス復帰を念押し。
        if !diffAppMembers.isEmpty, let rw = raisedWindow {
            AXUIElementSetAttributeValue(rw, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(rw, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        }
        // 5. 最後にまとめて CGSOrderWindow で他メンバーを raised の直下に配置。
        //    AXRaise の非決定的な順序影響を確定的に上書きする。
        if CGSPrivate.isOrderWindowAvailable {
            let allOthers = sameAppMembers + diffAppMembers.map { $0.cgID }
            for member in allOthers {
                let ok = CGSPrivate.orderWindow(member, mode: CGSPrivate.kCGSOrderBelow, relativeTo: id)
                debugLog("WindowGrouping:   CGSOrderWindow(\(member), below, \(id)) → \(ok)")
            }
            // 6. メンバーと同じアプリの**非メンバー**ウインドウが、グループメンバー間に
            //    挟まっているとそのメンバーが視覚的に隠されてしまう（例: App A の
            //    winA1 と winA2、App B の winB1 がある状態で、winA1-winB1 グループ化後、
            //    winA2 が winB1 を隠す問題）。
            //    対策：非メンバーウインドウで「ある member より前」にいるものを、
            //    最深 member の下に押し下げる。
            pushNonMemberSameAppWindowsBelowDeepestMember(group: group)
        }
    }

    /// `sourceID` 以外のグループメンバーが全て視覚的に「見えている」（他のウインドウに
    /// よって隠されていない）かを判定する。
    /// 真の場合は raise 連動を発動する必要がない。
    private func areAllOtherMembersVisible(group: WindowGroup, sourceID: CGWindowID) -> Bool {
        guard let infoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return false }

        // (cgWindowID, frame) のリストを Z-order で構築（layer=0 のみ）。
        var entries: [(CGWindowID, CGRect)] = []
        for info in infoList {
            guard let wid = info[kCGWindowNumber as String] as? CGWindowID else { continue }
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let boundsDict = info[kCGWindowBounds as String] as? [String: Any] else { continue }
            guard let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
            entries.append((wid, rect))
        }

        // 各非ソースメンバーについて、それより上に重なるウインドウがないか確認。
        for member in group.members where member != sourceID {
            guard let memberIdx = entries.firstIndex(where: { $0.0 == member }) else {
                // メンバーが entries にない（オフスクリーン等） → 隠れているとみなす
                return false
            }
            let memberRect = entries[memberIdx].1
            for i in 0..<memberIdx {
                let aboveRect = entries[i].1
                if aboveRect.intersects(memberRect) {
                    return false  // 上に重なっているウインドウがある → 隠れている
                }
            }
        }
        return true
    }

    /// グループメンバーと同じ PID を持つ非メンバーウインドウで、グループメンバーの
    /// 間に割り込んでいるものを、最深メンバーの下に押し下げる。
    private func pushNonMemberSameAppWindowsBelowDeepestMember(group: WindowGroup) {
        guard CGSPrivate.isOrderWindowAvailable else { return }
        guard let infoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return }

        // 各ウインドウの位置（Z-order indexed）と所有 PID を取得。
        var positions: [CGWindowID: Int] = [:]
        var owners: [CGWindowID: pid_t] = [:]
        for (idx, info) in infoList.enumerated() {
            guard let wid = info[kCGWindowNumber as String] as? CGWindowID else { continue }
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let pid = info[kCGWindowOwnerPID as String] as? Int32 else { continue }
            positions[wid] = idx
            owners[wid] = pid_t(pid)
        }

        // グループメンバーの PID 一覧と Z-order 上の位置。
        var memberPIDs: Set<pid_t> = []
        var memberPositions: [Int] = []
        for memberID in group.members {
            if let pid = owners[memberID] { memberPIDs.insert(pid) }
            if let pos = positions[memberID] { memberPositions.append(pos) }
        }
        guard let shallowestMemberPos = memberPositions.min(),
              let deepestMemberPos = memberPositions.max() else { return }

        // 最深メンバーの CGWindowID を特定（CGSOrderWindow の基準点に使う）。
        guard let deepestMemberID = group.members.first(where: { positions[$0] == deepestMemberPos }) else { return }

        debugLog("WindowGrouping:   push-down scan: shallow=\(shallowestMemberPos) deep=\(deepestMemberPos) deepestMemberID=\(deepestMemberID) memberPIDs=\(memberPIDs)")
        // 詳細：上位 20 ウインドウの (位置, ID, PID) を出力
        for (idx, info) in infoList.prefix(20).enumerated() {
            let wid = info[kCGWindowNumber as String] as? CGWindowID ?? 0
            let pid = info[kCGWindowOwnerPID as String] as? Int32 ?? 0
            let layer = info[kCGWindowLayer as String] as? Int ?? -1
            let name = info[kCGWindowOwnerName as String] as? String ?? "?"
            let isMember = group.members.contains(wid) ? " [MEMBER]" : ""
            debugLog("WindowGrouping:     z[\(idx)] wid=\(wid) pid=\(pid) layer=\(layer) name=\(name)\(isMember)")
        }

        // 非メンバーウインドウを走査し、メンバーと同じ PID かつメンバー間に挟まって
        // いるものを最深メンバーの下へ。
        for (wid, pos) in positions {
            if group.members.contains(wid) { continue }  // メンバーはスキップ
            guard let pid = owners[wid], memberPIDs.contains(pid) else { continue }  // 同じアプリのみ
            // shallowestMember より深く、deepestMember より浅い位置 → メンバー間に挟まっている
            guard pos > shallowestMemberPos && pos < deepestMemberPos else { continue }
            // まず最深メンバーの下に送る
            let ok1 = CGSPrivate.orderWindow(wid, mode: CGSPrivate.kCGSOrderBelow, relativeTo: deepestMemberID)
            debugLog("WindowGrouping:   push non-member \(wid) (pid=\(pid), pos=\(pos)) below deepest member \(deepestMemberID) → \(ok1)")
            // 念のため最背面にも送る（cross-app CGSOrderWindow の相対指定が効かない場合のフォールバック）
            let ok2 = CGSPrivate.orderWindow(wid, mode: CGSPrivate.kCGSOrderBelow, relativeTo: 0)
            debugLog("WindowGrouping:   push non-member \(wid) to very back → \(ok2)")
        }
    }
}
