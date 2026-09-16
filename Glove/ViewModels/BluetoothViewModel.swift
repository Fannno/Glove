import Combine
import CoreBluetooth
import Foundation
import SwiftUI

@MainActor
final class BluetoothViewModel: NSObject, ObservableObject {

    static let shared = BluetoothViewModel()
    let pipeline = TremorPipeline()
    let bluetoothManager = BluetoothManager()

    /// 纜繩出廠歸零原點、收緊上下限、有效長度邊界與微調極限常數
    static let initialCableHomeMm = 400.0
    static let initialTakeUpDefaultCm = 0.0
    static let initialTakeUpMinCm = 0.0
    static let initialTakeUpMaxCm = 14.0
    static let initialCableLengthDefaultMm = initialCableHomeMm
    static let initialCableLengthMinMm = initialCableHomeMm - (initialTakeUpMaxCm * 10.0)
    static let initialCableLengthMaxMm = initialCableHomeMm
    static let maxLengthAdjustmentMm: Int = 50
    static let maxLengthAdjustmentCm: Double = 5.0

    /// 藍牙連線、掃描、硬體供電、系統授權與狀態文字
    @Published var isConnected: Bool = false
    @Published var isScanning: Bool = false
    @Published var isBluetoothPoweredOn: Bool = true
    @Published var isBluetoothUnauthorized: Bool = false
    @Published var statusMessage: String = "未連線"

    /// 裝置剩餘電量百分比與馬達運轉致動狀態
    @Published var batteryLevel: Int = 0
    @Published var isMotorEnabled: Bool = false

    /// 全自動震顫抑制模式啟用狀態、指令回覆等待旗標與目標模式暫存
    @Published var isAutomaticSuppressionEnabled = false
    @Published var isAutomaticModeCommandPending = false
    private var pendingAutomaticSuppressionTarget: Bool?

    /// 手套初始化流程之傳輸等待、執行中、成功與錯誤訊息狀態
    @Published var isInitialLengthCommandPending = false
    @Published var isInitializationSequencePending = false
    @Published var initializationSequenceSucceeded = false
    @Published var initializationSequenceErrorMessage: String? = nil

    /// 即時震顫主頻率與震顫強度均方根值顯示數據
    @Published var dominantFrequencyText: String = "--"
    @Published var tremorStrengthRms: Double = 0.0

    /// 纜繩初始基準長度、初始收緊公分數與使用者介面微調偏移量
    @Published var initialCableLengthMm = 400.0
    @Published var initialTakeUpCm = 0.0
    @Published var lengthOffsetMm: Double = 0.0

    /// 掃描逾時監控任務、待確認基準寫入計數與初始化流程防衝突旗標
    private var scanTimeoutTask: Task<Void, Never>?
    private var pendingBaselineWriteCount = 0
    private var enableAutoAfterPendingBaselineWrites = false
    private var initializationBaselineWriteFailed = false
    private var initializationAutoWaitingForModeSlot = false

    /// 私有化建構子，配置分析管線回呼並自動評估藍牙狀態
    private override init() {
        super.init()

        DataViewModel.shared.bindPipeline(pipeline)
        bluetoothManager.delegate = self

        pipeline.onSendLengthAdjustment = { [weak self] offset in
            self?.bluetoothManager.sendLengthAdjustment(offset)
        }

        pipeline.onSendManualLengthInput = { [weak self] offset in
            self?.bluetoothManager.sendManualLengthInput(offset)
        }

        setupPipelineCallbacks()

        if bluetoothManager.isBluetoothEnabled && !isConnected {
            startScan()
        }
    }

    /// 設定分析管線與 UI 狀態連動之即時回呼機制
    private func setupPipelineCallbacks() {
        pipeline.onLiveAnalysisUpdated = { [weak self] result, points in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let lastPoint = points.last {
                    self.isMotorEnabled = lastPoint.motorEnabled == 1
                }

                if result.dataValid {
                    self.tremorStrengthRms = result.tremorStrengthRmsDps

                    if result.frequencyReliable, let frequency = result.dominantFrequencyHz {
                        self.dominantFrequencyText = String(format: "%.2f Hz", frequency)
                    } else {
                        self.dominantFrequencyText = "--"
                    }
                } else {
                    self.dominantFrequencyText = "--"
                    self.tremorStrengthRms = 0.0
                }
            }
        }

