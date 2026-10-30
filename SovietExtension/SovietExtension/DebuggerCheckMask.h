#pragma once

#include <array>
#include <cstdint>

namespace ym::debugger {

// arm64 Build 269079 的镜像相对地址；调用方还须核对 Build、UUID 和完整入口指纹。
inline constexpr std::uintptr_t kCheckAddress = 0x2471c;
inline constexpr std::array<std::uint32_t, 8> kOriginalEntry = {
    0xa9bd57f6, 0xa9014ff4, 0xa9027bfd, 0x910083fd,
    0xd10ac3ff, 0xd0045548, 0xf945e508, 0xf9400108,
};
inline constexpr std::array<std::uint32_t, 2> kMaskedEntry = {
    0x52800000, // mov w0, #0
    0xd65f03c0, // ret
};

inline bool MatchesOriginalEntry(
    const std::array<std::uint32_t, 8> &entry) noexcept {
    return entry == kOriginalEntry;
}

} // namespace ym::debugger
