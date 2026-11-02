import Foundation

public struct ECGMetadata {
    public var recordedDate: String = "N/D"
    public var classification: String = "N/D"
    public var sampleRate: Double = 512.0
    public var device: String = "Apple Watch"
    public var lead: String = "Lead I"
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
    public let filteredSignal: [Double]
    public let rPeakIndices: [Int]
    public let bpm: Double
    public let hrv: HRVMetrics
    public let rrIntervalsMs: [Double]
    public let qtSummary: QTAnalysisSummary?
    public let medianBeat: MedianBeatData?
    public let beats: [QTBeatResult]
}
