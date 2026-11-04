import Foundation

public enum Gender: String, CaseIterable, Identifiable, Codable {
    case male = "Uomo"
    case female = "Donna"
    public var id: String { rawValue }
}

public enum QTcStatus: String, Codable {
    case normal = "Normale"
    case borderline = "Borderline"
    case prolonged = "Prolungato (Attenzione)"
    case shortened = "Accorciato (< 350 ms)"
}

public enum LeadSelection: String, CaseIterable, Identifiable, Codable {
    case lead1 = "Lead I"
    case lead2 = "Lead II"
    case lead3 = "Lead III"
    case average = "Media (I+II+III)"
    
    public var id: String { rawValue }
}

public struct ECGMetadata: Codable {
    public var recordedDate: String = "N/D"
    public var classification: String = "N/D"
    public var sampleRate: Double = 512.0
    public var device: String = "Apple Watch"
    public var lead: String = "Lead I"
    public var symptoms: String = "Nessuno"
    public var units: String = "mV"
    
    public init(recordedDate: String = "N/D", classification: String = "N/D", sampleRate: Double = 512.0, device: String = "Apple Watch", lead: String = "Lead I", symptoms: String = "Nessuno", units: String = "mV") {
        self.recordedDate = recordedDate
        self.classification = classification
        self.sampleRate = sampleRate
        self.device = device
        self.lead = lead
        self.symptoms = symptoms
        self.units = units
    }
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
    
    public init(beatNumber: Int, rTimeSec: Double, rIndex: Int, qOnIndex: Int, tPeakIndex: Int, tEndIndex: Int, rrMs: Double, qtMs: Double, qtcBazett: Double, qtcFridericia: Double) {
        self.beatNumber = beatNumber
        self.rTimeSec = rTimeSec
        self.rIndex = rIndex
        self.qOnIndex = qOnIndex
        self.tPeakIndex = tPeakIndex
        self.tEndIndex = tEndIndex
        self.rrMs = rrMs
        self.qtMs = qtMs
        self.qtcBazett = qtcBazett
        self.qtcFridericia = qtcFridericia
    }
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
    
    public init(wave: [Double], timeRelMs: [Double], rIndex: Int, qOnIndex: Int, tPeakIndex: Int, tEndIndex: Int, kSlopeIndex: Int, mSlope: Double, vSlope: Double, vIso: Double, qtMs: Double, qrsMs: Double, rrMs: Double, qtcBazett: Double, qtcFridericia: Double, qtcFramingham: Double, qtcHodges: Double) {
        self.wave = wave
        self.timeRelMs = timeRelMs
        self.rIndex = rIndex
        self.qOnIndex = qOnIndex
        self.tPeakIndex = tPeakIndex
        self.tEndIndex = tEndIndex
        self.kSlopeIndex = kSlopeIndex
        self.mSlope = mSlope
        self.vSlope = vSlope
        self.vIso = vIso
        self.qtMs = qtMs
        self.qrsMs = qrsMs
        self.rrMs = rrMs
        self.qtcBazett = qtcBazett
        self.qtcFridericia = qtcFridericia
        self.qtcFramingham = qtcFramingham
        self.qtcHodges = qtcHodges
    }
}

public struct QTAnalysisSummary {
    public let qtMs: Double
    public let qtcBazett: Double
    public let qtcFridericia: Double
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

    public init(qtMs: Double, qtcBazett: Double, qtcFridericia: Double, qtcFramingham: Double, qtcHodges: Double, rrMs: Double, hrBpm: Double, qrsMs: Double, isReliable: Bool, beatsAnalyzed: Int, beatsTotal: Int, beatQtMedian: Double, beatQtIqr: Double) {
        self.qtMs = qtMs
        self.qtcBazett = qtcBazett
        self.qtcFridericia = qtcFridericia
        self.qtcFramingham = qtcFramingham
        self.qtcHodges = qtcHodges
        self.rrMs = rrMs
        self.hrBpm = hrBpm
        self.qrsMs = qrsMs
        self.isReliable = isReliable
        self.beatsAnalyzed = beatsAnalyzed
        self.beatsTotal = beatsTotal
        self.beatQtMedian = beatQtMedian
        self.beatQtIqr = beatQtIqr
    }

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
    public let sd1: Double
    public let sd2: Double
    public let sd1Sd2Ratio: Double
    public let correlationRho: Double
    
    public init(meanRR: Double, sdnn: Double, rmssd: Double, pnn50: Double, sd1: Double = 0.0, sd2: Double = 0.0, sd1Sd2Ratio: Double = 0.0, correlationRho: Double = 0.0) {
        self.meanRR = meanRR
        self.sdnn = sdnn
        self.rmssd = rmssd
        self.pnn50 = pnn50
        self.sd1 = sd1
        self.sd2 = sd2
        self.sd1Sd2Ratio = sd1Sd2Ratio
        self.correlationRho = correlationRho
    }
}

public struct PhasorAnalysisData {
    public let signal: [Double]
    public let phasor: [Double]
    public let pPeaks: [Int]
    public let prIntervalsMs: [Double]
    public let meanPRMs: Double
    public let prStatus: String
    
