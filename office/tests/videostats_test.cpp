#include "../../app/office/videostats.h"
#include <Limelight.h>
#include <atomic>
#include <cassert>
#include <iostream>
#include <thread>

namespace {
// Same field names as VIDEO_STATS, so copyVideoStats is checked without FFmpeg.
struct FakeStats {
    uint32_t receivedFrames = 0;
    double totalFps = 60.5, receivedFps = 60.0, decodedFps = 59.9, renderedFps = 59.6;
    uint32_t totalFrames = 1000, decodedFrames = 990, renderedFrames = 980;
    uint32_t networkDroppedFrames = 10, pacerDroppedFrames = 5;
    uint16_t minHostProcessingLatency = 12, maxHostProcessingLatency = 34;
    uint32_t totalHostProcessingLatency = 2000, framesWithHostProcessingLatency = 100;
    uint64_t totalDecodeTimeUs = 1980000, totalPacerTimeUs = 980000, totalRenderTimeUs = 2940000;
    uint32_t lastRtt = 12, lastRttVariance = 3;
};

bool contains(const std::string& text, const char* part) { return text.find(part) != std::string::npos; }
}

int main() {
    using namespace office;
    VideoStatsSample empty;
    assert(videoStatsSummary(empty).empty());
    assert(videoStatsDetails(empty).empty());

    VideoStatsSample sample;
    copyVideoStats(FakeStats{}, sample);
    assert(sample.rttMs == 12 && sample.rttVarianceMs == 3);
    assert(sample.minHostLatency == 12 && sample.maxHostLatency == 34);
    assert(sample.framesWithHostLatency == 100 && sample.renderedFrames == 980);
    // Bitrate unknown: left out instead of showing a negative value.
    assert(videoStatsSummary(sample) == "延迟 12 ms · 60 帧/秒");
    sample.averageMbps = 18.46;
    sample.peakMbps = 25.0;
    sample.bitrateWindowSeconds = 10;
    sample.width = 1920;
    sample.height = 1080;
    sample.codec = videoCodecName(VIDEO_FORMAT_H265, false);
    assert(sample.codec == "HEVC");
    assert(videoStatsSummary(sample) == "延迟 12 ms · 60 帧/秒 · 18.5 Mbps");
    const std::string details = videoStatsDetails(sample);
    assert(contains(details, "视频：1920×1080 · 60.50 帧/秒 · HEVC"));
    assert(contains(details, "码率：18.5 Mbps（10 秒内峰值 25.0 Mbps）"));
    assert(contains(details, "网络接收帧率：60.00 帧/秒"));
    assert(contains(details, "主机处理延迟（最小/最大/平均）：1.2 / 3.4 / 2.0 ms"));
    assert(contains(details, "网络丢帧：1.00%"));
    assert(contains(details, "网络延迟：12 ms（波动 3 ms）"));
    assert(contains(details, "平均解码时间：2.00 ms"));
    assert(contains(details, "平均渲染时间（含垂直同步）：3.00 ms"));
    assert(details.back() != '\n');

    // No RTT estimate yet: summary omits it, details say so.
    sample.rttMs = 0;
    assert(videoStatsSummary(sample) == "60 帧/秒 · 18.5 Mbps");
    assert(contains(videoStatsDetails(sample), "网络延迟：暂无"));

    assert(videoCodecName(VIDEO_FORMAT_H264, false) == "H.264");
    assert(videoCodecName(VIDEO_FORMAT_H265_MAIN10, true) == "HEVC 10 位 HDR");
    assert(videoCodecName(VIDEO_FORMAT_AV1_HIGH10_444, false) == "AV1 10 位 SDR 4:4:4");
    assert(videoCodecName(0, false).empty());

    VideoStatsChannel channel;
    VideoStatsSample taken;
    assert(!channel.take(taken));
    channel.publish(sample);
    sample.width = 2560;
    channel.publish(sample);
    assert(channel.take(taken) && taken.width == 2560); // only the newest sample
    assert(!channel.take(taken));
    channel.publish(sample);
    channel.clear();
    assert(!channel.take(taken));
    // Decoder thread publishes while the main thread takes.
    std::atomic_bool done{false};
    std::thread producer([&channel, &done, sample] {
        for (int i = 0; i < 1000; ++i) channel.publish(sample);
        done = true;
    });
    while (!done.load()) {
        if (channel.take(taken)) assert(taken.codec == "HEVC" && taken.width == 2560);
    }
    producer.join();
    channel.publish(sample);
    assert(channel.take(taken) && taken.codec == "HEVC");
    std::cout << "PASS: video statistics Chinese summary/details, codec names, latest-sample channel\n";
}