        pipeline.onMotorEnabledChanged = { [weak self] enabled in
            Task { @MainActor [weak self] in
                self?.isMotorEnabled = enabled
            }
        }
    }

    /// 啟動藍牙搜尋與配對手套裝置，包含權限檢查與 8 秒逾時防護機制
    func startScan() {
        if bluetoothManager.isBluetoothUnauthorized {
            isBluetoothUnauthorized = true
            isBluetoothPoweredOn = false
            statusMessage = "請先允許藍牙權限"
            openSettings()
            return
        }

        guard bluetoothManager.isBluetoothEnabled else {
            isBluetoothPoweredOn = false
            isBluetoothUnauthorized = false
            isConnected = false
            isScanning = false
            statusMessage = "手機藍牙未開啟"
            pipeline.resetPipeline()
            bluetoothManager.triggerSystemPowerAlert()
            return
        }

        guard !isConnected else {
            statusMessage = "手套已連線"
            return
        }

        AppLog.debug("啟動掃描...")
        isBluetoothPoweredOn = true
        isBluetoothUnauthorized = false
        isScanning = true
        statusMessage = "搜尋手套中..."

        bluetoothManager.startScanning()

        scanTimeoutTask?.cancel()
        scanTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8 * 1_000_000_000)

            guard let self, !Task.isCancelled else { return }

            if !self.isConnected {
                AppLog.error("掃描逾時未連線。")
                self.isScanning = false
                self.statusMessage = "搜尋失敗，請確認手套已開機"
                self.bluetoothManager.stopScanning()
            }
        }
    }

    /// 主動中斷手套藍牙連線，重設管線緩衝區、結算上傳資料並重設會話
    func disconnect() {
        scanTimeoutTask?.cancel()
        isScanning = false
        isMotorEnabled = false
        isAutomaticSuppressionEnabled = false
        isAutomaticModeCommandPending = false
        pendingAutomaticSuppressionTarget = nil
        pendingBaselineWriteCount = 0
        isInitialLengthCommandPending = false
        enableAutoAfterPendingBaselineWrites = false
        initializationBaselineWriteFailed = false
        initializationAutoWaitingForModeSlot = false
        isInitializationSequencePending = false
        initializationSequenceSucceeded = false
        initializationSequenceErrorMessage = nil
        isConnected = false
        statusMessage = "未連線"

        pipeline.resetPipeline()
        DataViewModel.shared.resetRawUploadBuffer(flushRemaining: true)
        DataViewModel.shared.currentSessionId = UUID().uuidString

        bluetoothManager.disconnect()
    }

    /// 開啟系統設定頁面引導使用者開啟藍牙權限
    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }

    /// 提交滑桿所選取之長度微調相對命令至硬體端，送出後自動將滑桿數值歸零
    func commitSliderLengthAdjustment() {
        guard isConnected else {
            AppLog.error("略過 Slider 指令：手套尚未連線完成。")
            lengthOffsetMm = 0.0
            return
        }

        let clampedCm = min(
            max(lengthOffsetMm, -Self.maxLengthAdjustmentCm),
            Self.maxLengthAdjustmentCm
        )
        let offsetMm = Int(round(clampedCm * 10.0))

        if offsetMm != 0 {
            bluetoothManager.sendLengthAdjustment(offsetMm)
        }

        lengthOffsetMm = 0.0
    }

    /// 發送手動輸入之長度微調命令至硬體端
    /// - Parameter offsetCm: 欲微調之長度（單位：公分 cm）
    func sendManualLengthInputCm(_ offsetCm: Double) {
        guard isConnected else {
            AppLog.error("略過手動指令：手套尚未連線完成。")
            return
        }

        let clampedCm = min(
            max(offsetCm, -Self.maxLengthAdjustmentCm),
            Self.maxLengthAdjustmentCm
        )
        let offsetMm = Int(round(clampedCm * 10.0))

        if offsetMm != 0 {
            bluetoothManager.sendManualLengthInput(offsetMm)
        }
    }

    /// 送出初始基準長度設定至硬體端
    /// - Parameter takeUpCm: 預收緊長度（單位：公分 cm）
    /// - Returns: 是否成功排入藍牙寫入佇列
    @discardableResult
    func sendInitialTakeUpCm(_ takeUpCm: Double) -> Bool {
        guard isConnected else {
            AppLog.error("略過初始收緊指令：手套尚未連線完成。")
            return false
        }

        let clampedCm = min(
            max(takeUpCm, Self.initialTakeUpMinCm),
            Self.initialTakeUpMaxCm
        )
        let roundedTakeUpMm = Int(round(clampedCm * 10.0))
        let baselineMm = Int(Self.initialCableHomeMm) - roundedTakeUpMm

        initialTakeUpCm = Double(roundedTakeUpMm) / 10.0
        initialCableLengthMm = Double(baselineMm)

        let queued = bluetoothManager.sendBaselineLength(magnitudeMm: baselineMm)
        if queued {
            pendingBaselineWriteCount += 1
            isInitialLengthCommandPending = true
            AppLog.debug("0x06 已排入 BLE，待確認 baseline=\(baselineMm) mm，pending=\(pendingBaselineWriteCount)")
        } else {
            AppLog.error("初始長度指令未成功排入 BLE 傳送。")
        }

        return queued
    }

    /// 確認初始長度並在基準確認完成後自動啟用抑震模式
    /// - Parameter takeUpCm: 最終選定之收緊長度（單位：公分 cm）
    /// - Returns: 初始化流程是否順利啟動
    @discardableResult
    func confirmInitialTakeUpAndEnableAuto(_ takeUpCm: Double) -> Bool {
        guard isConnected else {
            initializationSequenceErrorMessage = "手套尚未連線，無法完成初始化。"
            initializationSequenceSucceeded = false
            return false
        }

        guard !isInitializationSequencePending else {
            AppLog.debug("初始化流程已在執行，略過重複確認。")
            return false
        }

        initializationSequenceSucceeded = false
        initializationSequenceErrorMessage = nil
        initializationBaselineWriteFailed = false
        enableAutoAfterPendingBaselineWrites = true
        initializationAutoWaitingForModeSlot = false
        isInitializationSequencePending = true

        guard sendInitialTakeUpCm(takeUpCm) else {
            failInitializationSequence("初始長度 0x06 無法送出，請確認藍牙連線後再試一次。")
            return false
        }

        return true
    }

    /// 取消當前未完成的初始化與自動抑震串接流程
    func cancelInitialCalibrationSequence() {
        enableAutoAfterPendingBaselineWrites = false
        initializationBaselineWriteFailed = false
        initializationAutoWaitingForModeSlot = false
        isInitializationSequencePending = false
        initializationSequenceSucceeded = false
        initializationSequenceErrorMessage = nil
    }

    /// 重設初始化流程回饋提示狀態
    func resetInitializationSequenceFeedback() {
        guard !isInitializationSequencePending else { return }
        initializationSequenceSucceeded = false
        initializationSequenceErrorMessage = nil
    }

    /// 清除初始化流程錯誤訊息
    func clearInitializationSequenceError() {
        initializationSequenceErrorMessage = nil
    }

    /// 於所有基準長度指令確認寫入後排入自動抑震模式命令
    private func startInitializationAutoIfPossible() {
        guard isInitializationSequencePending else { return }
        guard enableAutoAfterPendingBaselineWrites else { return }
        guard pendingBaselineWriteCount == 0 else { return }

        if initializationBaselineWriteFailed {
            failInitializationSequence("初始長度指令寫入失敗，因此未啟用 AUTO。請重新調整後再試一次。")
            return
        }

        if isAutomaticModeCommandPending {
            initializationAutoWaitingForModeSlot = true
            AppLog.debug("0x06 已全部確認，等待目前 0x07 回覆完成後再送 AUTO。")
            return
        }

        initializationAutoWaitingForModeSlot = false
        pendingAutomaticSuppressionTarget = true
        isAutomaticModeCommandPending = true

        let queued = bluetoothManager.sendAutomaticMode(true)
        if queued {
            AppLog.debug("初始化 baseline 已全部確認，現在送出 AUTO：07 00 01")
        } else {
            isAutomaticModeCommandPending = false
            pendingAutomaticSuppressionTarget = nil
            failInitializationSequence("AUTO 指令無法送出，請確認藍牙連線後再試一次。")
        }
    }

    /// 標記初始化流程失敗並記錄錯誤訊息
    /// - Parameter message: 錯誤提示字串
    private func failInitializationSequence(_ message: String) {
        enableAutoAfterPendingBaselineWrites = false
        initializationAutoWaitingForModeSlot = false
        isInitializationSequencePending = false
        initializationSequenceSucceeded = false
        initializationSequenceErrorMessage = message
        AppLog.error(message)
    }

    /// 依據目標纜繩絕對長度發送初始基準校正設定
    /// - Parameter lengthMm: 目標纜繩長度（單位：毫米 mm）
    func sendInitialCableLengthMm(_ lengthMm: Double) {
        let clamped = min(
            max(lengthMm, Self.initialCableLengthMinMm),
            Self.initialCableLengthMaxMm
        )
        let takeUpCm = (Self.initialCableHomeMm - clamped) / 10.0
        sendInitialTakeUpCm(takeUpCm)
    }

    /// 切換手套是否開啟全自動即時震顫抑制模式
    /// - Parameter enabled: true 為開啟自動抑震，false 為手動模式
    func setAutomaticSuppression(_ enabled: Bool) {
        guard isConnected else {
            AppLog.error("略過模式切換：手套尚未連線完成。")
            isAutomaticSuppressionEnabled = false
            isAutomaticModeCommandPending = false
            pendingAutomaticSuppressionTarget = nil
            return
        }

        guard !isAutomaticModeCommandPending else {
            AppLog.debug("AUTO / MANUAL 模式切換仍在等待 BLE 回覆，略過重複操作。")
            return
        }

        pendingAutomaticSuppressionTarget = enabled
        isAutomaticModeCommandPending = true

        let queued = bluetoothManager.sendAutomaticMode(enabled)
        if !queued {
            AppLog.error("AUTO / MANUAL 指令未成功排入 BLE 傳送。")
            isAutomaticModeCommandPending = false
            pendingAutomaticSuppressionTarget = nil
        }
    }
}

