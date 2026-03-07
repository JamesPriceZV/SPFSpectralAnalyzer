import Foundation
import CloudKit
import AppKit

final class CloudKitSyncMonitor {
    static let shared = CloudKitSyncMonitor()

    private let container: CKContainer
    private let database: CKDatabase
    private let subscriptionID = "spf.spectral.cloudkit.database"
    private let tokenKey = "icloudDatabaseChangeToken"
    private var pollingTimer: Timer?
    private var isSyncing = false

    #if DEBUG
    private let lastNotificationKey = "icloudLastNotificationPayload"
    private let lastTokenDescriptionKey = "icloudLastTokenDescription"
    private let lastPollTimestampKey = "icloudLastPollTimestamp"
    private let lastPushTimestampKey = "icloudLastPushTimestamp"
    private let lastSyncReasonKey = "icloudLastSyncReason"
    private let lastChangedZonesKey = "icloudLastChangedZoneIDs"
    private let lastDeletedZonesKey = "icloudLastDeletedZoneIDs"
    private let lastSubscriptionIDKey = "icloudLastSubscriptionID"
    private let lastSubscriptionStatusKey = "icloudLastSubscriptionStatus"
    private let lastContainerIdentifierKey = "icloudContainerIdentifier"
    private let lastAccountStatusKey = "icloudAccountStatus"
    private let lastAccountStatusErrorKey = "icloudAccountStatusError"
    private let lastAccountStatusTimestampKey = "icloudAccountStatusTimestamp"
    private let lastDatabaseScopeKey = "icloudDatabaseScope"
    private let lastSyncStartTimestampKey = "icloudLastSyncStartTimestamp"
    private let lastSyncEndTimestampKey = "icloudLastSyncEndTimestamp"
    private let lastSyncDurationKey = "icloudLastSyncDuration"
    private let lastSyncErrorDomainKey = "icloudLastSyncErrorDomain"
    private let lastSyncErrorCodeKey = "icloudLastSyncErrorCode"
    private let lastSyncErrorDescriptionKey = "icloudLastSyncErrorDescription"
    private let lastSyncMoreComingKey = "icloudLastSyncMoreComing"
    private let lastSyncChangesDetectedKey = "icloudLastSyncChangesDetected"
    private let lastChangedZoneCountKey = "icloudLastChangedZoneCount"
    private let lastDeletedZoneCountKey = "icloudLastDeletedZoneCount"
    private let lastPushSubscriptionIDKey = "icloudLastPushSubscriptionID"
    private let lastNotificationTypeKey = "icloudLastNotificationType"
    private let lastTokenByteSizeKey = "icloudLastTokenByteSize"
    private let lastMoreComingTimestampsKey = "icloudLastMoreComingTimestamps"
    private let lastPartialZoneErrorsKey = "icloudLastPartialZoneErrors"
    private let lastZoneFetchErrorsKey = "icloudLastZoneFetchErrors"
    private let lastZoneFetchTimestampKey = "icloudLastZoneFetchTimestamp"
    private let lastZoneFetchMoreComingKey = "icloudLastZoneFetchMoreComing"
    private let zoneChangeTokensKey = "icloudZoneChangeTokens"
    #endif

    private init() {
        container = CKContainer.default()
        database = container.privateCloudDatabase
    }

    private func updateDefaults(_ block: @escaping (UserDefaults) -> Void) {
        if Thread.isMainThread {
            block(UserDefaults.standard)
        } else {
            Task { @MainActor in
                block(UserDefaults.standard)
            }
        }
    }

    func configure() {
        guard isSyncEnabled else { return }
        #if DEBUG
        updateDefaults { defaults in
            defaults.set(self.subscriptionID, forKey: self.lastSubscriptionIDKey)
            defaults.set(self.container.containerIdentifier ?? "default", forKey: self.lastContainerIdentifierKey)
            defaults.set(self.database.databaseScope == .private ? "private" : "public", forKey: self.lastDatabaseScopeKey)
        }
        #endif
        refreshAccountStatus()
        ensureSubscription()
        startPollingIfNeeded()
    }

