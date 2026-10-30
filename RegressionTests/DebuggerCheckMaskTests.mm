#include "../SovietExtension/SovietExtension/DebuggerCheckMask.h"
#include <libkern/OSCacheControl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>

static void Check(bool condition, const char *message) {
    if (!condition) {
        std::fprintf(stderr, "FAIL %s\n", message);
        std::exit(1);
    }
}

int main(int argc, char **argv) {
    using namespace ym::debugger;
    Check(argc >= 2, "expected supported arm64 image path");
    std::ifstream image(argv[1], std::ios::binary);
    Check(image.good(), "image is readable");
    std::array<std::uint32_t, 8> entry{};
    image.seekg(kCheckAddress);
    image.read(reinterpret_cast<char *>(entry.data()), sizeof(entry));
    Check(image.good() && MatchesOriginalEntry(entry), "exact image entry fingerprint");
    for (std::size_t index = 0; index < entry.size(); ++index) {
        auto changed = entry;
        changed[index] ^= 1;
        Check(!MatchesOriginalEntry(changed), "modified entry must be rejected");
    }

#if defined(__arm64__)
    constexpr std::size_t functionSize = 0xe4;
    constexpr std::size_t guardPointerAddress = 0x8acebc8;
    constexpr std::size_t cacheAddress = 0x9144f88;
    const auto pageSize = static_cast<std::size_t>(getpagesize());
    const auto pageStart = [pageSize](std::size_t address) {
        return address & ~(pageSize - 1);
    };
    const std::size_t mappingSize = pageStart(cacheAddress) + pageSize;
    auto *mapping = static_cast<unsigned char *>(mmap(nullptr, mappingSize,
        PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0));
    Check(mapping != MAP_FAILED, "reserve isolated address-space fixture");
    for (std::size_t address : {kCheckAddress, guardPointerAddress, cacheAddress}) {
        Check(mprotect(mapping + pageStart(address), pageSize,
                       PROT_READ | PROT_WRITE) == 0, "prepare fixture page");
    }
    image.seekg(kCheckAddress);
    image.read(reinterpret_cast<char *>(mapping + kCheckAddress), functionSize);
    Check(image.good(), "read complete original function");
    std::uint64_t guard = 0x12345678;
    auto *guardPointer = &guard;
    std::memcpy(mapping + guardPointerAddress, &guardPointer, sizeof(guardPointer));
    mapping[cacheAddress] = 1;
    mapping[cacheAddress + 1] = 1;
    auto *codePage = mapping + pageStart(kCheckAddress);
    const auto executable = [&] {
        sys_icache_invalidate(mapping + kCheckAddress, functionSize);
        Check(mprotect(codePage, pageSize, PROT_READ | PROT_EXEC) == 0,
              "make fixture code executable");
    };
    auto checkDebugger = reinterpret_cast<unsigned (*)()>(mapping + kCheckAddress);
    executable();
    Check(checkDebugger() == 1, "unmodified host function reports cached debugger=true");
    if (argc == 3 && std::strcmp(argv[2], "--baseline") == 0) {
        const unsigned observed = checkDebugger();
        Check(munmap(mapping, mappingSize) == 0, "release baseline fixture");
        std::printf("BASELINE unmasked_debugger_result=%u\n", observed);
        return observed == 0 ? 0 : 1;
    }
    Check(mprotect(codePage, pageSize, PROT_READ | PROT_WRITE) == 0,
          "prepare fixture mask write");
    std::memcpy(mapping + kCheckAddress, kMaskedEntry.data(), sizeof(kMaskedEntry));
    executable();
    Check(checkDebugger() == 0, "masked host function reports debugger=false");
    Check(mapping[cacheAddress + 1] == 1, "mask does not overwrite host cache data");
    Check(mprotect(codePage, pageSize, PROT_READ | PROT_WRITE) == 0,
          "prepare fixture original-code reload");
    std::memcpy(mapping + kCheckAddress, entry.data(), sizeof(kMaskedEntry));
    executable();
    Check(checkDebugger() == 1, "original-code reload restores debugger detection");
    Check(munmap(mapping, mappingSize) == 0, "release isolated fixture");
    std::puts("PASS DebuggerCheckMaskTests native_original=1 masked=0 restored=1 fingerprint_guard=true");
#else
    std::puts("PASS DebuggerCheckMaskTests fingerprint_guard=true native_execution=unsupported_arch");
#endif
    return 0;
}