extension BluetoothViewModel: BluetoothManagerDelegate {

    /// 接收手套硬體端回傳之電池狀態推播更新
    /// - Parameters:
    ///   - manager: 發送回呼之藍牙管理器實體
    ///   - battery: 包含電量百分比之 BatteryStatus 物件
    public func bluetoothManager(
        _ manager: BluetoothManager,
        didUpdateBattery battery: BatteryStatus
    ) {
        Task { @MainActor in
            self.batteryLevel = Int(battery.percent)
        }
    }

    /// 接收手套硬體端連續串流傳入之原始三軸震顫資料點
    /// - Parameters:
    ///   - manager: 發送回呼之藍牙管理器實體
    ///   - points: 最新解析出之 TremorDataPoint 感測訊號陣列
    public func bluetoothManager(
        _ manager: BluetoothManager,
        didReceivePoints points: [TremorDataPoint]
    ) {
        if !isConnected {
            scanTimeoutTask?.cancel()
            isConnected = true
            isScanning = false
            statusMessage = "手套已連線"
        }

        pipeline.bluetoothManager(manager, didReceivePoints: points)
    }

    /// 監聽系統底層 CoreBluetooth 狀態改變並同步處理 UI 提示與連線狀態
    /// - Parameters:
    ///   - manager: 發送回呼之藍牙管理器實體
    ///   - state: 系統最新之 CBManagerState 狀態
    public func bluetoothManager(
        _ manager: BluetoothManager,
        didUpdateState state: CBManagerState
    ) {
        Task { @MainActor in
            switch state {
            case .poweredOn:
                isBluetoothPoweredOn = true
                isBluetoothUnauthorized = false
                if !isConnected && !isScanning {
                    startScan()
                }

            case .unauthorized:
                isBluetoothPoweredOn = false
                isBluetoothUnauthorized = true
                isConnected = false
                isScanning = false
                isAutomaticSuppressionEnabled = false
                isAutomaticModeCommandPending = false
                pendingAutomaticSuppressionTarget = nil
                pendingBaselineWriteCount = 0
                isInitialLengthCommandPending = false
                enableAutoAfterPendingBaselineWrites = false
                initializationBaselineWriteFailed = false
                initializationAutoWaitingForModeSlot = false
                isInitializationSequencePending = false
                initializationSequenceSucceeded = false
                initializationSequenceErrorMessage = nil
                statusMessage = "未取得藍牙權限"
                scanTimeoutTask?.cancel()
                pipeline.resetPipeline()
                DataViewModel.shared.resetRawUploadBuffer(flushRemaining: true)
                DataViewModel.shared.currentSessionId = UUID().uuidString

            case .poweredOff:
                isBluetoothPoweredOn = false
                isBluetoothUnauthorized = false
                isConnected = false
                isScanning = false
                isAutomaticSuppressionEnabled = false
                isAutomaticModeCommandPending = false
                pendingAutomaticSuppressionTarget = nil
                pendingBaselineWriteCount = 0
                isInitialLengthCommandPending = false
                enableAutoAfterPendingBaselineWrites = false
                initializationBaselineWriteFailed = false
                initializationAutoWaitingForModeSlot = false
                isInitializationSequencePending = false
                initializationSequenceSucceeded = false
                initializationSequenceErrorMessage = nil
                statusMessage = "手機藍牙未開啟"
                scanTimeoutTask?.cancel()
                pipeline.resetPipeline()
                DataViewModel.shared.resetRawUploadBuffer(flushRemaining: true)
                DataViewModel.shared.currentSessionId = UUID().uuidString

            default:
                isBluetoothPoweredOn = false
                isConnected = false
                isScanning = false
                isAutomaticSuppressionEnabled = false
                isAutomaticModeCommandPending = false
                pendingAutomaticSuppressionTarget = nil
                pendingBaselineWriteCount = 0
                isInitialLengthCommandPending = false
                enableAutoAfterPendingBaselineWrites = false
                initializationBaselineWriteFailed = false
                initializationAutoWaitingForModeSlot = false
                isInitializationSequencePending = false
                initializationSequenceSucceeded = false
                initializationSequenceErrorMessage = nil
                statusMessage = "藍牙準備中..."
                pipeline.resetPipeline()
                DataViewModel.shared.resetRawUploadBuffer(flushRemaining: true)
                DataViewModel.shared.currentSessionId = UUID().uuidString
            }
        }
    }

