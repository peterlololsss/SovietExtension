//
//  LiquidGlassIdentity.hpp
//  SovietExtension
//
//  组件级液态玻璃的目标身份校验：只认 WeChat 4.1.11 / 269079 / arm64。
//
//  目标 SHA-256 是 arm64 切片的哈希。安装包里的 wechat.dylib 是 x86_64 + arm64
//  的 fat 文件，对整个文件求哈希永远对不上，所以这里先按 fat 头找到 arm64 切片，
//  再只对切片字节求哈希。
//

#pragma once

#include <CommonCrypto/CommonDigest.h>
#include <libkern/OSByteOrder.h>
#include <mach-o/fat.h>
#include <mach-o/loader.h>
#include <mach/machine.h>

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include <algorithm>
#include <array>
#include <cerrno>
#include <cstdint>
#include <cstring>
#include <vector>

namespace ym::liquid_glass {

using Digest = std::array<std::uint8_t, CC_SHA256_DIGEST_LENGTH>;
using UUID = std::array<std::uint8_t, 16>;

inline constexpr const char *kBundleIdentifier = "com.tencent.xinWeChat";
inline constexpr const char *kShortVersion = "4.1.11";
inline constexpr const char *kBuildVersion = "269079";

// analysis/sidebar-wechat-4.1.11/wechat-arm64.dylib
inline constexpr Digest kArm64SliceSHA256 = {
    0x48, 0x0f, 0x5b, 0xd4, 0xc3, 0x60, 0xc9, 0x23,
    0x15, 0xdd, 0x26, 0x88, 0xaa, 0xe9, 0xfd, 0xfa,
    0x46, 0x4d, 0xe6, 0xdd, 0x52, 0xeb, 0x3a, 0xed,
    0x59, 0xa9, 0x77, 0x6d, 0xce, 0x1a, 0x12, 0x6c,
};

// 580294A4-5AF5-310D-9A9A-C3639BEE0A28
inline constexpr UUID kArm64SliceUUID = {
    0x58, 0x02, 0x94, 0xa4, 0x5a, 0xf5, 0x31, 0x0d,
    0x9a, 0x9a, 0xc3, 0x63, 0x9b, 0xee, 0x0a, 0x28,
};

struct SliceRange {
    std::uint64_t offset = 0;
    std::uint64_t size = 0;
};

// 在 fat 或单架构 Mach-O 文件里找唯一的 CPU_TYPE_ARM64 切片。
// 没有、重复、越界都返回 false。
inline bool FindArm64Slice(int fd, std::uint64_t fileSize, SliceRange &out) {
    std::uint8_t head[8] = {};
    if (fileSize < sizeof(head) ||
        pread(fd, head, sizeof(head), 0) != static_cast<ssize_t>(sizeof(head))) {
        return false;
    }

    const std::uint32_t magic = OSReadBigInt32(head, 0);
    if (magic == FAT_MAGIC || magic == FAT_MAGIC_64) {
        const bool wide = magic == FAT_MAGIC_64;
        const std::uint32_t count = OSReadBigInt32(head, 4);
        if (count == 0 || count > 32) {
            return false;
        }
        const std::size_t entrySize = wide ? sizeof(fat_arch_64) : sizeof(fat_arch);
        bool found = false;
        for (std::uint32_t index = 0; index < count; ++index) {
            std::uint8_t entry[sizeof(fat_arch_64)] = {};
            const off_t at = static_cast<off_t>(sizeof(head) + index * entrySize);
            if (pread(fd, entry, entrySize, at) != static_cast<ssize_t>(entrySize)) {
                return false;
            }
            if (static_cast<cpu_type_t>(OSReadBigInt32(entry, 0)) != CPU_TYPE_ARM64) {
                continue;
            }
            const std::uint64_t offset =
                wide ? OSReadBigInt64(entry, 8) : OSReadBigInt32(entry, 8);
            const std::uint64_t size =
                wide ? OSReadBigInt64(entry, 16) : OSReadBigInt32(entry, 12);
            if (found || size == 0 || offset > fileSize || size > fileSize - offset) {
                return false;
            }
            out = {offset, size};
            found = true;
        }
        return found;
    }

    if (OSReadLittleInt32(head, 0) == MH_MAGIC_64 &&
        static_cast<cpu_type_t>(OSReadLittleInt32(head, 4)) == CPU_TYPE_ARM64) {
        out = {0, fileSize};
        return true;
    }
    return false;
}

// 对 path 的 arm64 切片流式求 SHA-256。
inline bool Arm64SliceDigest(const char *path, Digest &digest) {
    const int fd = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (fd < 0) {
        return false;
    }
    struct stat info = {};
    SliceRange range;
    bool ok = fstat(fd, &info) == 0 && S_ISREG(info.st_mode) && info.st_size > 0 &&
              FindArm64Slice(fd, static_cast<std::uint64_t>(info.st_size), range);
    if (ok) {
        CC_SHA256_CTX context;
        CC_SHA256_Init(&context);
        std::vector<std::uint8_t> buffer(1 << 20);
        std::uint64_t done = 0;
        while (done < range.size) {
            const std::size_t want = static_cast<std::size_t>(
                std::min<std::uint64_t>(buffer.size(), range.size - done));
            const ssize_t got =
                pread(fd, buffer.data(), want, static_cast<off_t>(range.offset + done));
            if (got < 0 && errno == EINTR) {
                continue;
            }
            if (got <= 0) {
                ok = false;
                break;
            }
            CC_SHA256_Update(&context, buffer.data(), static_cast<CC_LONG>(got));
            done += static_cast<std::uint64_t>(got);
        }
        if (ok) {
            CC_SHA256_Final(digest.data(), &context);
        }
    }
    close(fd);
    return ok;
}

// 读取 dyld 已经映射的镜像的 LC_UUID。
inline bool LoadedImageUUID(const mach_header_64 *header, UUID &uuid) {
    if (header == nullptr || header->magic != MH_MAGIC_64) {
        return false;
    }
    const auto *cursor = reinterpret_cast<const std::uint8_t *>(header + 1);
    std::uint32_t consumed = 0;
    for (std::uint32_t index = 0; index < header->ncmds; ++index) {
        const auto *command = reinterpret_cast<const load_command *>(cursor);
        if (command->cmdsize < sizeof(load_command) ||
            command->cmdsize > header->sizeofcmds - consumed) {
            return false;
        }
        if (command->cmd == LC_UUID && command->cmdsize >= sizeof(uuid_command)) {
            std::memcpy(uuid.data(),
                        reinterpret_cast<const uuid_command *>(command)->uuid,
                        uuid.size());
            return true;
        }
        consumed += command->cmdsize;
        cursor += command->cmdsize;
    }
    return false;
}

}  // namespace ym::liquid_glass
