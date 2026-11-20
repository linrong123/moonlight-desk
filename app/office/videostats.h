#pragma once
#include <atomic>
#include <cstdint>
#include <mutex>
#include <string>

namespace office {
// One-second window of the upstream VIDEO_STATS plus values the decoder derives
// for its own overlay (stream size, codec, bitrate). Plain data so the Chinese
// formatting below can be tested without FFmpeg or a live connection.
struct VideoStatsSample {
    int width = 0;
    int height = 0;
    std::string codec;
    double totalFps = 0, receivedFps = 0, decodedFps = 0, renderedFps = 0;
    uint32_t totalFrames = 0, decodedFrames = 0, renderedFrames = 0;
    uint32_t networkDroppedFrames = 0, pacerDroppedFrames = 0;
    // Host latency values are in 0.1 ms units, as reported by the host.
    uint32_t minHostLatency = 0, maxHostLatency = 0;
    uint64_t totalHostLatency = 0;
    uint32_t framesWithHostLatency = 0;
    uint64_t totalDecodeTimeUs = 0, totalPacerTimeUs = 0, totalRenderTimeUs = 0;
    // 0 means the control stream has no RTT estimate yet (upstream "N/A").
    uint32_t rttMs = 0, rttVarianceMs = 0;
    // Negative means unknown.
    double averageMbps = -1, peakMbps = -1;
    unsigned bitrateWindowSeconds = 0;
};

// Copies the counters by name, so any struct with VIDEO_STATS field names works.
template <typename Stats>
void copyVideoStats(const Stats& stats, VideoStatsSample& sample) {
    sample.totalFps = stats.totalFps;
    sample.receivedFps = stats.receivedFps;
    sample.decodedFps = stats.decodedFps;
    sample.renderedFps = stats.renderedFps;
    sample.totalFrames = stats.totalFrames;
    sample.decodedFrames = stats.decodedFrames;
    sample.renderedFrames = stats.renderedFrames;
    sample.networkDroppedFrames = stats.networkDroppedFrames;
    sample.pacerDroppedFrames = stats.pacerDroppedFrames;
    sample.minHostLatency = stats.minHostProcessingLatency;
    sample.maxHostLatency = stats.maxHostProcessingLatency;
    sample.totalHostLatency = stats.totalHostProcessingLatency;
    sample.framesWithHostLatency = stats.framesWithHostProcessingLatency;
    sample.totalDecodeTimeUs = stats.totalDecodeTimeUs;
    sample.totalPacerTimeUs = stats.totalPacerTimeUs;
    sample.totalRenderTimeUs = stats.totalRenderTimeUs;
    sample.rttMs = stats.lastRtt;
    sample.rttVarianceMs = stats.lastRttVariance;
}

// Mirrors the codec names of FFmpegVideoDecoder::stringifyVideoStats.
std::string videoCodecName(int videoFormat, bool hdr);
// One toolbar line, e.g. "延迟 12 ms · 60 帧/秒 · 18.5 Mbps". Items without data
// are left out; empty when nothing is known yet.
std::string videoStatsSummary(const VideoStatsSample& sample);
// Full Chinese statistics, one item per line, in upstream overlay order.
std::string videoStatsDetails(const VideoStatsSample& sample);

// Decoder thread publishes about once per second; the SDL main thread takes the
// latest sample. Only the newest sample is kept.
class VideoStatsChannel {
public:
    void publish(const VideoStatsSample& sample);
    bool take(VideoStatsSample& sample);
    void clear();
private:
    std::mutex m_Lock;
    VideoStatsSample m_Sample;
    std::atomic_bool m_Fresh{false};
};
VideoStatsChannel& videoStatsChannel();
}
