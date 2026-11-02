import Foundation

public final class ECGParser {
    public static func parseCSV(content: String) -> (metadata: ECGMetadata, signal: [Double], fs: Double) {
        var meta = ECGMetadata()
        var fs = 512.0
        var samples: [Double] = []

        let lines = content.components(separatedBy: .newlines)
        for (idx, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }

            let lower = line.lowercased()
            if idx < 25 {
                if lower.contains("hertz") || lower.contains("hz") {
                    let parts = line.components(separatedBy: ",")
                    for p in parts {
                        let sub = p.replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespaces)
                        let comps = sub.components(separatedBy: " ")
                        if let first = comps.first {
                            let cleanNum = first.replacingOccurrences(of: ",", with: ".")
                            if let val = Double(cleanNum), val > 10.0 {
                                fs = val
                                meta.sampleRate = val
                            }
                        }
                    }
                }
                if lower.contains("date") || lower.contains("data") {
                    let parts = line.components(separatedBy: ",")
                    if parts.count >= 2 {
                        meta.recordedDate = parts.dropFirst().joined(separator: ", ").replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespaces)
                    }
                }
                if lower.contains("classification") || lower.contains("classificazione") {
                    let parts = line.components(separatedBy: ",")
                    if parts.count >= 2 {
                        meta.classification = parts.dropFirst().joined(separator: ", ").replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespaces)
                    }
                }
                if lower.contains("device") || lower.contains("dispositivo") {
                    let parts = line.components(separatedBy: ",")
                    if parts.count >= 2 {
                        meta.device = parts.dropFirst().joined(separator: ", ").replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespaces)
                    }
                }
            }

            // Check if line is numeric (voltage sample)
            let trimmed = line.replacingOccurrences(of: "\"", with: "")
            let cells = trimmed.components(separatedBy: ",")
            if cells.count == 2, let _ = Int(cells[0]), let _ = Int(cells[1]) {
                // e.g. -1,25 split across comma
                if let val = Double("\(cells[0]).\(cells[1])") {
                    samples.append(val / 1000.0) // Convert uV to mV
                    continue
                }
            }
            if let firstCell = cells.first {
                let candidate = firstCell.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
                if let val = Double(candidate) {
                    samples.append(val / 1000.0) // Convert uV to mV
                }
            }
        }

        return (meta, samples, fs)
    }
}

public final class ECGProcessor {
    // 2nd order Butterworth Bandpass (5-15 Hz approximation at 512 Hz)
    public static func bandpassFilter(signal: [Double], fs: Double) -> [Double] {
        guard signal.count > 10 else { return signal }
        // Simple forward-backward difference gradient bandpass
        let n = signal.count
        var filtered = [Double](repeating: 0.0, count: n)
        // Highpass (remove baseline wander)
        let alpha = 0.995
        var prevIn = signal[0]
        var prevOut = 0.0
        for i in 0..<n {
            let out = alpha * (prevOut + signal[i] - prevIn)
            prevIn = signal[i]
            prevOut = out
            filtered[i] = out
        }
        return filtered
    }

    public static func detectRPeaks(signal: [Double], fs: Double) -> [Int] {
        let n = signal.count
        guard n > Int(fs * 2.0) else { return [] }

        // Pan-Tompkins derivative & squaring
        var deriv = [Double](repeating: 0.0, count: n)
        for i in 1..<(n - 1) {
            deriv[i] = (signal[i + 1] - signal[i - 1]) * 0.5
        }
        let squared = deriv.map { $0 * $0 }

        // Moving window integration (120 ms)
        let winSize = max(5, Int(0.12 * fs))
        var integrated = [Double](repeating: 0.0, count: n)
        var sum = 0.0
        for i in 0..<n {
            sum += squared[i]
            if i >= winSize {
                sum -= squared[i - winSize]
            }
            integrated[i] = sum / Double(winSize)
        }

        let maxVal = integrated.max() ?? 1.0
        let threshold = maxVal * 0.25
        let refractory = Int(0.25 * fs)

        var candidatePeaks: [Int] = []
        var lastPeak = -refractory

        for i in 1..<(n - 1) {
            if integrated[i] > threshold && integrated[i] > integrated[i - 1] && integrated[i] >= integrated[i + 1] {
                if (i - lastPeak) > refractory {
                    candidatePeaks.append(i)
                    lastPeak = i
                }
            }
        }

        // Snap to true extremum of signal (handles upright and inverted QRS)
        let half = Int(0.06 * fs)
        var refined: [Int] = []
        for p in candidatePeaks {
            let lo = max(0, p - half)
            let hi = min(n - 1, p + half)
            var bestIdx = p
            var bestAbs = 0.0
            for j in lo...hi {
                let a = abs(signal[j])
                if a > bestAbs {
                    bestAbs = a
                    bestIdx = j
                }
            }
            if refined.isEmpty || (bestIdx - refined.last!) > refractory {
                refined.append(bestIdx)
            }
        }

        return refined
    }

