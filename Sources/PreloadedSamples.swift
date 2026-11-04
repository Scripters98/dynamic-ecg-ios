import Foundation

public struct ClinicalSample {
    public let id: String
    public let title: String
    public let subtitle: String
    public let fileName: String
    public let expectedBpm: Double
    public let expectedQTc: Double
    public let isMultiChannel: Bool
}

public final class PreloadedSamples {
    public static let allSamples: [ClinicalSample] = [
        ClinicalSample(
            id: "sample_normal",
            title: "Ritmo Sinusale Normale",
            subtitle: "Apple Watch · 70 BPM · QTc normale 415 ms",
            fileName: "Sample_AppleWatch_Normal",
            expectedBpm: 70.0,
            expectedQTc: 415.0,
            isMultiChannel: false
        ),
        ClinicalSample(
            id: "sample_tachycardia",
            title: "Tachicardia Sinusale",
            subtitle: "Apple Watch · 108 BPM · Frequenza elevata",
            fileName: "Sample_AppleWatch_Tachycardia",
            expectedBpm: 108.0,
            expectedQTc: 428.0,
            isMultiChannel: false
        ),
        ClinicalSample(
            id: "sample_bradycardia",
            title: "Bradicardia Sinusale",
            subtitle: "Apple Watch · 52 BPM · Frequenza bassa",
            fileName: "Sample_AppleWatch_Bradycardia",
            expectedBpm: 52.0,
            expectedQTc: 435.0,
            isMultiChannel: false
        ),
        ClinicalSample(
            id: "sample_holter",
            title: "Holter 3 Canali (3-Lead)",
            subtitle: "Elettrodi Holter · 180 Hz · Lead I, II, III",
            fileName: "Sample_Holter_3Channel",
            expectedBpm: 74.0,
            expectedQTc: 405.0,
            isMultiChannel: true
        )
    ]
    
    public static func loadSample(sample: ClinicalSample) -> (content: String, displayName: String) {
        if let url = Bundle.main.url(forResource: sample.fileName, withExtension: "csv"),
           let str = try? String(contentsOf: url, encoding: .utf8) {
            return (str, sample.title)
        }
        
        // Dynamic fallback synthesis if bundle resource is absent
        let str = generateFallbackCSV(sample: sample)
        return (str, sample.title)
    }
    
    private static func generateFallbackCSV(sample: ClinicalSample) -> String {
        var lines: [String] = []
        if sample.isMultiChannel {
            lines.append("# sample_rate: 180")
            lines.append("# Classification: Ritmo Sinusale Normale")
            lines.append("# Device: Holter 3 Canali")
            lines.append("time_seconds,channel_1,channel_2,channel_3")
            let fs = 180.0
            let total = Int(25.0 * fs)
            let rr = Int((60.0 / sample.expectedBpm) * fs)
            for i in 0..<total {
                let t = Double(i) / fs
                let beatPhase = i % rr
                var v1 = sin(2.0 * .pi * 1.2 * t) * 0.05
                var v2 = sin(2.0 * .pi * 1.2 * t) * 0.04
                var v3 = sin(2.0 * .pi * 1.2 * t) * 0.03
                
                // QRS complex
                if beatPhase >= 20 && beatPhase <= 28 {
                    let p = Double(beatPhase - 24)
                    v1 += (1.2 - abs(p) * 0.25)
                    v2 += (0.9 - abs(p) * 0.20)
                    v3 += (0.6 - abs(p) * 0.15)
                }
                // T wave
                if beatPhase >= 45 && beatPhase <= 65 {
                    let tp = sin(Double(beatPhase - 45) / 20.0 * .pi)
                    v1 += tp * 0.25
                    v2 += tp * 0.30
                    v3 += tp * 0.20
                }
                lines.append(String(format: "%.4f,%.1f,%.1f,%.1f", t, v1 * 1000.0, v2 * 1000.0, v3 * 1000.0))
            }
        } else {
            lines.append("Nome,Paziente Esempio")
            lines.append("Data di registrazione,\(Date().formatted())")
            lines.append("Classificazione,\(sample.expectedBpm > 100 ? "Frequenza cardiaca elevata" : (sample.expectedBpm < 60 ? "Bradicardia sinusale" : "Ritmo sinusale"))")
            lines.append("Dispositivo,Apple Watch")
            lines.append("Frequenza di campionamento,512,0 Hz")
            let fs = 512.0
            let total = Int(30.0 * fs)
            let rr = Int((60.0 / sample.expectedBpm) * fs)
            for i in 0..<total {
                let beatPhase = i % rr
                var v = 0.0
                if beatPhase >= 60 && beatPhase <= 80 {
                    // P wave
                    v += sin(Double(beatPhase - 60) / 20.0 * .pi) * 0.08
                }
                if beatPhase >= 110 && beatPhase <= 126 {
                    // QRS
                    let p = Double(beatPhase - 118)
                    v += (1.1 - abs(p) * 0.18)
                }
                if beatPhase >= 180 && beatPhase <= 250 {
                    // T wave
                    v += sin(Double(beatPhase - 180) / 70.0 * .pi) * 0.22
                }
                lines.append(String(format: "%.2f", v * 1000.0))
            }
        }
        return lines.joined(separator: "\n")
    }
}
