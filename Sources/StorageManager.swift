import Foundation

public final class StorageManager {
    public static let shared = StorageManager()
    
    private let recordingsFolder: URL
    private let metadataKey = "DynamicECG_SavedRecordings_Metadata"
    
    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        recordingsFolder = docs.appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: recordingsFolder, withIntermediateDirectories: true)
    }
    
    public func saveCSV(content: String, originalFileName: String, report: ECGAnalysisReport) -> SavedRecordingItem {
        let cleanName = originalFileName.replacingOccurrences(of: ".csv", with: "")
        let safeFileName = "\(cleanName)_\(Int(Date().timeIntervalSince1970)).csv"
        let destURL = recordingsFolder.appendingPathComponent(safeFileName)
        
        try? content.write(to: destURL, atomically: true, encoding: .utf8)
        
        let item = SavedRecordingItem(
            fileName: safeFileName,
            displayName: cleanName,
            dateStr: report.metadata.recordedDate.isEmpty ? "N/D" : report.metadata.recordedDate,
            classification: report.metadata.classification,
            bpm: report.bpm,
            qtcFridericia: report.qtSummary?.qtcFridericia ?? 0.0,
            durationSec: report.durationSec,
            isMultiLead: report.multiLead.hasMultipleLeads,
            isSample: false
        )
        
        var list = listSavedRecordings()
        list.insert(item, at: 0)
        saveMetadata(list)
        return item
    }
    
    public func listSavedRecordings() -> [SavedRecordingItem] {
        guard let data = UserDefaults.standard.data(forKey: metadataKey),
              let list = try? JSONDecoder().decode([SavedRecordingItem].self, from: data) else {
            return []
        }
        return list
    }
    
    public func readCSVContent(fileName: String) -> String? {
        let fileURL = recordingsFolder.appendingPathComponent(fileName)
        return try? String(contentsOf: fileURL, encoding: .utf8)
    }
    
    public func deleteRecording(item: SavedRecordingItem) {
        let fileURL = recordingsFolder.appendingPathComponent(item.fileName)
        try? FileManager.default.removeItem(at: fileURL)
        var list = listSavedRecordings()
        list.removeAll { $0.id == item.id }
        saveMetadata(list)
    }
    
    private func saveMetadata(_ list: [SavedRecordingItem]) {
        if let encoded = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(encoded, forKey: metadataKey)
        }
    }
}