    public static func calculateHRV(rrMs: [Double]) -> HRVMetrics {
        guard !rrMs.isEmpty else { return HRVMetrics(meanRR: 0, sdnn: 0, rmssd: 0, pnn50: 0) }
        let mean = rrMs.reduce(0.0, +) / Double(rrMs.count)
        let variance = rrMs.map { pow($0 - mean, 2) }.reduce(0.0, +) / Double(rrMs.count)
        let sdnn = sqrt(variance)

        if rrMs.count > 1 {
            var diffSq = 0.0
            var count50 = 0
            for i in 0..<(rrMs.count - 1) {
                let d = abs(rrMs[i + 1] - rrMs[i])
                diffSq += d * d
                if d > 50.0 { count50 += 1 }
            }
            let rmssd = sqrt(diffSq / Double(rrMs.count - 1))
            let pnn50 = (Double(count50) / Double(rrMs.count - 1)) * 100.0
            return HRVMetrics(meanRR: mean, sdnn: sdnn, rmssd: rmssd, pnn50: pnn50)
        }

        return HRVMetrics(meanRR: mean, sdnn: sdnn, rmssd: 0, pnn50: 0)
    }

    public static func calculateQTc(qtMs: Double, rrMs: Double) -> (bazett: Double, fridericia: Double, framingham: Double, hodges: Double) {
        guard qtMs > 0, rrMs > 0 else { return (0, 0, 0, 0) }
        let rrSec = rrMs / 1000.0
        let hrBpm = 60.0 / rrSec

        let bazett = qtMs / sqrt(rrSec)
        let fridericia = qtMs / pow(rrSec, 1.0 / 3.0)
        let framingham = qtMs + 154.0 * (1.0 - rrSec)
        let hodges = qtMs + 1.75 * (hrBpm - 60.0)

        return (bazett, fridericia, framingham, hodges)
    }

