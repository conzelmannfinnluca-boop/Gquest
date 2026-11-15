// Boundary tests for the platform interfaces in core/platform/.
//
// The interfaces are abstract, so what can be tested here is the contract around them: the
// policy helpers, and a fake host that exercises the frame step the way a real host will.
// The fakes are deliberately plain - they are the executable statement of what a host has
// to do, so a host that disagrees with them is the thing that is wrong.
//
// Engine-free: this file includes standard headers, the core headers and the content
// installer's path rules, nothing else. If a core header ever pulled in an engine type, this
// translation unit would stop compiling - that is gate G1 in its cheapest form.
#include <cassert>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <map>
#include <string>
#include <vector>

#include "gquest_content_install.h"
#include "gquest_platform_host.h"

using namespace GquestPlatform;

namespace {

struct FakeClock : IClock {
    double now = 0;
    double NowSeconds() const override { return now; }
};

struct FakeLog : ILog {
    struct Record {
        LogLevel level;
        std::string text;
    };
    std::vector<Record> records;
    void Write(LogLevel level, const char* message) override {
        records.push_back({level, message ? message : ""});
    }
    bool HasWarning(const char* needle) const {
        for (const auto& record : records) {
            if (record.level == LogLevel::Warning &&
                record.text.find(needle) != std::string::npos)
                return true;
        }
        return false;
    }
};

struct FakeAssets : IAssetSource {
    std::map<std::string, std::vector<std::uint8_t>> files;
    bool Exists(const char* relativePath) override {
        return GquestAssetPathAllowed(relativePath) && files.count(relativePath) > 0;
    }
    bool Read(const char* relativePath, std::size_t maxBytes,
              std::vector<std::uint8_t>& out) override {
        if (!GquestAssetPathAllowed(relativePath)) return false;
        const auto found = files.find(relativePath);
        if (found == files.end() || found->second.size() > maxBytes) return false;
        out = found->second;
        return true;
    }
};

struct FakeVr : IVRBackend {
    VrFrame frame{};
    bool frameAvailable = false;
    int hapticCalls = 0;
    bool Poll(VrFrame& out) override {
        if (!frameAvailable) return false;
        out = frame;
        return true;
    }
    bool Haptic(Hand, float seconds, float frequencyHz, float amplitude) override {
        if (!GquestHapticArgumentsAllowed(seconds, frequencyHz, amplitude)) return false;
        ++hapticCalls;
        return true;
    }
};

struct FakeHost : IPlatformHost {
    FakeClock clock;
    FakeLog log;
    FakeAssets assets;
    FakeVr vr;
    IClock& Clock() override { return clock; }
    ILog& Log() override { return log; }
    IAssetSource& Assets() override { return assets; }
    IVRBackend& Vr() override { return vr; }
};

bool Near(double actual, double expected, double tolerance = 0.001) {
    return std::fabs(actual - expected) <= tolerance;
}

GquestPose::Snapshot Pose(float x, float y, float z, float yaw) {
    GquestPose::Snapshot pose{};
    pose.position = {x, y, z};
    pose.angle = {0.0f, yaw, 0.0f};
    return pose;
}

double HorizontalDistance(const GquestPlayspace::Pose& pose) {
    return std::sqrt(static_cast<double>(pose.position.x) * pose.position.x +
                     static_cast<double>(pose.position.z) * pose.position.z);
}

}  // namespace

