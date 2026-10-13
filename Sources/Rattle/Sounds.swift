import AVFoundation

/// Small synthesized cues so the app ships with no third-party audio.
final class Sounds {
    static let shared = Sounds()
    private var players: [String: AVAudioPlayer] = [:]

    private func tone(_ notes: [(Double, Double)], volume: Float = 0.25) -> AVAudioPlayer? {
        let rate = 44100.0
        var s = [Float]()
        for (freq, dur) in notes {
            let n = Int(rate * dur)
            for i in 0..<n {
                let t = Double(i) / rate
                let env = min(1, Double(i) / (rate * 0.01)) * min(1, Double(n - i) / (rate * 0.04))
                s.append(Float(sin(2 * .pi * freq * t) * env))
            }
        }
        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        let bytes = UInt32(s.count * 2)
        d.append("RIFF".data(using: .ascii)!); u32(36 + bytes); d.append("WAVEfmt ".data(using: .ascii)!)
        u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate) * 2); u16(2); u16(16)
        d.append("data".data(using: .ascii)!); u32(bytes)
        for v in s { var x = Int16(v * 32767).littleEndian; d.append(Data(bytes: &x, count: 2)) }
        let p = try? AVAudioPlayer(data: d)
        p?.volume = volume
        p?.prepareToPlay()
        return p
    }

    func play(_ name: String) {
        if players[name] == nil {
            switch name {
            case "start": players[name] = tone([(660, 0.07), (880, 0.09)])
            case "stop": players[name] = tone([(880, 0.06), (587, 0.1)])
            case "done": players[name] = tone([(1175, 0.05)], volume: 0.15)
            default: break
            }
        }
        players[name]?.currentTime = 0
        players[name]?.play()
    }
}