    public init(signal: [Double], phasor: [Double], pPeaks: [Int], prIntervalsMs: [Double], meanPRMs: Double, prStatus: String) {
        self.signal = signal
        self.phasor = phasor
        self.pPeaks = pPeaks
        self.prIntervalsMs = prIntervalsMs
        self.meanPRMs = meanPRMs
        self.prStatus = prStatus
    }
}

public struct PanTompkinsAnalysisData {
    public let windowSignal: [Double]
    public let rPeaks: [Int]
    public let threshold: Double
    
    public init(windowSignal: [Double], rPeaks: [Int], threshold: Double) {
        self.windowSignal = windowSignal
        self.rPeaks = rPeaks
        self.threshold = threshold
    }
}

public struct SpectrogramData {
    public let timeBins: [Double]
    public let freqBins: [Double]
    public let matrix: [[Double]] // rows: freqs, cols: times
    public let minDb: Double
    public let maxDb: Double
    
    public init(timeBins: [Double], freqBins: [Double], matrix: [[Double]], minDb: Double, maxDb: Double) {
        self.timeBins = timeBins
        self.freqBins = freqBins
        self.matrix = matrix
        self.minDb = minDb
        self.maxDb = maxDb
    }
}

public struct VCGPoint3D {
    public let x: Double
    public let y: Double
    public let z: Double
    
    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
}

public struct VCGData {
    public let points: [VCGPoint3D]
    public let isMultiChannel: Bool
    
    public init(points: [VCGPoint3D], isMultiChannel: Bool) {
        self.points = points
        self.isMultiChannel = isMultiChannel
    }
}

public struct TachogramData {
    public let beatTimesSec: [Double]
    public let rrIntervalsMs: [Double]
    public let instantBpm: [Double]
    
    public init(beatTimesSec: [Double], rrIntervalsMs: [Double], instantBpm: [Double]) {
        self.beatTimesSec = beatTimesSec
        self.rrIntervalsMs = rrIntervalsMs
        self.instantBpm = instantBpm
    }
}

public struct MultiLeadData {
    public let hasMultipleLeads: Bool
    public let lead1: [Double]
    public let lead2: [Double]
    public let lead3: [Double]
    public let average: [Double]
    
    public init(hasMultipleLeads: Bool, lead1: [Double], lead2: [Double], lead3: [Double], average: [Double]) {
        self.hasMultipleLeads = hasMultipleLeads
        self.lead1 = lead1
        self.lead2 = lead2
        self.lead3 = lead3
        self.average = average
    }
}

public struct SavedRecordingItem: Identifiable, Codable {
    public var id: UUID = UUID()
    public var fileName: String
    public var displayName: String
    public var dateStr: String
    public var classification: String
    public var bpm: Double
    public var qtcFridericia: Double
    public var durationSec: Double
    public var isMultiLead: Bool
    public var isSample: Bool
    
    public init(id: UUID = UUID(), fileName: String, displayName: String, dateStr: String, classification: String, bpm: Double, qtcFridericia: Double, durationSec: Double, isMultiLead: Bool = false, isSample: Bool = false) {
        self.id = id
        self.fileName = fileName
        self.displayName = displayName
        self.dateStr = dateStr
        self.classification = classification
        self.bpm = bpm
        self.qtcFridericia = qtcFridericia
        self.durationSec = durationSec
        self.isMultiLead = isMultiLead
        self.isSample = isSample
    }
}

public struct ECGAnalysisReport {
    public let metadata: ECGMetadata
    public let fs: Double
    public let durationSec: Double
    public var selectedLead: LeadSelection
    public let multiLead: MultiLeadData
    public let rawSignal: [Double]
    public let filteredSignal: [Double]
    public let rPeakIndices: [Int]
    public let bpm: Double
    public let hrv: HRVMetrics
    public let tachogram: TachogramData
    public let phasorData: PhasorAnalysisData
    public let panTompkinsData: PanTompkinsAnalysisData
    public let spectrogramData: SpectrogramData
    public let vcgData: VCGData
    public let qtSummary: QTAnalysisSummary?
    public let medianBeat: MedianBeatData?
    public let beats: [QTBeatResult]
    public var userNotes: String = ""
    
    public init(metadata: ECGMetadata, fs: Double, durationSec: Double, selectedLead: LeadSelection = .lead1, multiLead: MultiLeadData, rawSignal: [Double], filteredSignal: [Double], rPeakIndices: [Int], bpm: Double, hrv: HRVMetrics, tachogram: TachogramData, phasorData: PhasorAnalysisData, panTompkinsData: PanTompkinsAnalysisData, spectrogramData: SpectrogramData, vcgData: VCGData, qtSummary: QTAnalysisSummary?, medianBeat: MedianBeatData?, beats: [QTBeatResult], userNotes: String = "") {
        self.metadata = metadata
        self.fs = fs
        self.durationSec = durationSec
        self.selectedLead = selectedLead
        self.multiLead = multiLead
        self.rawSignal = rawSignal
        self.filteredSignal = filteredSignal
        self.rPeakIndices = rPeakIndices
        self.bpm = bpm
        self.hrv = hrv
        self.tachogram = tachogram
        self.phasorData = phasorData
        self.panTompkinsData = panTompkinsData
        self.spectrogramData = spectrogramData
        self.vcgData = vcgData
        self.qtSummary = qtSummary
        self.medianBeat = medianBeat
        self.beats = beats
        self.userNotes = userNotes
    }
}