    /// 接收硬體控制指令寫入結果回呼，處理模式確認與初始化長度串接狀態
    /// - Parameters:
    ///   - manager: 發送回呼之藍牙管理器實體
    ///   - commandId: 執行寫入之指令識別碼
    ///   - value: 該指令寫入之數值
    ///   - success: 藍牙特徵值寫入是否成功
    public func bluetoothManager(
        _ manager: BluetoothManager,
        didWriteControlCommand commandId: UInt8,
        value: UInt16,
        success: Bool
    ) {
        Task { @MainActor in
            switch commandId {
            case 0x07:
                let requestedAuto = (value == 1)
                isAutomaticModeCommandPending = false
                pendingAutomaticSuppressionTarget = nil

                if success {
                    isAutomaticSuppressionEnabled = requestedAuto
                    AppLog.debug(
                        requestedAuto
                            ? "AUTO 指令已由 BLE 確認送達 ESP32：07 00 01"
                            : "MANUAL 指令已由 BLE 確認送達 ESP32：07 00 00"
                    )
                } else {
                    AppLog.error("AUTO / MANUAL BLE 寫入失敗，App 保留原模式顯示。")
                }

                if isInitializationSequencePending && requestedAuto {
                    if success {
                        enableAutoAfterPendingBaselineWrites = false
                        initializationAutoWaitingForModeSlot = false
                        isInitializationSequencePending = false
                        initializationSequenceSucceeded = true
                        initializationSequenceErrorMessage = nil
                        AppLog.debug("初始化流程完成：0x06 已確認，07 00 01 也已確認。")
                    } else {
                        failInitializationSequence("AUTO BLE 寫入失敗，初始化已停在 MANUAL。")
                    }
                    return
                }

                if isInitializationSequencePending && initializationAutoWaitingForModeSlot {
                    startInitializationAutoIfPossible()
                }

            case 0x06:
                if pendingBaselineWriteCount > 0 {
                    pendingBaselineWriteCount -= 1
                }
                isInitialLengthCommandPending = pendingBaselineWriteCount > 0

                if success {
                    isAutomaticSuppressionEnabled = false
                    AppLog.debug(
                        "初始長度 0x06 已寫入 ESP32，baseline=\(value) mm；剩餘 pending=\(pendingBaselineWriteCount)"
                    )
                } else {
                    initializationBaselineWriteFailed = true
                    AppLog.error(
                        "初始長度 0x06 BLE 寫入失敗，baseline=\(value) mm；剩餘 pending=\(pendingBaselineWriteCount)"
                    )
                }

                if isInitializationSequencePending &&
                    enableAutoAfterPendingBaselineWrites &&
                    pendingBaselineWriteCount == 0 {
                    startInitializationAutoIfPossible()
                }

            default:
                break
            }
        }
    }