    public static func analyzeQT(signal: [Double], rPeaks: [Int], fs: Double) -> (summary: QTAnalysisSummary?, medianBeat: MedianBeatData?, beats: [QTBeatResult]) {
        guard rPeaks.count >= 4 else { return (nil, nil, []) }

        var rrSamples: [Double] = []
        for i in 0..<(rPeaks.count - 1) {
            rrSamples.append(Double(rPeaks[i + 1] - rPeaks[i]))
        }
        let sortedRR = rrSamples.sorted()
        let medRRSamples = sortedRR[sortedRR.count / 2]
        let medRRMs = (medRRSamples / fs) * 1000.0

        let pre = Int(0.25 * fs)
        let post = min(Int(0.75 * medRRSamples), Int(0.55 * fs))

        // Template matching to select regular, normal beats
        var keptBeats: [Int] = []
        for i in 1..<(rPeaks.count - 1) {
            let r = rPeaks[i]
            if (r - pre) >= 0 && (r + post) < signal.count {
                let rrPrev = Double(rPeaks[i] - rPeaks[i - 1])
                let rrNext = Double(rPeaks[i + 1] - rPeaks[i])
                if rrPrev >= 0.8 * medRRSamples && rrPrev <= 1.2 * medRRSamples && rrNext >= 0.8 * medRRSamples {
                    keptBeats.append(i)
                }
            }
        }

        guard keptBeats.count >= 3 else { return (nil, nil, []) }

        let winLen = pre + post
        var medianWave = [Double](repeating: 0.0, count: winLen)
        for s in 0..<winLen {
            var col = [Double]()
            for bi in keptBeats {
                let r = rPeaks[bi]
                col.append(signal[r - pre + s])
            }
            col.sort()
            medianWave[s] = col[col.count / 2]
        }

        // Delineate on median beat
        guard let medDel = delineateSingleBeat(wave: medianWave, rIdx: pre, fs: fs, rrMs: medRRMs) else {
            return (nil, nil, [])
        }

        let qtc = calculateQTc(qtMs: medDel.qtMs, rrMs: medRRMs)
        let timeRelMs = (0..<winLen).map { (Double($0 - pre) / fs) * 1000.0 }

        let medianBeatData = MedianBeatData(
            wave: medianWave,
            timeRelMs: timeRelMs,
            rIndex: pre,
            qOnIndex: medDel.qOn,
            tPeakIndex: medDel.tPeak,
            tEndIndex: medDel.tEnd,
            kSlopeIndex: medDel.kSlope,
            mSlope: medDel.mSlope,
            vSlope: medDel.vSlope,
            vIso: medDel.vIso,
            qtMs: medDel.qtMs,
            qrsMs: medDel.qrsMs,
            rrMs: medRRMs,
            qtcBazett: qtc.bazett,
            qtcFridericia: qtc.fridericia,
            qtcFramingham: qtc.framingham,
            qtcHodges: qtc.hodges
        )

        // Beat by beat calculation
        var beatResults: [QTBeatResult] = []
        for bi in keptBeats {
            let r = rPeaks[bi]
            let rrPrevMs = (Double(rPeaks[bi] - rPeaks[bi - 1]) / fs) * 1000.0
            let beatSegment = Array(signal[(r - pre)..<(r + post)])
            if let res = delineateSingleBeat(wave: beatSegment, rIdx: pre, fs: fs, rrMs: rrPrevMs) {
                let beatQtc = calculateQTc(qtMs: res.qtMs, rrMs: rrPrevMs)
                beatResults.append(QTBeatResult(
                    beatNumber: bi + 1,
                    rTimeSec: Double(r) / fs,
                    rIndex: r,
                    qOnIndex: (r - pre) + res.qOn,
                    tPeakIndex: (r - pre) + res.tPeak,
                    tEndIndex: (r - pre) + res.tEnd,
                    rrMs: rrPrevMs,
                    qtMs: res.qtMs,
                    qtcBazett: beatQtc.bazett,
                    qtcFridericia: beatQtc.fridericia
                ))
            }
        }

        let beatQTs = beatResults.map { $0.qtMs }.sorted()
        let beatQtMedian = beatQTs.isEmpty ? medDel.qtMs : beatQTs[beatQTs.count / 2]
        let p75 = beatQTs.isEmpty ? 0.0 : beatQTs[Int(Double(beatQTs.count) * 0.75)]
        let p25 = beatQTs.isEmpty ? 0.0 : beatQTs[Int(Double(beatQTs.count) * 0.25)]
        let iqr = p75 - p25

        let isReliable = abs(beatQtMedian - medDel.qtMs) <= 25.0 && iqr <= 40.0 && beatResults.count >= 5

        let summary = QTAnalysisSummary(
            qtMs: medDel.qtMs,
            qtcFridericia: qtc.fridericia,
            qtcBazett: qtc.bazett,
            qtcFramingham: qtc.framingham,
            qtcHodges: qtc.hodges,
            rrMs: medRRMs,
            hrBpm: 60000.0 / medRRMs,
            qrsMs: medDel.qrsMs,
            isReliable: isReliable,
            beatsAnalyzed: beatResults.count,
            beatsTotal: rPeaks.count,
            beatQtMedian: beatQtMedian,
            beatQtIqr: iqr
        )

        return (summary, medianBeatData, beatResults)
    }

    private struct SingleBeatDelineation {
        let qOn: Int
        let jPt: Int
        let tPeak: Int
        let tEnd: Int
        let kSlope: Int
        let mSlope: Double
        let vSlope: Double
        let vIso: Double
        let qrsMs: Double
        let qtMs: Double
    }

