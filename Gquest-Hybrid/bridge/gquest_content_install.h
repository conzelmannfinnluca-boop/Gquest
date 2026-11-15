// VR content installation: directory creation and validation of the shipped file list.
//
// Split out of the bridge so the rules that decide whether a manifest line is acceptable
// can run on a host. They carry weight: the listing chooses which files are written under
// the content root, so a line with an absolute path, a ".." segment or a bogus size has to
// abort the installation instead of being skipped or written somewhere else.
#pragma once
#include <sys/stat.h>
#include <cerrno>
#include <cstdlib>
#include <string>
#include <vector>

struct GquestContentEntry {
    unsigned long long bytes = 0;
    std::string relative;
};

enum class GquestManifestError {
    None,
    UnterminatedLine,
    MissingTab,
    BadSize,
    EmptyPath,
    AbsolutePath,
    ParentTraversal,
    CarriageReturn,
};

inline const char* GquestManifestErrorText(GquestManifestError error) {
    switch (error) {
        case GquestManifestError::None: return "ok";
        case GquestManifestError::UnterminatedLine: return "last line has no newline";
        case GquestManifestError::MissingTab: return "missing tab between size and path";
        case GquestManifestError::BadSize: return "size is not a plain decimal number";
        case GquestManifestError::EmptyPath: return "empty path";
        case GquestManifestError::AbsolutePath: return "absolute path";
        case GquestManifestError::ParentTraversal: return "path contains ..";
        case GquestManifestError::CarriageReturn: return "path contains a carriage return";
    }
    return "unknown";
}

// Every entry is "<size>\t<relative path>\n". Parsing stops at the first bad line; the
// caller has to treat any error as fatal, because the remaining entries are unverified.
//
// The size must be plain digits: std::strtoull alone also accepts "-5" (wrapping it to a
// huge value) and silently saturates on overflow, so both are rejected here rather than
// compared against a file size that can never match.
inline bool GquestParseContentManifest(const std::string& listing,
                                      std::vector<GquestContentEntry>& entries,
                                      GquestManifestError& error) {
    entries.clear();
    error = GquestManifestError::None;
    size_t position = 0;
    while (position < listing.size()) {
        const size_t end = listing.find('\n', position);
        if (end == std::string::npos) {
            error = GquestManifestError::UnterminatedLine;
            return false;
        }
        const std::string line = listing.substr(position, end - position);
        position = end + 1;
        const size_t tab = line.find('\t');
        if (tab == std::string::npos) {
            error = GquestManifestError::MissingTab;
            return false;
        }
        bool digits = tab > 0 && tab <= 20;
        for (size_t i = 0; i < tab && digits; ++i)
            digits = line[i] >= '0' && line[i] <= '9';
        if (!digits) {
            error = GquestManifestError::BadSize;
            return false;
        }
        const unsigned long long bytes = std::strtoull(line.c_str(), nullptr, 10);
        const std::string relative = line.substr(tab + 1);
        if (relative.empty()) {
            error = GquestManifestError::EmptyPath;
            return false;
        }
        if (relative[0] == '/') {
            error = GquestManifestError::AbsolutePath;
            return false;
        }
        if (relative.find("..") != std::string::npos) {
            error = GquestManifestError::ParentTraversal;
            return false;
        }
        if (relative.find('\r') != std::string::npos) {
            error = GquestManifestError::CarriageReturn;
            return false;
        }
        GquestContentEntry entry;
        entry.bytes = bytes;
        entry.relative = relative;
        entries.push_back(entry);
    }
    return true;
}

// mkdir -p for an absolute path, 0700. Relative paths are refused outright: a relative
// path would silently create directories in the process working directory, which on the
// device is not where any caller means to write. Every caller passes a path below the
// app's own data directory.
inline bool GquestEnsureDirectory(const std::string& path) {
    if (path.empty() || path[0] != '/') return false;
    for (size_t i = 1; i <= path.size(); ++i) {
        if (i != path.size() && path[i] != '/') continue;
        const std::string dir = path.substr(0, i);
        if (mkdir(dir.c_str(), 0700) != 0 && errno != EEXIST) return false;
        struct stat st{};
        if (stat(dir.c_str(), &st) != 0 || !S_ISDIR(st.st_mode)) return false;
    }
    return true;
}