    func startPollingIfNeeded() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        guard isSyncEnabled else { return }
        let interval = pollingIntervalMinutes * 60.0
        pollingTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.performSyncCheck(reason: "poll")
            }
        }
    }

    func handleRemoteNotification(_ userInfo: [String: Any]) {
        guard isSyncEnabled else { return }
        #if DEBUG
        saveLastNotificationPayload(userInfo)
        updateDefaults { defaults in
            defaults.set(Date().timeIntervalSince1970, forKey: self.lastPushTimestampKey)
        }
        #endif
        if let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) {
            #if DEBUG
            if let subscriptionID = notification.subscriptionID {
                updateDefaults { defaults in
                    defaults.set(subscriptionID, forKey: self.lastPushSubscriptionIDKey)
                }
            }
            updateDefaults { defaults in
                defaults.set(String(describing: notification.notificationType), forKey: self.lastNotificationTypeKey)
            }
            #endif
            if notification.subscriptionID == subscriptionID || notification.notificationType == .database {
                performSyncCheck(reason: "push")
            }
        }
    }

    private func ensureSubscription() {
        let subscription = CKDatabaseSubscription(subscriptionID: subscriptionID)
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info

        let op = CKModifySubscriptionsOperation(subscriptionsToSave: [subscription], subscriptionIDsToDelete: [])
        op.modifySubscriptionsResultBlock = { [weak self] result in
            #if DEBUG
            let status: String
            switch result {
            case .success:
                status = "Subscription active"
            case .failure(let error):
                status = "Subscription error: \(error.localizedDescription)"
            }
            self?.updateDefaults { defaults in
                if let key = self?.lastSubscriptionStatusKey {
                    defaults.set(status, forKey: key)
                }
            }
            #endif
        }
        database.add(op)
    }

    private func performSyncCheck(reason: String) {
        guard !isSyncing else { return }
        isSyncing = true
        updateSyncStatus(message: "Sync in progress")
        #if DEBUG
        updateDefaults { defaults in
            defaults.set(reason, forKey: self.lastSyncReasonKey)
            if reason == "poll" {
                defaults.set(Date().timeIntervalSince1970, forKey: self.lastPollTimestampKey)
            }
            defaults.set(Date().timeIntervalSince1970, forKey: self.lastSyncStartTimestampKey)
        }
        #endif

        let token = loadChangeToken()
        let op = CKFetchDatabaseChangesOperation(previousServerChangeToken: token)
        var changesDetected = false
        var changedZoneIDs: [String] = []
        var deletedZoneIDs: [String] = []

        op.recordZoneWithIDChangedBlock = { zoneID in
            changesDetected = true
            #if DEBUG
            changedZoneIDs.append(zoneID.zoneName)
            #endif
        }
        op.recordZoneWithIDWasDeletedBlock = { zoneID in
            #if DEBUG
            deletedZoneIDs.append(zoneID.zoneName)
            #endif
        }
        op.changeTokenUpdatedBlock = { [weak self] newToken in
            self?.saveChangeToken(newToken)
        }
        op.fetchDatabaseChangesResultBlock = { [weak self] result in
            defer { self?.isSyncing = false }
            switch result {
            case .failure(let error):
                self?.updateSyncStatus(message: "Sync error: \(error.localizedDescription)")
                #if DEBUG
                self?.updateDefaults { defaults in
                    defaults.set(error._domain, forKey: self?.lastSyncErrorDomainKey ?? "")
                    defaults.set(error._code, forKey: self?.lastSyncErrorCodeKey ?? "")
                    defaults.set(error.localizedDescription, forKey: self?.lastSyncErrorDescriptionKey ?? "")
                    defaults.set(false, forKey: self?.lastSyncMoreComingKey ?? "")
                }
                self?.capturePartialErrorsIfNeeded(error)
                #endif
            case .success(let data):
                self?.saveChangeToken(data.serverChangeToken)
                let status = changesDetected ? "CloudKit change detected" : "No CloudKit changes"
                self?.updateSyncStatus(message: status)
                #if DEBUG
                self?.updateDefaults { defaults in
                    defaults.set(data.moreComing, forKey: self?.lastSyncMoreComingKey ?? "")
                }
                self?.recordMoreComingIfNeeded(data.moreComing)
                self?.updateDefaults { defaults in
                    defaults.set("", forKey: self?.lastSyncErrorDomainKey ?? "")
                    defaults.set(0, forKey: self?.lastSyncErrorCodeKey ?? "")
                    defaults.set("", forKey: self?.lastSyncErrorDescriptionKey ?? "")
                }
                #endif
                self?.fetchZoneChangesIfNeeded(zoneNames: changedZoneIDs)
            }
            #if DEBUG
            self?.updateDefaults { defaults in
                defaults.set(Date().timeIntervalSince1970, forKey: self?.lastSyncEndTimestampKey ?? "")
                if let start = defaults.object(forKey: self?.lastSyncStartTimestampKey ?? "") as? Double {
                    defaults.set(Date().timeIntervalSince1970 - start, forKey: self?.lastSyncDurationKey ?? "")
                }
                defaults.set(changesDetected, forKey: self?.lastSyncChangesDetectedKey ?? "")
                defaults.set(changedZoneIDs.count, forKey: self?.lastChangedZoneCountKey ?? "")
                defaults.set(deletedZoneIDs.count, forKey: self?.lastDeletedZoneCountKey ?? "")
                if let key = self?.lastChangedZonesKey {
                    defaults.set(changedZoneIDs.joined(separator: "\n"), forKey: key)
                }
                if let key = self?.lastDeletedZonesKey {
                    defaults.set(deletedZoneIDs.joined(separator: "\n"), forKey: key)
                }
            }
            #endif
        }

        database.add(op)
    }

    private var isSyncEnabled: Bool {
        UserDefaults.standard.bool(forKey: ICloudDefaultsKeys.syncEnabled)
    }

    private var pollingIntervalMinutes: Double {
        let value = UserDefaults.standard.double(forKey: "icloudPollingIntervalMinutes")
        return value == 0 ? 15.0 : value
    }

    private func loadChangeToken() -> CKServerChangeToken? {
        guard let data = UserDefaults.standard.data(forKey: tokenKey) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    private func saveChangeToken(_ token: CKServerChangeToken) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
            updateDefaults { defaults in
                defaults.set(data, forKey: self.tokenKey)
            }
            #if DEBUG
            updateDefaults { defaults in
                defaults.set(data.count, forKey: self.lastTokenByteSizeKey)
            }
            #endif
        }
        #if DEBUG
        updateDefaults { defaults in
            defaults.set(String(describing: token), forKey: self.lastTokenDescriptionKey)
        }
        #endif
    }

    #if DEBUG
    private func saveLastNotificationPayload(_ payload: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]),
           let text = String(data: data, encoding: .utf8) {
            updateDefaults { defaults in
                defaults.set(text, forKey: self.lastNotificationKey)
            }
        }
    }

    private func recordMoreComingIfNeeded(_ moreComing: Bool) {
        guard moreComing else { return }
        let now = Date().timeIntervalSince1970
        var timestamps: [Double] = []
        if let data = UserDefaults.standard.data(forKey: lastMoreComingTimestampsKey),
           let decoded = try? JSONDecoder().decode([Double].self, from: data) {
            timestamps = decoded
        }
        timestamps.append(now)
        if timestamps.count > 20 {
            timestamps = Array(timestamps.suffix(20))
        }
        if let data = try? JSONEncoder().encode(timestamps) {
            updateDefaults { defaults in
                defaults.set(data, forKey: self.lastMoreComingTimestampsKey)
            }
        }
    }

    private func capturePartialErrorsIfNeeded(_ error: Error) {
        guard let ckError = error as? CKError else { return }
        let partials = ckError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error]
        guard let partials, !partials.isEmpty else { return }
        let lines = partials.map { key, err in
            "\(key): \(err.localizedDescription)"
        }.sorted()
        updateDefaults { defaults in
            defaults.set(lines.joined(separator: "\n"), forKey: self.lastPartialZoneErrorsKey)
        }
    }
    #endif

    private func updateSyncStatus(message: String) {
        let now = Date().timeIntervalSince1970
        let isInProgress = message.lowercased().contains("in progress")
        updateDefaults { defaults in
            defaults.set(isInProgress, forKey: ICloudDefaultsKeys.syncInProgress)
            defaults.set(now, forKey: ICloudDefaultsKeys.lastSyncTimestamp)
            defaults.set(message, forKey: ICloudDefaultsKeys.lastSyncStatus)
        }
    }

    private func refreshAccountStatus() {
        #if DEBUG
        container.accountStatus { [weak self] status, error in
            var statusText = "unknown"
            switch status {
            case .available: statusText = "available"
            case .noAccount: statusText = "noAccount"
            case .restricted: statusText = "restricted"
            case .couldNotDetermine: statusText = "couldNotDetermine"
            case .temporarilyUnavailable: statusText = "temporarilyUnavailable"
            @unknown default: statusText = "unknown"
            }
            Task { @MainActor in
                guard let self else { return }
                self.updateDefaults { defaults in
                    defaults.set(statusText, forKey: self.lastAccountStatusKey)
                    defaults.set(Date().timeIntervalSince1970, forKey: self.lastAccountStatusTimestampKey)
                    if let error {
                        defaults.set(error.localizedDescription, forKey: self.lastAccountStatusErrorKey)
                    } else {
                        defaults.set("", forKey: self.lastAccountStatusErrorKey)
                    }
                }
            }
        }
        #endif
    }

    private func fetchZoneChangesIfNeeded(zoneNames: [String]) {
        guard !zoneNames.isEmpty else { return }
        var zoneIDs: [CKRecordZone.ID] = []
        var configs: [CKRecordZone.ID: CKFetchRecordZoneChangesOperation.ZoneConfiguration] = [:]
        for name in zoneNames {
            let zoneID = CKRecordZone.ID(zoneName: name)
            if configs[zoneID] != nil { continue }
            let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
            #if DEBUG
            config.previousServerChangeToken = loadZoneChangeToken(for: zoneID)
            #endif
            configs[zoneID] = config
            zoneIDs.append(zoneID)
        }
        guard !zoneIDs.isEmpty else { return }
        let op = CKFetchRecordZoneChangesOperation(recordZoneIDs: zoneIDs, configurationsByRecordZoneID: configs)

        var zoneErrors: [String] = []
        var anyMoreComing = false

        op.recordZoneChangeTokensUpdatedBlock = { [weak self] zoneID, token, _ in
            #if DEBUG
            guard let token else { return }
            self?.saveZoneChangeToken(token, for: zoneID)
            #endif
        }

        if #available(macOS 13.0, *) {
            op.recordZoneFetchResultBlock = { zoneID, result in
                switch result {
                case .failure(let error):
                    zoneErrors.append("\(zoneID.zoneName): \(error.localizedDescription)")
                case .success(let info):
                    if info.moreComing {
                        anyMoreComing = true
                    }
                }
            }
        }

        op.fetchRecordZoneChangesResultBlock = { [weak self] _ in
            #if DEBUG
            self?.updateDefaults { defaults in
                defaults.set(Date().timeIntervalSince1970, forKey: self?.lastZoneFetchTimestampKey ?? "")
                defaults.set(anyMoreComing, forKey: self?.lastZoneFetchMoreComingKey ?? "")
                if let key = self?.lastZoneFetchErrorsKey {
                    defaults.set(zoneErrors.sorted().joined(separator: "\n"), forKey: key)
                }
            }
            #endif
        }

        database.add(op)
    }
#if DEBUG
    private func loadZoneChangeToken(for zoneID: CKRecordZone.ID) -> CKServerChangeToken? {
        guard let data = UserDefaults.standard.data(forKey: zoneChangeTokensKey),
              let decoded = try? JSONDecoder().decode([String: Data].self, from: data),
              let tokenData = decoded[zoneID.zoneName] else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: tokenData)
    }

    private func saveZoneChangeToken(_ token: CKServerChangeToken, for zoneID: CKRecordZone.ID) {
        guard let tokenData = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else { return }
        var map: [String: Data] = [:]
        if let data = UserDefaults.standard.data(forKey: zoneChangeTokensKey),
           let decoded = try? JSONDecoder().decode([String: Data].self, from: data) {
            map = decoded
        }
        map[zoneID.zoneName] = tokenData
        if let data = try? JSONEncoder().encode(map) {
            updateDefaults { defaults in
                defaults.set(data, forKey: self.zoneChangeTokensKey)
            }
        }
    }
#endif
}
