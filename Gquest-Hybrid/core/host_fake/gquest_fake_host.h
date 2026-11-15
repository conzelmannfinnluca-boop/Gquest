// A host made only of in-memory pieces, for driving the core without an engine.
//
// This is gate G2 from PROJECT_STATUS.md: 60 frames, the playspace and the content
// installation, with no OpenXR, no Android and no Source engine. The pieces are deliberately
// plain containers - the point is not to simulate a device, it is to be able to say that the
// core runs, that it refuses what it should refuse, and that the installation contract holds
// outside the APK.
//
// The installation mirrors quest_engine_bridge.cpp instead of inventing a friendlier rule:
// parse the whole listing first, skip an already installed file whose size matches unless it
// is a lua/ file, require the shipped size to match, and stop at the first failure.
#pragma once
#include <cstddef>
#include <cstdint>
#include <cmath>
#include <map>
#include <string>
#include <vector>

#include "gquest_content_install.h"
#include "gquest_platform_host.h"

namespace GquestFake {

using Bytes = std::vector<std::uint8_t>;
using GquestPlatform::Hand;
using GquestPlatform::LogLevel;
using GquestPlatform::VrFrame;

struct Clock : GquestPlatform::IClock {
    double now = 0;
    // A backwards or non-finite step is ignored here so a scenario cannot produce the very
    // situation the core is meant to survive.
    void Advance(double seconds) {
        if (std::isfinite(seconds) && seconds > 0.0) now += seconds;
    }
    double NowSeconds() const override { return now; }
};

struct Log : GquestPlatform::ILog {
    struct Record {
        LogLevel level;
        std::string text;
    };
    std::vector<Record> records;
    void Write(LogLevel level, const char* message) override {
        records.push_back({level, message ? message : ""});
    }
    void Clear() { records.clear(); }
    std::size_t Count(LogLevel level) const {
        std::size_t count = 0;
        for (const auto& record : records)
            if (record.level == level) ++count;
        return count;
    }
    bool Has(LogLevel level, const char* needle) const {
        for (const auto& record : records)
            if (record.level == level && record.text.find(needle) != std::string::npos)
                return true;
        return false;
    }
};

struct Assets : GquestPlatform::IAssetSource {
    std::map<std::string, Bytes> staged;     // what the installation ships
    std::map<std::string, Bytes> installed;  // what ended up under the content root

    bool Exists(const char* relativePath) override {
        return GquestPlatform::GquestAssetPathAllowed(relativePath) &&
               installed.count(relativePath) > 0;
    }
    bool Read(const char* relativePath, std::size_t maxBytes, Bytes& out) override {
        if (!GquestPlatform::GquestAssetPathAllowed(relativePath)) return false;
        const auto found = installed.find(relativePath);
        if (found == installed.end() || found->second.size() > maxBytes) return false;
        out = found->second;
        return true;
    }

    struct InstallResult {
        bool ok = false;
        unsigned installed = 0;   // written during this run
        unsigned existing = 0;    // already present with the expected size
        unsigned long long writtenBytes = 0;
        GquestManifestError manifestError = GquestManifestError::None;
        std::string failedPath;   // first entry that aborted the run, empty when ok
        bool sizeMismatch = false;
    };

    InstallResult InstallManifest(const std::string& listing) {
        InstallResult result;
        std::vector<GquestContentEntry> entries;
        if (listing.empty() ||
            !GquestParseContentManifest(listing, entries, result.manifestError)) {
            // Nothing is written: the listing is judged before the first file, exactly like
            // the device installation does.
            return result;
        }
        for (const GquestContentEntry& entry : entries) {
            const std::string& relative = entry.relative;
            const bool alwaysRewrite = relative.compare(0, 4, "lua/") == 0;
            const auto present = installed.find(relative);
            if (!alwaysRewrite && present != installed.end() &&
                present->second.size() == entry.bytes) {
                ++result.existing;
                continue;
            }
            const auto shipped = staged.find(relative);
            if (shipped == staged.end()) {
                result.failedPath = relative;
                return result;
            }
            if (shipped->second.size() != entry.bytes) {
                result.failedPath = relative;
                result.sizeMismatch = true;
                return result;
            }
            installed[relative] = shipped->second;
            ++result.installed;
            result.writtenBytes += shipped->second.size();
        }
        result.ok = true;
        return result;
    }
};

struct VrBackend : GquestPlatform::IVRBackend {
    std::vector<VrFrame> frames;  // one frame per Poll, then nothing available
    std::size_t next = 0;
    std::vector<Hand> hapticHands;
    bool Poll(VrFrame& out) override {
        if (next >= frames.size()) return false;
        out = frames[next++];
        return true;
    }
    bool Haptic(Hand hand, float seconds, float frequencyHz, float amplitude) override {
        if (!GquestPlatform::GquestHapticArgumentsAllowed(seconds, frequencyHz, amplitude))
            return false;
        hapticHands.push_back(hand);
        return true;
    }
};

struct Host : GquestPlatform::IPlatformHost {
    // Qualified on purpose: inside this class the member functions Clock(), Log(), Assets()
    // and Vr() hide the type names, so an unqualified `Clock clock;` does not compile.
    GquestFake::Clock clock;
    GquestFake::Log log;
    GquestFake::Assets assets;
    GquestFake::VrBackend vr;
    GquestPlatform::IClock& Clock() override { return clock; }
    GquestPlatform::ILog& Log() override { return log; }
    GquestPlatform::IAssetSource& Assets() override { return assets; }
    GquestPlatform::IVRBackend& Vr() override { return vr; }
};

inline bool FinitePose(const GquestPlayspace::Pose& pose) {
    return std::isfinite(pose.position.x) && std::isfinite(pose.position.y) &&
           std::isfinite(pose.position.z) && std::isfinite(pose.yaw);
}

struct RunResult {
    std::vector<GquestPlatform::FrameOutput> outputs;  // one per frame, valid or not
    int valid = 0;          // frames the core published
    int rejected = 0;       // frames it refused
    int handsPublished = 0;
    double elapsed = 0;     // clock time after the last frame
    bool finite = true;     // every published pose stayed finite
};

// Advances the clock, lets the caller act, then runs one core frame - `count` times. The hook
// runs before the frame so a turn or a recentre takes effect on that frame, the way a button
// press does.
template <typename OnFrame>
RunResult RunFrames(Host& host, GquestPlayspace::State& playspace, int count,
                    double frameSeconds, OnFrame onFrame) {
    RunResult result;
    if (count > 0) result.outputs.reserve(static_cast<std::size_t>(count));
    for (int index = 0; index < count; ++index) {
        host.clock.Advance(frameSeconds);
        onFrame(index);
        const GquestPlatform::FrameOutput output =
            GquestPlatform::GquestStepFrame(host, playspace);
        if (output.valid) {
            ++result.valid;
            if (!FinitePose(output.head)) result.finite = false;
        } else {
            ++result.rejected;
        }
        for (int hand = 0; hand < GquestPlatform::kHandCount; ++hand)
            if (output.handValid[hand]) {
                ++result.handsPublished;
                if (!FinitePose(output.hands[hand])) result.finite = false;
            }
        result.outputs.push_back(output);
    }
    result.elapsed = host.clock.NowSeconds();
    return result;
}

}  // namespace GquestFake
