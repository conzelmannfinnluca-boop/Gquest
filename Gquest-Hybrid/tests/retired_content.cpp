#include <string>
#include <sys/stat.h>
#include <unistd.h>
#include <cerrno>
#include <cstdio>
#include <cassert>
#include <filesystem>
#include <fstream>
#define LOG(...) do {} while(0)
// GquestEnsureDirectory comes from gquest_content_install.h, which the retirement header
// includes. It used to be a local std::filesystem copy here, so the tested helper and the
// shipped helper were two different implementations.
#include "gquest_retired_content.h"
int main() {
    char temporary[]="/tmp/gquest-retire-test-XXXXXX";
    assert(mkdtemp(temporary));
    const std::string base=std::string(temporary)+"/", root=base+"mounted/", backup=base+"retired/";
    auto write=[](const std::string& path,const char* text) {
        assert(GquestEnsureDirectory(path.substr(0,path.find_last_of('/'))));
        std::ofstream file(path);file<<text;assert(file.good());
    };
    for (auto path:GquestRetiredArcVRPaths) write(root+path,"old private overlay");
    write(root+"lua/autorun/user_addon.lua","unrelated user file");
    assert(RetireGquestArcVR(root,backup));
    for (auto path:GquestRetiredArcVRPaths) {
        assert(!std::filesystem::exists(root+path));
        assert(std::filesystem::file_size(backup+path)==19);
    }
    assert(std::filesystem::exists(root+"lua/autorun/user_addon.lua"));
    assert(RetireGquestArcVR(root,backup)); // Repeated launch is harmless.
    const std::string first=GquestRetiredArcVRPaths[0];
    write(root+first,"installed again");
    assert(RetireGquestArcVR(root,backup));
    assert(std::filesystem::file_size(backup+first)==19);
    assert(std::filesystem::file_size(backup+first+".1")==15);
    assert(symlink((backup+first).c_str(),(root+first).c_str())==0);
    assert(!RetireGquestArcVR(root,backup)); // Never follow an unexpected link.
    assert(std::filesystem::file_size(backup+first)==19);
    std::filesystem::remove_all(base);
    puts("PASS ArcVR retirement: 63 owned files backed up, unrelated addon retained, repeated launch, backup collision and symlink guard");
}
