#include "videostats.h"
#include <Limelight.h>
#include <cstdarg>
#include <cstdio>

namespace office {
namespace {
void append(std::string& text, const char* separator, const char* format, ...) {
    char buffer[160];
    va_list args;
    va_start(args, format);
    const int length = vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);
    if (length <= 0) return;
    if (!text.empty()) text += separator;
    text += buffer;
}
double perFrameMs(uint64_t totalUs, uint32_t frames) {
    return static_cast<double>(totalUs) / 1000.0 / frames;
}
}

std::string videoCodecName(int videoFormat, bool hdr) {
    const char* depth = hdr ? "10 位 HDR" : "10 位 SDR";
    switch (videoFormat) {
    case VIDEO_FORMAT_H264: return "H.264";
    case VIDEO_FORMAT_H264_HIGH8_444: return "H.264 4:4:4";
    case VIDEO_FORMAT_H265: return "HEVC";
    case VIDEO_FORMAT_H265_REXT8_444: return "HEVC 4:4:4";
    case VIDEO_FORMAT_H265_MAIN10: return std::string("HEVC ") + depth;
    case VIDEO_FORMAT_H265_REXT10_444: return std::string("HEVC ") + depth + " 4:4:4";
    case VIDEO_FORMAT_AV1_MAIN8: return "AV1";
    case VIDEO_FORMAT_AV1_HIGH8_444: return "AV1 4:4:4";
    case VIDEO_FORMAT_AV1_MAIN10: return std::string("AV1 ") + depth;
    case VIDEO_FORMAT_AV1_HIGH10_444: return std::string("AV1 ") + depth + " 4:4:4";
    default: return {};
    }
}

std::string videoStatsSummary(const VideoStatsSample& sample) {
    std::string text;
    if (sample.rttMs > 0) append(text, " · ", "延迟 %u ms", sample.rttMs);
    if (sample.receivedFps > 0) append(text, " · ", "%.0f 帧/秒", sample.renderedFps);
    if (sample.averageMbps > 0) append(text, " · ", "%.1f Mbps", sample.averageMbps);
    return text;
}

std::string videoStatsDetails(const VideoStatsSample& sample) {
    std::string text;
    const char* line = "\n";
    if (sample.receivedFps > 0 && sample.width > 0 && sample.height > 0) {
        if (sample.codec.empty())
            append(text, line, "视频：%d×%d · %.2f 帧/秒", sample.width, sample.height, sample.totalFps);
        else
            append(text, line, "视频：%d×%d · %.2f 帧/秒 · %s", sample.width, sample.height,
                   sample.totalFps, sample.codec.c_str());
    }
    if (sample.averageMbps > 0) {
        if (sample.peakMbps > 0 && sample.bitrateWindowSeconds > 0)
            append(text, line, "码率：%.1f Mbps（%u 秒内峰值 %.1f Mbps）", sample.averageMbps,
                   sample.bitrateWindowSeconds, sample.peakMbps);
        else
            append(text, line, "码率：%.1f Mbps", sample.averageMbps);
    }
    if (sample.receivedFps > 0) {
        append(text, line, "网络接收帧率：%.2f 帧/秒", sample.receivedFps);
        append(text, line, "解码帧率：%.2f 帧/秒", sample.decodedFps);
        append(text, line, "渲染帧率：%.2f 帧/秒", sample.renderedFps);
    }
    if (sample.framesWithHostLatency > 0) {
        append(text, line, "主机处理延迟（最小/最大/平均）：%.1f / %.1f / %.1f ms",
               sample.minHostLatency / 10.0, sample.maxHostLatency / 10.0,
               static_cast<double>(sample.totalHostLatency) / 10.0 / sample.framesWithHostLatency);
    }
    if (sample.renderedFrames != 0) {
        if (sample.totalFrames > 0)
            append(text, line, "网络丢帧：%.2f%%", 100.0 * sample.networkDroppedFrames / sample.totalFrames);
        if (sample.decodedFrames > 0)
            append(text, line, "抖动丢帧：%.2f%%", 100.0 * sample.pacerDroppedFrames / sample.decodedFrames);
        if (sample.rttMs > 0)
            append(text, line, "网络延迟：%u ms（波动 %u ms）", sample.rttMs, sample.rttVarianceMs);
        else
            append(text, line, "网络延迟：暂无");
        if (sample.decodedFrames > 0)
            append(text, line, "平均解码时间：%.2f ms", perFrameMs(sample.totalDecodeTimeUs, sample.decodedFrames));
        append(text, line, "平均排队延迟：%.2f ms", perFrameMs(sample.totalPacerTimeUs, sample.renderedFrames));
        append(text, line, "平均渲染时间（含垂直同步）：%.2f ms",
               perFrameMs(sample.totalRenderTimeUs, sample.renderedFrames));
    }
    return text;
}

void VideoStatsChannel::publish(const VideoStatsSample& sample) {
    std::lock_guard<std::mutex> lock(m_Lock);
    m_Sample = sample;
    m_Fresh = true;
}

bool VideoStatsChannel::take(VideoStatsSample& sample) {
    if (!m_Fresh.load()) return false;
    std::lock_guard<std::mutex> lock(m_Lock);
    if (!m_Fresh.load()) return false;
    sample = m_Sample;
    m_Fresh = false;
    return true;
}

void VideoStatsChannel::clear() {
    std::lock_guard<std::mutex> lock(m_Lock);
    m_Sample = {};
    m_Fresh = false;
}

VideoStatsChannel& videoStatsChannel() {
    static VideoStatsChannel channel;
    return channel;
}
}
