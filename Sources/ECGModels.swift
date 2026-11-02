import Foundation

public enum Gender: String, CaseIterable, Identifiable {
    case male = "Uomo"
    case female = "Donna"
    public var id: String { rawValue }
}

public enum QTcStatus: String {
    case normal = "Normale"
    case borderline = "Borderline"
    case prolonged = "Prolungato (Attenzione)"
    case shortened = "Accorciato (< 350 ms)"
}

public struct ECGMetadata {
    public var recordedDate: String = "N/D"
    public var classification: String = "N/D"
    public var sampleRate: Double = 512.0
    public var device: String = "Apple Watch"
    public var lead: String = "Lead I"
    public var symptoms: String = "Nessuno"
}

public struct QTBeatResult: Identifiable {
    public var id: Int { beatNumber }
    public let beatNumber: Int
    public let rTimeSec: Double
    public let rIndex: Int
    public let qOnIndex: Int
    public let tPeakIndex: Int
    public let tEndIndex: Int
    public let rrMs: Double
    public let qtMs: Double
    public let qtcBazett: Double
    public let qtcFridericia: Double
}

public struct MedianBeatData {
    public let wave: [Double]
    public let timeRelMs: [Double]
    public let rIndex: Int
    public let qOnIndex: Int
    public let tPeakIndex: Int
    public let tEndIndex: Int
    public let kSlopeIndex: Int
    public let mSlope: Double
    public let vSlope: Double
    public let vIso: Double
    public let qtMs: Double
    public let qrsMs: Double
    public let rrMs: Double
    public let qtcBazett: Double
    public let qtcFridericia: Double
    public let qtcFramingham: Double
    public let qtcHodges: Double
}

public struct QTAnalysisSummary {
    public let qtMs: Double
    public let qtcFridericia: Double
    public let qtcBazett: Double
    public let qtcFramingham: Double
    public let qtcHodges: Double
    public let rrMs: Double
    public let hrBpm: Double
    public let qrsMs: Double
    public let isReliable: Bool
    public let beatsAnalyzed: Int
    public let beatsTotal: Int
    public let beatQtMedian: Double
    public let beatQtIqr: Double

    public func evaluate(for gender: Gender) -> (status: QTcStatus, text: String, isWarning: Bool) {
        let val = qtcFridericia
        if val <= 0 {
            return (.normal, "Calcolo non disponibile", false)
        }
        if val < 350.0 {
            return (.shortened, "QTc Fridericia \(Int(val)) ms < 350 ms (Accorciato)", true)
        }
        switch gender {
        case .male:
            if val < 450.0 {
                return (.normal, "QTc Fridericia \(Int(val)) ms nella norma (Uomo < 450 ms)", false)
            } else if val <= 470.0 {
                return (.borderline, "QTc Fridericia \(Int(val)) ms Borderline (Uomo 450-470 ms)", true)
            } else {
                return (.prolonged, "QTc Fridericia \(Int(val)) ms Prolungato (Uomo > 470 ms)", true)
            }
        case .female:
            if val < 460.0 {
                return (.normal, "QTc Fridericia \(Int(val)) ms nella norma (Donna < 460 ms)", false)
            } else if val <= 480.0 {
                return (.borderline, "QTc Fridericia \(Int(val)) ms Borderline (Donna 460-480 ms)", true)
            } else {
                return (.prolonged, "QTc Fridericia \(Int(val)) ms Prolungato (Donna > 480 ms)", true)
            }
        }
    }
}

public struct HRVMetrics {
    public let meanRR: Double
    public let sdnn: Double
    public let rmssd: Double
    public let pnn50: Double
}

public struct ECGAnalysisReport {
    public let metadata: ECGMetadata
    public let fs: Double
    public let durationSec: Double
    public let rawSignal: [Double]
    public let filteredSignal: [Double]
    public let rPeakIndices: [Int]
    public let pPeakIndices: [Int]
    public let bpm: Double
    public let hrv: HRVMetrics
    public let rrIntervalsMs: [Double]
    public let qtSummary: QTAnalysisSummary?
    public let medianBeat: MedianBeatData?
    public let beats: [QTBeatResult]
    public var userNotes: String = ""
}