    /// 監聽手套藍牙連線或中斷連線事件回呼
    /// - Parameters:
    ///   - manager: 發送回呼之藍牙管理器實體
    ///   - connected: 裝置當前是否處於連線狀態
    public func bluetoothManager(
        _ manager: BluetoothManager,
        didUpdateConnection connected: Bool
    ) {
        Task { @MainActor in
            scanTimeoutTask?.cancel()
            isConnected = connected
            isScanning = false
            statusMessage = connected ? "手套已連線" : "已斷開連線"

            if !connected {
                dominantFrequencyText = "--"
                tremorStrengthRms = 0.0
                isMotorEnabled = false
                isAutomaticSuppressionEnabled = false
                isAutomaticModeCommandPending = false
                pendingAutomaticSuppressionTarget = nil
                pendingBaselineWriteCount = 0
                isInitialLengthCommandPending = false
                enableAutoAfterPendingBaselineWrites = false
                initializationBaselineWriteFailed = false
                initializationAutoWaitingForModeSlot = false
                isInitializationSequencePending = false
                initializationSequenceSucceeded = false
                initializationSequenceErrorMessage = nil

                pipeline.resetPipeline()
                DataViewModel.shared.resetRawUploadBuffer(flushRemaining: true)
                DataViewModel.shared.currentSessionId = UUID().uuidString
            } else {
                DataViewModel.shared.currentSessionId = UUID().uuidString
                pendingBaselineWriteCount = 0
                isInitialLengthCommandPending = false
                enableAutoAfterPendingBaselineWrites = false
                initializationBaselineWriteFailed = false
                initializationAutoWaitingForModeSlot = false
                isInitializationSequencePending = false
                initializationSequenceSucceeded = false
                initializationSequenceErrorMessage = nil
                isAutomaticSuppressionEnabled = false
                pendingAutomaticSuppressionTarget = false
                isAutomaticModeCommandPending = bluetoothManager.sendAutomaticMode(false)
                if !isAutomaticModeCommandPending {
                    pendingAutomaticSuppressionTarget = nil
                    AppLog.error("連線完成後的 MANUAL 初始化指令未成功排入 BLE 傳送。")
                }
            }

            lengthOffsetMm = 0.0
        }
    }
}