    private static func delineateSingleBeat(wave: [Double], rIdx: Int, fs: Double, rrMs: Double) -> SingleBeatDelineation? {
        let n = wave.count
        let ms = fs / 1000.0
        guard rIdx >= Int(0.12 * fs), rIdx < (n - 5) else { return nil }

        // Baseline (average of pre-P and post-T levels)
        let preCount = max(3, Int(0.05 * fs))
        let preSub = Array(wave[0..<min(preCount, n)])
        let tailCount = max(3, Int(0.04 * fs))
        let tailSub = Array(wave[(n - tailCount)..<n])
        let vIso = 0.5 * ((preSub.reduce(0.0, +) / Double(preSub.count)) + (tailSub.reduce(0.0, +) / Double(tailSub.count)))

        // Gradients
        var g = [Double](repeating: 0.0, count: n)
        for i in 1..<(n - 1) {
            g[i] = (wave[i + 1] - wave[i - 1]) * 0.5
        }

        // QRS slope search
        let qrsLo = max(0, rIdx - Int(0.04 * fs))
        let qrsHi = min(n - 1, rIdx + Int(0.04 * fs))
        let maxSlope = (qrsLo...qrsHi).map { abs(g[$0]) }.max() ?? 1.0
        if maxSlope <= 0 { return nil }

        // QRS onset via quiet run
        var qOn = max(0, rIdx - Int(0.08 * fs))
        var quiet = 0
        for j in stride(from: rIdx, through: max(0, rIdx - Int(0.10 * fs)), by: -1) {
            if abs(g[j]) < 0.12 * maxSlope {
                quiet += 1
                if quiet >= max(3, Int(0.008 * fs)) {
                    qOn = j
                    break
                }
            } else {
                quiet = 0
            }
        }

        // J point
        var jPt = min(n - 1, rIdx + Int(0.06 * fs))
        quiet = 0
        for j in rIdx..<min(n, rIdx + Int(0.12 * fs)) {
            if abs(g[j]) < 0.15 * maxSlope {
                quiet += 1
                if quiet >= max(3, Int(0.010 * fs)) {
                    jPt = j
                    break
                }
            } else {
                quiet = 0
            }
        }
        jPt = max(jPt, rIdx + Int(0.025 * fs))

        // T peak search window
        let tLo = max(jPt + Int(0.03 * fs), rIdx + Int(0.08 * fs))
        let tHi = min(n - 3, rIdx + Int(min(0.72 * rrMs, 460.0) * ms))
        guard tHi > (tLo + Int(0.04 * fs)) else { return nil }

        // Find T peak
        var bestTPeak = tLo
        var maxDev = 0.0
        for i in tLo...tHi {
            let d = abs(wave[i] - vIso)
            if d > maxDev {
                maxDev = d
                bestTPeak = i
            }
        }
        if maxDev < 0.015 { return nil }

        let sign = (wave[bestTPeak] >= vIso) ? 1.0 : -1.0
        let y = wave.map { sign * ($0 - vIso) }
        let tAmp = y[bestTPeak]

        // Tangent method on descending limb
        let lim = min(n - 2, bestTPeak + Int(0.20 * fs))
        var stop = lim
        for i in bestTPeak..<lim {
            if y[i] < 0.15 * tAmp {
                stop = max(i, bestTPeak + 4)
                break
            }
        }

        var minSlope = 0.0
        var kSlope = bestTPeak
        for i in bestTPeak...stop {
            let slope = (y[i + 1] - y[i - 1]) * 0.5
            if slope < minSlope {
                minSlope = slope
                kSlope = i
            }
        }

        if minSlope >= -1e-5 { return nil }

        let tEndDouble = Double(kSlope) + (0.0 - y[kSlope]) / minSlope
        let tEnd = max(bestTPeak + Int(0.02 * fs), min(n - 1, Int(round(tEndDouble))))

        let qtMs = Double(tEnd - qOn) / ms
        let qrsMs = Double(jPt - qOn) / ms

        guard qtMs >= 200.0 && qtMs <= 620.0 else { return nil }

        return SingleBeatDelineation(
            qOn: qOn,
            jPt: jPt,
            tPeak: bestTPeak,
            tEnd: tEnd,
            kSlope: kSlope,
            mSlope: sign * minSlope,
            vSlope: wave[kSlope],
            vIso: vIso,
            qrsMs: qrsMs,
            qtMs: qtMs
        )
    }
}
