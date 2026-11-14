// Host tests for bridge/gquest_content_install.h.
//
// The manifest decides which files get written under the VR content root, so the rules are
// worth pinning down: an absolute path, a ".." segment, a non-numeric or wrapped size and
// an unterminated last line must all be rejected, and directory creation must refuse to
// walk into a path that is already a file.
#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include "gquest_content_install.h"

namespace {

GquestManifestError Parse(const std::string& listing, std::vector<GquestContentEntry>& entries) {
    GquestManifestError error = GquestManifestError::None;
    GquestParseContentManifest(listing, entries, error);
    return error;
}

const char* TempDirectory() {
    static char path[] = "/tmp/gquest-content-XXXXXX";
    if (mkdtemp(path) == nullptr) return nullptr;
    return path;
}

}  // namespace

int main() {
    std::vector<GquestContentEntry> entries;

    // Two well-formed entries, one nested.
    assert(Parse("12\tlua/a.lua\n345\tmodels/b.mdl\n", entries) == GquestManifestError::None);
    assert(entries.size() == 2);
    assert(entries[0].bytes == 12 && entries[0].relative == "lua/a.lua");
    assert(entries[1].bytes == 345 && entries[1].relative == "models/b.mdl");

    // An empty listing parses to nothing; the caller refuses to install in that case.
    assert(Parse("", entries) == GquestManifestError::None && entries.empty());

    assert(Parse("12 lua/a.lua\n", entries) == GquestManifestError::MissingTab);
    assert(Parse("abc\tlua/a.lua\n", entries) == GquestManifestError::BadSize);
    assert(Parse("\tlua/a.lua\n", entries) == GquestManifestError::BadSize);
    // strtoull alone would wrap this to a huge number and could compare equal to nothing -
    // but it would also then write the file. Rejected as a size error.
    assert(Parse("-5\tlua/a.lua\n", entries) == GquestManifestError::BadSize);
    assert(Parse("5.5\tlua/a.lua\n", entries) == GquestManifestError::BadSize);
    assert(Parse("99999999999999999999999\tlua/a.lua\n", entries)
           == GquestManifestError::BadSize);
    assert(Parse("12\t\n", entries) == GquestManifestError::EmptyPath);
    assert(Parse("12\t/etc/passwd\n", entries) == GquestManifestError::AbsolutePath);
    assert(Parse("12\tlua/../../escape.lua\n", entries) == GquestManifestError::ParentTraversal);
    assert(Parse("12\tlua/..\n", entries) == GquestManifestError::ParentTraversal);
    // A CRLF manifest would otherwise create a file whose name ends with a carriage return.
    assert(Parse("12\tlua/a.lua\r\n", entries) == GquestManifestError::CarriageReturn);
    // A truncated last line is not trusted.
    assert(Parse("12\tlua/a.lua", entries) == GquestManifestError::UnterminatedLine);

    // The first good line is kept, but the caller must not use it: the error is fatal.
    assert(Parse("12\tlua/a.lua\n13\tbad", entries) == GquestManifestError::UnterminatedLine);
    assert(entries.size() == 1);

    for (GquestManifestError error : {GquestManifestError::None, GquestManifestError::BadSize,
                                      GquestManifestError::ParentTraversal})
        assert(std::strcmp(GquestManifestErrorText(error), "ok") != 0 ||
               error == GquestManifestError::None);

    const char* root = TempDirectory();
    assert(root);
    const std::string base(root);

    // Nested creation, then the same call again: it has to be idempotent.
    assert(GquestEnsureDirectory(base + "/vr_content/lua/autorun"));
    assert(GquestEnsureDirectory(base + "/vr_content/lua/autorun"));
    struct stat st{};
    assert(stat((base + "/vr_content/lua/autorun").c_str(), &st) == 0 && S_ISDIR(st.st_mode));
    // A trailing slash means the same directory.
    assert(GquestEnsureDirectory(base + "/vr_content/"));

    // Refuse to continue when a component is a regular file, not a directory.
    const std::string blocker = base + "/blocked";
    FILE* file = std::fopen(blocker.c_str(), "wb");
    assert(file);
    std::fclose(file);
    assert(!GquestEnsureDirectory(blocker + "/below"));

    // A relative path must not be created in the process working directory. (Before this
    // was refused, the call succeeded and created ./relative next to the working copy.)
    assert(!GquestEnsureDirectory("relative/dir"));
    assert(!GquestEnsureDirectory(""));

    const std::string cleanup = "rm -rf " + base;
    assert(std::system(cleanup.c_str()) == 0);

    std::puts("PASS content install: manifest rejects absolute paths, .. segments, non-numeric "
              "and overflowing sizes, empty paths and CRLF; directory creation is idempotent "
              "and refuses to descend into a file");
    return 0;
}
