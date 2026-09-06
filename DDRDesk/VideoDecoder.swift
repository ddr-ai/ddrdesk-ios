import Foundation
import VideoToolbox
import CoreMedia
import AVFoundation

/// Annex-B H.264 → AVSampleBufferDisplayLayer (hardware decode, lowest latency).
final class VideoSink {
    let layer = AVSampleBufferDisplayLayer()
    private var format: CMVideoFormatDescription?
    private var sps: Data?
    private var pps: Data?

    init() {
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = CGColor(gray: 0, alpha: 1)
        if #available(iOS 17.0, *) {
            layer.preventsDisplaySleepDuringVideoPlayback = true
        }
    }

    func reset() {
        format = nil
        sps = nil
        pps = nil
        if #available(iOS 18.0, *) {
            layer.sampleBufferRenderer.flush()
        } else {
            layer.flushAndRemoveImage()
        }
    }

    func submit(annexB: Data, keyframe: Bool) {
        let nals = splitAnnexB(annexB)
        for nal in nals {
            guard !nal.isEmpty else { continue }
            let t = nal[0] & 0x1F
            if t == 7 { sps = nal; format = nil }
            else if t == 8 { pps = nal; format = nil }
        }
        if format == nil { rebuildFormat() }
        guard let format else { return }

        var avcc = Data()
        for nal in nals {
            let t = nal[0] & 0x1F
            if t == 7 || t == 8 { continue }
            var len = UInt32(nal.count).bigEndian
            avcc.append(Data(bytes: &len, count: 4))
            avcc.append(nal)
        }
        guard !avcc.isEmpty else { return }

        var block: CMBlockBuffer?
        let rc = avcc.withUnsafeBytes { raw -> OSStatus in
            guard let p = raw.baseAddress else { return -1 }
            return CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: nil,
                blockLength: avcc.count,
                blockAllocator: kCFAllocatorDefault,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: avcc.count,
                flags: 0,
                blockBufferOut: &block
            )
        }
        guard rc == noErr, let block else { return }
        _ = avcc.withUnsafeBytes { raw in
            guard let p = raw.baseAddress else { return }
            CMBlockBufferReplaceDataBytes(with: p, blockBuffer: block, offsetIntoDestination: 0, dataLength: avcc.count)
        }

        var sample: CMSampleBuffer?
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )
        var size = avcc.count
        guard CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            formatDescription: format,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &size,
            sampleBufferOut: &sample
        ) == noErr, let sample else { return }

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            if !keyframe {
                CFDictionarySetValue(
                    dict,
                    Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque(),
                    Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
                )
            }
        }

        if #available(iOS 18.0, *) {
            layer.sampleBufferRenderer.enqueue(sample)
        } else {
            layer.enqueue(sample)
        }
    }

    private func rebuildFormat() {
        guard let sps, let pps else { return }
        let spsBytes = [UInt8](sps)
        let ppsBytes = [UInt8](pps)
        let status = spsBytes.withUnsafeBufferPointer { sBuf in
            ppsBytes.withUnsafeBufferPointer { pBuf in
                guard let sPtr = sBuf.baseAddress, let pPtr = pBuf.baseAddress else { return OSStatus(-1) }
                var ptrs: [UnsafePointer<UInt8>] = [sPtr, pPtr]
                var sizes: [Int] = [spsBytes.count, ppsBytes.count]
                return ptrs.withUnsafeBufferPointer { pPtrs in
                    sizes.withUnsafeBufferPointer { pSizes in
                        guard let pBase = pPtrs.baseAddress, let sBase = pSizes.baseAddress else {
                            return OSStatus(-1)
                        }
                        return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                            allocator: kCFAllocatorDefault,
                            parameterSetCount: 2,
                            parameterSetPointers: pBase,
                            parameterSetSizes: sBase,
                            nalUnitHeaderLength: 4,
                            formatDescriptionOut: &format
                        )
                    }
                }
            }
        }
        if status != noErr {
            format = nil
        }
    }
}

func splitAnnexB(_ data: Data) -> [Data] {
    var out: [Data] = []
    let bytes = [UInt8](data)
    var i = 0
    var start: Int?
    func isStart(_ i: Int) -> Int? {
        if i + 3 < bytes.count, bytes[i] == 0, bytes[i+1] == 0, bytes[i+2] == 0, bytes[i+3] == 1 { return 4 }
        if i + 2 < bytes.count, bytes[i] == 0, bytes[i+1] == 0, bytes[i+2] == 1 { return 3 }
        return nil
    }
    while i < bytes.count {
        if let n = isStart(i) {
            if let s = start {
                out.append(Data(bytes[s..<i]))
            }
            i += n
            start = i
        } else {
            i += 1
        }
    }
    if let s = start, s < bytes.count {
        out.append(Data(bytes[s..<bytes.count]))
    }
    return out
}