int main() {
    // Frame delta: advances, refuses a step backwards or a non-finite sample, clamps a stall.
    double delta = -1;
    assert(GquestFrameDelta(1.0, 1.016, delta) && Near(delta, 0.016));
    delta = 42;
    assert(!GquestFrameDelta(2.0, 1.5, delta) && delta == 42);
    assert(!GquestFrameDelta(2.0, 2.0, delta));
    assert(!GquestFrameDelta(std::nanf(""), 2.0, delta));
    assert(!GquestFrameDelta(2.0, INFINITY, delta));
    assert(GquestFrameDelta(0.0, 3.0, delta) && Near(delta, kMaxFrameSeconds));

    // Log levels: an Error passes an Info threshold, a Trace does not.
    assert(GquestLogAtLeast(LogLevel::Error, LogLevel::Info));
    assert(GquestLogAtLeast(LogLevel::Info, LogLevel::Info));
    assert(!GquestLogAtLeast(LogLevel::Trace, LogLevel::Info));
    assert(std::strcmp(GquestLogLevelName(LogLevel::Warning), "warning") == 0);

    // Path policy: the same paths the installer refuses have to be unreadable here. Comparing
    // both keeps the two rules from drifting apart in opposite directions.
    const char* accepted[] = {"models/a.mdl", "sound/x.wav", "a"};
    for (const char* path : accepted) {
        assert(GquestAssetPathAllowed(path));
        std::vector<GquestContentEntry> entries;
        GquestManifestError error = GquestManifestError::None;
        const std::string listing = std::string("1\t") + path + "\n";
        assert(GquestParseContentManifest(listing, entries, error) && entries.size() == 1);
    }
    const char* refused[] = {"", "/etc/passwd", "a/../b", "../up", "a\rb"};
    for (const char* path : refused) {
        assert(!GquestAssetPathAllowed(path));
        std::vector<GquestContentEntry> entries;
        GquestManifestError error = GquestManifestError::None;
        const std::string listing = std::string("1\t") + path + "\n";
        assert(!GquestParseContentManifest(listing, entries, error));
    }
    assert(!GquestAssetPathAllowed(nullptr));

    // Assets: missing, oversized and refused all leave the output untouched.
    FakeAssets assets;
    assets.files["models/a.mdl"] = {1, 2, 3, 4};
    std::vector<std::uint8_t> buffer;
    assert(assets.Exists("models/a.mdl"));
    assert(!assets.Exists("models/b.mdl"));
    assert(!assets.Exists("/etc/passwd"));
    assert(!assets.Read("models/b.mdl", 64, buffer) && buffer.empty());
    buffer.assign({9, 9});
    assert(!assets.Read("models/a.mdl", 3, buffer) && buffer == std::vector<std::uint8_t>({9, 9}));
    assert(!assets.Read("../a.mdl", 64, buffer) && buffer.size() == 2);
    assert(assets.Read("models/a.mdl", 4, buffer) && buffer.size() == 4 && buffer[3] == 4);

    // Haptics: out-of-range values are refused before they reach the runtime.
    FakeVr vr;
    assert(vr.Haptic(Hand::Right, 0.1f, 160.0f, 0.5f) && vr.hapticCalls == 1);
    assert(!vr.Haptic(Hand::Right, 0.0f, 160.0f, 0.5f));
    assert(!vr.Haptic(Hand::Right, 2.5f, 160.0f, 0.5f));
    assert(!vr.Haptic(Hand::Right, 0.1f, 0.0f, 0.5f));
    assert(!vr.Haptic(Hand::Right, 0.1f, 1001.0f, 0.5f));
    assert(!vr.Haptic(Hand::Right, 0.1f, 160.0f, 1.5f));
    assert(!vr.Haptic(Hand::Right, std::nanf(""), 160.0f, 0.5f));
    assert(vr.hapticCalls == 1);

    // The frame step: after a recentre the head sits on the axis and a hand keeps its
    // distance, which is the same contract the playspace test pins without a host.
    FakeHost host;
    GquestPlayspace::State playspace{};
    assert(GquestPlayspace::Recenter(playspace, GquestPose::Vec3{10, 62, -4}, 37));

    host.vr.frameAvailable = false;
    FrameOutput none = GquestStepFrame(host, playspace);
    assert(!none.valid && host.log.HasWarning("vr frame unavailable"));

    host.vr.frameAvailable = true;
    host.vr.frame.head = Pose(10, 62, -4, 37);
    host.vr.frame.hands[0] = Pose(10, 62, 10, 37);
    host.vr.frame.handValid[0] = true;
    FrameOutput frame = GquestStepFrame(host, playspace);
    assert(frame.valid);
    assert(Near(frame.head.position.x, 0) && Near(frame.head.position.z, 0));
    assert(Near(frame.head.position.y, 62) && Near(frame.head.yaw, 0));
    assert(frame.handValid[0] && !frame.handValid[1]);
    assert(Near(HorizontalDistance(frame.hands[0]), 14));

    // A broken hand is dropped alone; the head stays usable.
    host.vr.frame.hands[1] = Pose(0, 62, 0, 0);
    host.vr.frame.hands[1].position.x = std::nanf("");
    host.vr.frame.handValid[1] = true;
    host.log.records.clear();
    FrameOutput partial = GquestStepFrame(host, playspace);
    assert(partial.valid && partial.handValid[0] && !partial.handValid[1]);
    assert(host.log.HasWarning("hand pose refused"));

    // A broken head invalidates the frame and publishes no hand poses either: hands are only
    // meaningful relative to the head they were measured against.
    host.vr.frame.head.position.z = std::nanf("");
    host.log.records.clear();
    FrameOutput broken = GquestStepFrame(host, playspace);
    assert(!broken.valid && !broken.handValid[0] && !broken.handValid[1]);
    assert(host.log.HasWarning("head pose refused"));
    assert(Near(broken.head.position.x, 0) && Near(broken.head.yaw, 0));

    std::puts("PASS platform interfaces: frame delta clamped and refuses backwards or "
              "non-finite samples, log levels ordered, asset paths refused exactly where the "
              "content installer refuses them, oversized and missing reads leave the buffer "
              "untouched, haptics bounded, and a frame step that publishes head and hands "
              "through the playspace or nothing at all");
    return 0;
}
