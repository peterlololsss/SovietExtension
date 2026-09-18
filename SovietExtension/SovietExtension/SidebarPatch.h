#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <optional>
#include <utility>
#include <cstdio>
#include <cstring>
#include <functional>
#include <memory>

// ---- SidebarPatchTransaction -----------------------------------

namespace ym::sidebar::patch {

inline constexpr std::size_t kNoStage = std::numeric_limits<std::size_t>::max();

struct TrampolineMapping {
    std::uintptr_t address = 0;
    std::size_t size = 0;
};

enum class InstallError : std::uint8_t {
    none,
    invalidOperations,
    preflightMismatch,
    quiescenceFailure,
    allocationFailure,
    writeFailure
};

enum class RollbackError : std::uint8_t {
    none,
    restoreFailure,
    releaseFailure
};

enum class QuiescenceError : std::uint8_t {
    none,
    invalidOperations,
    releaseFailure
};

enum class UninstallError : std::uint8_t {
    none,
    invalidOperations,
    quiescenceFailure,
    restoreFailure,
    partialRestoreFailure,
    releaseFailure,
    partialReleaseFailure
};

struct Operations {
    void *context = nullptr;
    bool (*preflight)(void *, std::size_t) noexcept = nullptr;
    bool (*acquireQuiescence)(void *) noexcept = nullptr;
    bool (*releaseQuiescence)(void *) noexcept = nullptr;
    bool (*allocateTrampoline)(void *, std::size_t, TrampolineMapping *)
        noexcept = nullptr;
    bool (*releaseTrampoline)(void *, std::size_t, TrampolineMapping)
        noexcept = nullptr;
    bool (*writePatch)(void *, std::size_t, TrampolineMapping) noexcept = nullptr;
    bool (*restoreTarget)(void *, std::size_t) noexcept = nullptr;
};

template <std::size_t StageCount> class InstalledPatches;
template <std::size_t StageCount> class InstallResult;
class UninstallResult;

template <std::size_t StageCount>
[[nodiscard]] InstallResult<StageCount> Install(const Operations &) noexcept;

template <std::size_t StageCount>
[[nodiscard]] UninstallResult Uninstall(
    InstalledPatches<StageCount> &, const Operations &) noexcept;

template <std::size_t StageCount>
[[nodiscard]] QuiescenceError RetryQuiescence(
    InstalledPatches<StageCount> &, const Operations &) noexcept;

template <std::size_t StageCount>
class InstalledPatches {
public:
    InstalledPatches(const InstalledPatches &) = delete;
    InstalledPatches &operator=(const InstalledPatches &) = delete;
    InstalledPatches &operator=(InstalledPatches &&) = delete;

    InstalledPatches(InstalledPatches &&other) noexcept
        : mappings_(other.mappings_),
          active_(other.active_),
          needsRestore_(other.needsRestore_),
          remaining_(std::exchange(other.remaining_, 0)),
          quiescencePending_(
              std::exchange(other.quiescencePending_, false)) {
        other.active_.fill(false);
        other.needsRestore_.fill(false);
    }

    [[nodiscard]] std::size_t remainingCount() const noexcept { return remaining_; }

    [[nodiscard]] bool hasPendingQuiescence() const noexcept {
        return quiescencePending_;
    }

    [[nodiscard]] bool hasOwnership() const noexcept {
        return remaining_ != 0 || quiescencePending_;
    }

    [[nodiscard]] bool isActive(std::size_t stage) const noexcept {
        return stage < StageCount && active_[stage];
    }

private:
    explicit InstalledPatches(
        std::array<TrampolineMapping, StageCount> mappings,
        bool quiescencePending = false) noexcept
        : mappings_(std::move(mappings)),
          remaining_(StageCount),
          quiescencePending_(quiescencePending) {
        active_.fill(true);
        needsRestore_.fill(true);
    }

    InstalledPatches(std::array<TrampolineMapping, StageCount> mappings,
                     std::array<bool, StageCount> active,
                     std::array<bool, StageCount> needsRestore,
                     std::size_t remaining,
                     bool quiescencePending = false) noexcept
        : mappings_(std::move(mappings)),
          active_(std::move(active)),
          needsRestore_(std::move(needsRestore)),
          remaining_(remaining),
          quiescencePending_(quiescencePending) {}

    std::array<TrampolineMapping, StageCount> mappings_{};
    std::array<bool, StageCount> active_{};
    std::array<bool, StageCount> needsRestore_{};
    std::size_t remaining_ = 0;
    bool quiescencePending_ = false;

    friend InstallResult<StageCount> Install<StageCount>(const Operations &)
        noexcept;
    friend UninstallResult Uninstall<StageCount>(
        InstalledPatches &, const Operations &) noexcept;
    friend QuiescenceError RetryQuiescence<StageCount>(
        InstalledPatches &, const Operations &) noexcept;
};

template <std::size_t StageCount>
class InstallResult {
public:
    InstallResult(const InstallResult &) = delete;
    InstallResult &operator=(const InstallResult &) = delete;
    InstallResult(InstallResult &&) noexcept = default;
    InstallResult &operator=(InstallResult &&) = delete;

    [[nodiscard]] bool succeeded() const noexcept {
        return error_ == InstallError::none &&
               rollbackError_ == RollbackError::none &&
               quiescenceError() == QuiescenceError::none &&
               installed_.has_value() &&
               installed_->remainingCount() == StageCount;
    }

    [[nodiscard]] InstallError error() const noexcept { return error_; }
    [[nodiscard]] RollbackError rollbackError() const noexcept {
        return rollbackError_;
    }
    [[nodiscard]] QuiescenceError quiescenceError() const noexcept {
        if (quiescenceError_ == QuiescenceError::releaseFailure &&
            installed_.has_value() &&
            !installed_->hasPendingQuiescence()) {
            return QuiescenceError::none;
        }
        return quiescenceError_;
    }
    [[nodiscard]] std::size_t failedStage() const noexcept { return failedStage_; }
    [[nodiscard]] std::size_t rollbackFailedStage() const noexcept {
        return rollbackFailedStage_;
    }
    [[nodiscard]] InstalledPatches<StageCount> *installed() noexcept {
        return installed_ ? &*installed_ : nullptr;
    }
    [[nodiscard]] const InstalledPatches<StageCount> *installed() const noexcept {
        return installed_ ? &*installed_ : nullptr;
    }

private:
    explicit InstallResult(
        InstalledPatches<StageCount> installed,
        QuiescenceError quiescenceError = QuiescenceError::none) noexcept
        : quiescenceError_(quiescenceError),
          installed_(std::move(installed)) {}

    InstallResult(InstallError error,
                  std::size_t failedStage,
                  RollbackError rollbackError = RollbackError::none,
                  std::size_t rollbackFailedStage = kNoStage,
                  QuiescenceError quiescenceError =
                      QuiescenceError::none) noexcept
        : error_(error),
          rollbackError_(rollbackError),
          quiescenceError_(quiescenceError),
          failedStage_(failedStage),
          rollbackFailedStage_(rollbackFailedStage) {}

    InstallResult(InstallError error,
                  std::size_t failedStage,
                  RollbackError rollbackError,
                  std::size_t rollbackFailedStage,
                  QuiescenceError quiescenceError,
                  InstalledPatches<StageCount> residual) noexcept
        : error_(error),
          rollbackError_(rollbackError),
          quiescenceError_(quiescenceError),
          failedStage_(failedStage),
          rollbackFailedStage_(rollbackFailedStage),
          installed_(std::move(residual)) {}

    InstallError error_ = InstallError::none;
    RollbackError rollbackError_ = RollbackError::none;
    QuiescenceError quiescenceError_ = QuiescenceError::none;
    std::size_t failedStage_ = kNoStage;
    std::size_t rollbackFailedStage_ = kNoStage;
    std::optional<InstalledPatches<StageCount>> installed_;

    friend InstallResult Install<StageCount>(const Operations &) noexcept;
};

class UninstallResult {
public:
    [[nodiscard]] bool succeeded() const noexcept {
        return error_ == UninstallError::none &&
               quiescenceError_ == QuiescenceError::none &&
               remainingCount_ == 0 && !quiescencePending_;
    }
    [[nodiscard]] UninstallError error() const noexcept { return error_; }
    [[nodiscard]] QuiescenceError quiescenceError() const noexcept {
        return quiescenceError_;
    }
    [[nodiscard]] std::size_t failedStage() const noexcept { return failedStage_; }
    [[nodiscard]] std::size_t restoredCount() const noexcept {
        return restoredCount_;
    }
    [[nodiscard]] std::size_t remainingCount() const noexcept {
        return remainingCount_;
    }
    [[nodiscard]] bool hasPendingQuiescence() const noexcept {
        return quiescencePending_;
    }

private:
    UninstallResult(UninstallError error,
                    QuiescenceError quiescenceError,
                    std::size_t failedStage,
                    std::size_t restoredCount,
                    std::size_t remainingCount,
                    bool quiescencePending) noexcept
        : error_(error),
          quiescenceError_(quiescenceError),
          failedStage_(failedStage),
          restoredCount_(restoredCount),
          remainingCount_(remainingCount),
          quiescencePending_(quiescencePending) {}

    UninstallError error_ = UninstallError::none;
    QuiescenceError quiescenceError_ = QuiescenceError::none;
    std::size_t failedStage_ = kNoStage;
    std::size_t restoredCount_ = 0;
    std::size_t remainingCount_ = 0;
    bool quiescencePending_ = false;

    template <std::size_t StageCount>
    friend UninstallResult Uninstall(InstalledPatches<StageCount> &,
                                     const Operations &) noexcept;
};

namespace detail {

inline bool HasInstallCallbacks(const Operations &operations) noexcept {
    return operations.preflight && operations.acquireQuiescence &&
           operations.releaseQuiescence && operations.allocateTrampoline &&
           operations.releaseTrampoline && operations.writePatch &&
           operations.restoreTarget;
}

inline bool HasUninstallCallbacks(const Operations &operations) noexcept {
    return operations.acquireQuiescence && operations.releaseQuiescence &&
           operations.releaseTrampoline && operations.restoreTarget;
}

}

template <std::size_t StageCount>
QuiescenceError RetryQuiescence(
    InstalledPatches<StageCount> &installed,
    const Operations &operations) noexcept {
    if (!installed.quiescencePending_) {
        return QuiescenceError::none;
    }
    if (!operations.releaseQuiescence) {
        return QuiescenceError::invalidOperations;
    }
    if (!operations.releaseQuiescence(operations.context)) {
        return QuiescenceError::releaseFailure;
    }
    installed.quiescencePending_ = false;
    return QuiescenceError::none;
}

template <std::size_t StageCount>
InstallResult<StageCount> Install(const Operations &operations) noexcept {
    if constexpr (StageCount == 0) {
        return InstallResult<StageCount>(InstalledPatches<StageCount>({}));
    }
    if (!detail::HasInstallCallbacks(operations)) {
        return {InstallError::invalidOperations, kNoStage};
    }
    for (std::size_t stage = 0; stage < StageCount; ++stage) {
        if (!operations.preflight(operations.context, stage)) {
            return {InstallError::preflightMismatch, stage};
        }
    }
    if (!operations.acquireQuiescence(operations.context)) {
        const bool quiescencePending =
            !operations.releaseQuiescence(operations.context);
        if (quiescencePending) {
            return InstallResult<StageCount>(
                InstallError::quiescenceFailure, kNoStage,
                RollbackError::none, kNoStage,
                QuiescenceError::releaseFailure,
                InstalledPatches<StageCount>(
                    {}, {}, {}, 0, true));
        }
        return {InstallError::quiescenceFailure, kNoStage};
    }
    for (std::size_t stage = 0; stage < StageCount; ++stage) {
        if (!operations.preflight(operations.context, stage)) {
            const bool quiescencePending =
                !operations.releaseQuiescence(operations.context);
            if (quiescencePending) {
                return InstallResult<StageCount>(
                    InstallError::preflightMismatch, stage,
                    RollbackError::none, kNoStage,
                    QuiescenceError::releaseFailure,
                    InstalledPatches<StageCount>(
                        {}, {}, {}, 0, true));
            }
            return {InstallError::preflightMismatch, stage};
        }
    }

    std::array<TrampolineMapping, StageCount> mappings{};
    std::array<bool, StageCount> active{};
    std::array<bool, StageCount> needsRestore{};
    std::size_t allocatedCount = 0;
    for (std::size_t stage = 0; stage < StageCount; ++stage) {
        if (!operations.allocateTrampoline(
                operations.context, stage, &mappings[stage])) {
            std::size_t releaseFailedStage = kNoStage;
            for (std::size_t cursor = allocatedCount; cursor > 0; --cursor) {
                const std::size_t releaseStage = cursor - 1;
                if (!operations.releaseTrampoline(
                        operations.context, releaseStage, mappings[releaseStage])) {
                    if (releaseFailedStage == kNoStage) {
                        releaseFailedStage = releaseStage;
                    }
                    active[releaseStage] = true;
                } else {
                    active[releaseStage] = false;
                }
            }
            const bool quiescencePending =
                !operations.releaseQuiescence(operations.context);
            std::size_t remaining = 0;
            for (bool isActive : active) {
                remaining += isActive ? 1u : 0u;
            }
            const RollbackError rollbackError =
                releaseFailedStage == kNoStage
                    ? RollbackError::none
                    : RollbackError::releaseFailure;
            const QuiescenceError quiescenceError =
                quiescencePending ? QuiescenceError::releaseFailure
                                  : QuiescenceError::none;
            if (remaining != 0 || quiescencePending) {
                return InstallResult<StageCount>(
                    InstallError::allocationFailure, stage,
                    rollbackError, releaseFailedStage, quiescenceError,
                    InstalledPatches<StageCount>(
                        std::move(mappings), std::move(active),
                        std::move(needsRestore), remaining,
                        quiescencePending));
            }
            return {InstallError::allocationFailure, stage,
                    rollbackError, releaseFailedStage,
                    quiescenceError};
        }
        active[stage] = true;
        ++allocatedCount;
    }

    for (std::size_t stage = 0; stage < StageCount; ++stage) {
        if (operations.writePatch(
                operations.context, stage, mappings[stage])) {
            needsRestore[stage] = true;
            continue;
        }

        for (std::size_t attempted = 0; attempted <= stage; ++attempted) {
            needsRestore[attempted] = true;
        }
        std::size_t restoreFailedStage = kNoStage;
        for (std::size_t cursor = stage + 1; cursor > 0; --cursor) {
            const std::size_t restoreStage = cursor - 1;
            if (operations.restoreTarget(operations.context, restoreStage)) {
                needsRestore[restoreStage] = false;
            } else if (restoreFailedStage == kNoStage) {
                restoreFailedStage = restoreStage;
            }
        }

        std::size_t releaseFailedStage = kNoStage;
        for (std::size_t cursor = StageCount; cursor > 0; --cursor) {
            const std::size_t releaseStage = cursor - 1;
            if (!needsRestore[releaseStage] &&
                !operations.releaseTrampoline(
                    operations.context, releaseStage, mappings[releaseStage])) {
                if (releaseFailedStage == kNoStage) {
                    releaseFailedStage = releaseStage;
                }
                active[releaseStage] = true;
            } else if (!needsRestore[releaseStage]) {
                active[releaseStage] = false;
            }
        }

        const auto rollbackError = restoreFailedStage != kNoStage
                                       ? RollbackError::restoreFailure
                                       : releaseFailedStage == kNoStage
                                             ? RollbackError::none
                                             : RollbackError::releaseFailure;
        const std::size_t rollbackStage = restoreFailedStage != kNoStage
                                              ? restoreFailedStage
                                              : releaseFailedStage;
        std::size_t remaining = 0;
        for (bool isActive : active) {
            remaining += isActive ? 1u : 0u;
        }
        const bool quiescencePending =
            !operations.releaseQuiescence(operations.context);
        const QuiescenceError quiescenceError =
            quiescencePending ? QuiescenceError::releaseFailure
                              : QuiescenceError::none;
        if (remaining != 0 || quiescencePending) {
            return InstallResult<StageCount>(
                InstallError::writeFailure, stage, rollbackError, rollbackStage,
                quiescenceError,
                InstalledPatches<StageCount>(
                    std::move(mappings), std::move(active),
                    std::move(needsRestore), remaining,
                    quiescencePending));
        }
        return {InstallError::writeFailure, stage, rollbackError,
                rollbackStage, quiescenceError};
    }

    const bool quiescencePending =
        !operations.releaseQuiescence(operations.context);
    const QuiescenceError quiescenceError =
        quiescencePending ? QuiescenceError::releaseFailure
                          : QuiescenceError::none;
    return InstallResult<StageCount>(
        InstalledPatches<StageCount>(
            std::move(mappings), quiescencePending),
        quiescenceError);
}

template <std::size_t StageCount>
UninstallResult Uninstall(InstalledPatches<StageCount> &installed,
                          const Operations &operations) noexcept {
    if (!installed.hasOwnership()) {
        return {UninstallError::none, QuiescenceError::none,
                kNoStage, 0, 0, false};
    }
    if (installed.quiescencePending_) {
        const QuiescenceError retryError =
            RetryQuiescence(installed, operations);
        if (retryError != QuiescenceError::none) {
            const UninstallError error =
                retryError == QuiescenceError::invalidOperations
                    ? UninstallError::invalidOperations
                    : UninstallError::none;
            return {error, retryError, kNoStage, 0,
                    installed.remaining_, true};
        }
        if (installed.remaining_ == 0) {
            return {UninstallError::none, QuiescenceError::none,
                    kNoStage, 0, 0, false};
        }
    }
    if (!detail::HasUninstallCallbacks(operations)) {
        return {UninstallError::invalidOperations,
                QuiescenceError::none, kNoStage, 0,
                installed.remaining_, false};
    }
    if (!operations.acquireQuiescence(operations.context)) {
        installed.quiescencePending_ =
            !operations.releaseQuiescence(operations.context);
        const QuiescenceError quiescenceError =
            installed.quiescencePending_
                ? QuiescenceError::releaseFailure
                : QuiescenceError::none;
        return {UninstallError::quiescenceFailure, quiescenceError,
                kNoStage, 0, installed.remaining_,
                installed.quiescencePending_};
    }
    std::size_t failedStage = kNoStage;
    std::size_t restoreFailedStage = kNoStage;
    std::size_t releaseFailedStage = kNoStage;
    std::size_t restoredCount = 0;
    for (std::size_t cursor = StageCount; cursor > 0; --cursor) {
        const std::size_t stage = cursor - 1;
        if (!installed.active_[stage]) {
            continue;
        }
        if (installed.needsRestore_[stage]) {
            if (!operations.restoreTarget(operations.context, stage)) {
                if (failedStage == kNoStage) {
                    failedStage = stage;
                }
                if (restoreFailedStage == kNoStage) {
                    restoreFailedStage = stage;
                }
                continue;
            }
            installed.needsRestore_[stage] = false;
        }
        if (!operations.releaseTrampoline(
                operations.context, stage, installed.mappings_[stage])) {
            if (failedStage == kNoStage) {
                failedStage = stage;
            }
            if (releaseFailedStage == kNoStage) {
                releaseFailedStage = stage;
            }
            continue;
        }
        installed.active_[stage] = false;
        --installed.remaining_;
        ++restoredCount;
    }

    installed.quiescencePending_ =
        !operations.releaseQuiescence(operations.context);
    const QuiescenceError quiescenceError =
        installed.quiescencePending_
            ? QuiescenceError::releaseFailure
            : QuiescenceError::none;
    UninstallError error = UninstallError::none;
    if (failedStage != kNoStage) {
        error = restoreFailedStage != kNoStage
                    ? (restoredCount == 0
                           ? UninstallError::restoreFailure
                           : UninstallError::partialRestoreFailure)
                    : releaseFailedStage != kNoStage
                          ? (restoredCount == 0
                                 ? UninstallError::releaseFailure
                                 : UninstallError::partialReleaseFailure)
                          : UninstallError::none;
    }
    return {error, quiescenceError, failedStage, restoredCount,
            installed.remaining_, installed.quiescencePending_};
}

}

// ---- SidebarManagerPatchState ----------------------------------

namespace ym::sidebar::manager_patch {

enum class InstallDisposition : std::uint8_t {
    installed,
    pendingActivation,
    cleanupPending,
    failed,
    busy,
};

enum class OwnershipStatus : std::uint8_t {
    ready,
    active,
    pendingActivation,
    cleanupPending,
};

struct InstallOutcome {
    InstallDisposition disposition{InstallDisposition::failed};
    patch::InstallError error{patch::InstallError::none};
    patch::RollbackError rollbackError{patch::RollbackError::none};
    patch::QuiescenceError quiescenceError{patch::QuiescenceError::none};
    std::size_t failedStage{patch::kNoStage};
    std::size_t rollbackFailedStage{patch::kNoStage};
};

template <typename Port, typename Count = std::size_t>
struct ThreadPortReleaseState {
    Port *storage{nullptr};
    Count storageCount{0};
    Count suspendedCount{0};
    Count ownedPortCount{0};
    std::optional<Port> currentThreadPort;

    ThreadPortReleaseState() = default;
    ThreadPortReleaseState(const ThreadPortReleaseState &) = delete;
    ThreadPortReleaseState &operator=(const ThreadPortReleaseState &) = delete;
    ThreadPortReleaseState &operator=(ThreadPortReleaseState &&) = delete;
    ThreadPortReleaseState(ThreadPortReleaseState &&other) noexcept
        : storage(std::exchange(other.storage, nullptr)),
          storageCount(std::exchange(other.storageCount, 0)),
          suspendedCount(std::exchange(other.suspendedCount, 0)),
          ownedPortCount(std::exchange(other.ownedPortCount, 0)),
          currentThreadPort(
              std::exchange(other.currentThreadPort, std::nullopt)) {}
};

template <typename Port, typename Count = std::size_t>
struct ThreadPortReleaseOperations {
    using Resume = bool (*)(void *, Port) noexcept;
    using DeallocatePort = bool (*)(void *, Port) noexcept;
    using DeallocateStorage = bool (*)(void *, Port *, Count) noexcept;

    void *context{nullptr};
    Resume resume{nullptr};
    DeallocatePort deallocatePort{nullptr};
    DeallocateStorage deallocateStorage{nullptr};

    [[nodiscard]] bool usable() const noexcept {
        return resume != nullptr && deallocatePort != nullptr &&
               deallocateStorage != nullptr;
    }
};

template <typename Port, typename Count = std::size_t>
struct ThreadPortAcquisitionOperations {
    using Enumerate = bool (*)(void *, Port **, Count *) noexcept;
    using AcquireCurrent = bool (*)(void *, Port *) noexcept;
    using Suspend = bool (*)(void *, Port) noexcept;
    using ValidateSuspended = bool (*)(void *, Port) noexcept;

    void *context{nullptr};
    Enumerate enumerate{nullptr};
    AcquireCurrent acquireCurrent{nullptr};
    Suspend suspend{nullptr};
    ValidateSuspended validateSuspended{nullptr};
    ThreadPortReleaseOperations<Port, Count> release;

    [[nodiscard]] bool usable() const noexcept {
        return enumerate != nullptr && acquireCurrent != nullptr &&
               suspend != nullptr && validateSuspended != nullptr &&
               release.usable();
    }
};

namespace detail {

template <typename Port, typename Count>
void RetainProcessedThreadPort(ThreadPortReleaseState<Port, Count> &state,
                               Port port,
                               bool resumePending) noexcept {
    if (resumePending) {
        for (Count cursor = state.ownedPortCount;
             cursor > state.suspendedCount;
             --cursor) {
            state.storage[cursor] = state.storage[cursor - 1];
        }
        state.storage[state.suspendedCount++] = port;
    } else {
        state.storage[state.ownedPortCount] = port;
    }
    ++state.ownedPortCount;
}

}

template <typename Port, typename Count>
[[nodiscard]] bool ReleaseThreadPorts(
    ThreadPortReleaseState<Port, Count> &state,
    Count firstUnprocessed,
    const ThreadPortReleaseOperations<Port, Count> &operations) noexcept {
    if (!operations.usable()) {
        return false;
    }
    if (state.storage == nullptr) {
        if (state.storageCount != 0 || state.suspendedCount != 0 ||
            state.ownedPortCount != 0) {
            return false;
        }
        if (!state.currentThreadPort.has_value()) {
            return true;
        }
        if (!operations.deallocatePort(
                operations.context, *state.currentThreadPort)) {
            return false;
        }
        state.currentThreadPort.reset();
        return true;
    }
    if (firstUnprocessed > state.storageCount ||
        state.suspendedCount > state.ownedPortCount ||
        state.ownedPortCount > firstUnprocessed) {
        return false;
    }

    const Count originalSuspended = state.suspendedCount;
    const Count originalOwned = state.ownedPortCount;
    Count retainedSuspended = 0;
    Count retainedOwned = 0;
    for (Count index = 0; index < originalOwned; ++index) {
        const Port port = state.storage[index];
        if (index < originalSuspended &&
            !operations.resume(operations.context, port)) {
            for (Count cursor = retainedOwned;
                 cursor > retainedSuspended;
                 --cursor) {
                state.storage[cursor] = state.storage[cursor - 1];
            }
            state.storage[retainedSuspended++] = port;
            ++retainedOwned;
            continue;
        }
        if (!operations.deallocatePort(operations.context, port)) {
            state.storage[retainedOwned++] = port;
        }
    }
    for (Count index = firstUnprocessed; index < state.storageCount; ++index) {
        const Port port = state.storage[index];
        if (!operations.deallocatePort(operations.context, port)) {
            state.storage[retainedOwned++] = port;
        }
    }
    state.suspendedCount = retainedSuspended;
    state.ownedPortCount = retainedOwned;
    bool released = retainedOwned == 0;
    if (released) {
        if (operations.deallocateStorage(
                operations.context, state.storage, state.storageCount)) {
            state.storage = nullptr;
            state.storageCount = 0;
        } else {
            released = false;
        }
    }
    if (state.currentThreadPort.has_value()) {
        if (operations.deallocatePort(
                operations.context, *state.currentThreadPort)) {
            state.currentThreadPort.reset();
        } else {
            released = false;
        }
    }
    return released && state.storage == nullptr &&
           !state.currentThreadPort.has_value();
}

template <typename Port, typename Count>
[[nodiscard]] bool AcquireThreadPorts(
    ThreadPortReleaseState<Port, Count> &state,
    const ThreadPortAcquisitionOperations<Port, Count> &operations) noexcept {
    if (!operations.usable() || state.storage != nullptr ||
        state.storageCount != 0 || state.suspendedCount != 0 ||
        state.ownedPortCount != 0 || state.currentThreadPort.has_value()) {
        return false;
    }
    if (!operations.enumerate(
            operations.context, &state.storage, &state.storageCount)) {
        if (state.storage != nullptr) {
            static_cast<void>(
                ReleaseThreadPorts(state, Count{0}, operations.release));
        }
        return false;
    }

    Port currentThread{};
    if (!operations.acquireCurrent(operations.context, &currentThread)) {
        static_cast<void>(
            ReleaseThreadPorts(state, Count{0}, operations.release));
        return false;
    }
    state.currentThreadPort = currentThread;

    for (Count cursor = 0; cursor < state.storageCount; ++cursor) {
        const Port thread = state.storage[cursor];
        if (thread == currentThread) {
            detail::RetainProcessedThreadPort(state, thread, false);
            continue;
        }
        if (!operations.suspend(operations.context, thread)) {
            detail::RetainProcessedThreadPort(state, thread, false);
            static_cast<void>(ReleaseThreadPorts(
                state, static_cast<Count>(cursor + 1), operations.release));
            return false;
        }
        detail::RetainProcessedThreadPort(state, thread, true);
        if (!operations.validateSuspended(operations.context, thread)) {
            static_cast<void>(ReleaseThreadPorts(
                state, static_cast<Count>(cursor + 1), operations.release));
            return false;
        }
    }
    return true;
}

template <std::size_t StageCount, typename Context>
class Coordinator final {
public:
    using OperationsFactory = patch::Operations (*)(Context &) noexcept;

    Coordinator() = default;
    Coordinator(const Coordinator &) = delete;
    Coordinator &operator=(const Coordinator &) = delete;
    Coordinator(Coordinator &&) = delete;
    Coordinator &operator=(Coordinator &&) = delete;

    [[nodiscard]] InstallOutcome InstallFresh(
        Context context,
        OperationsFactory factory) noexcept {
        if (active_ || pendingActivation_ || cleanup_) {
            return {InstallDisposition::busy};
        }
        if (factory == nullptr) {
            return {
                InstallDisposition::failed,
                patch::InstallError::invalidOperations,
            };
        }

        patch::InstallResult<StageCount> result =
            patch::Install<StageCount>(factory(context));
        InstallOutcome outcome{
            InstallDisposition::failed,
            result.error(),
            result.rollbackError(),
            result.quiescenceError(),
            result.failedStage(),
            result.rollbackFailedStage(),
        };
        patch::InstalledPatches<StageCount> *const installed =
            result.installed();
        if (result.succeeded() && installed != nullptr) {
            active_.emplace(
                std::move(context), std::move(*installed), factory);
            outcome.disposition = InstallDisposition::installed;
            return outcome;
        }
        if (installed == nullptr || !installed->hasOwnership()) {
            return outcome;
        }

        const bool activationPending =
            result.error() == patch::InstallError::none &&
            installed->remainingCount() == StageCount &&
            installed->hasPendingQuiescence();
        if (activationPending) {
            pendingActivation_.emplace(
                std::move(context), std::move(*installed), factory);
            outcome.disposition = InstallDisposition::pendingActivation;
        } else {
            cleanup_.emplace(
                std::move(context), std::move(*installed), factory);
            outcome.disposition = InstallDisposition::cleanupPending;
        }
        return outcome;
    }

    [[nodiscard]] OwnershipStatus RetryOwned() noexcept {
        if (active_) {
            return OwnershipStatus::active;
        }
        if (pendingActivation_) {
            Record &record = *pendingActivation_;
            const patch::QuiescenceError error =
                patch::RetryQuiescence(record.patches, record.operations());
            if (error != patch::QuiescenceError::none) {
                return OwnershipStatus::pendingActivation;
            }
            if (record.patches.remainingCount() == StageCount &&
                !record.patches.hasPendingQuiescence()) {
                active_.emplace(std::move(record));
                pendingActivation_.reset();
                return OwnershipStatus::active;
            }
            cleanup_.emplace(std::move(record));
            pendingActivation_.reset();
        }
        if (cleanup_) {
            Record &record = *cleanup_;
            static_cast<void>(
                patch::Uninstall(record.patches, record.operations()));
            if (record.patches.hasOwnership()) {
                return OwnershipStatus::cleanupPending;
            }
            cleanup_.reset();
        }
        return OwnershipStatus::ready;
    }

    [[nodiscard]] bool supported() const noexcept {
        return active_.has_value();
    }

    [[nodiscard]] bool hasPendingActivation() const noexcept {
        return pendingActivation_.has_value();
    }

    [[nodiscard]] bool hasCleanup() const noexcept {
        return cleanup_.has_value();
    }

    [[nodiscard]] std::size_t cleanupRemainingCount() const noexcept {
        return cleanup_ ? cleanup_->patches.remainingCount() : 0;
    }

    [[nodiscard]] bool cleanupHasPendingQuiescence() const noexcept {
        return cleanup_ && cleanup_->patches.hasPendingQuiescence();
    }

private:
    struct Record final {
        Record(Context contextValue,
               patch::InstalledPatches<StageCount> patchesValue,
               OperationsFactory factoryValue) noexcept
            : context(std::move(contextValue)),
              patches(std::move(patchesValue)),
              factory(factoryValue) {}

        Record(const Record &) = delete;
        Record &operator=(const Record &) = delete;
        Record &operator=(Record &&) = delete;
        Record(Record &&other) noexcept
            : context(std::move(other.context)),
              patches(std::move(other.patches)),
              factory(other.factory) {}

        [[nodiscard]] patch::Operations operations() noexcept {
            return factory(context);
        }

        Context context;
        patch::InstalledPatches<StageCount> patches;
        OperationsFactory factory;
    };

    std::optional<Record> active_;
    std::optional<Record> pendingActivation_;
    std::optional<Record> cleanup_;
};

}

// ---- SidebarPatchEligibility -----------------------------------

namespace ym::sidebar::patch_guard::patch_eligibility {

enum class SidebarDisposition : std::uint8_t {
    installed,
    pendingActivation,
    cleanupPending,
    failed,
    busy,
};

enum class Ownership : std::uint8_t {
    ready,
    active,
    pendingActivation,
    cleanupPending,
};

struct Decision final {
    bool publish{false};
    bool invalidate{false};
    bool retainReceipt{false};
    std::uint64_t epoch{0};
};

struct Snapshot final {
    std::uint64_t activeAttempt{0};
    std::uint64_t pendingAttempt{0};
    std::uint64_t epoch{0};
    bool receiptPending{false};
    bool published{false};
};

class Orchestration final {
public:
    [[nodiscard]] constexpr bool needsPreflight(
        Ownership ownership) const noexcept {
        return ownership == Ownership::ready;
    }

    void beginAttempt(std::uint64_t attempt, bool hasReceipt) noexcept {
        activeAttempt_ = 0;
        pendingAttempt_ = attempt;
        receiptPending_ = hasReceipt;
        published_ = false;
    }

    [[nodiscard]] Decision observeInstall(std::uint64_t attempt,
                                          SidebarDisposition disposition,
                                          bool exactOwnership) noexcept {
        if (attempt == 0 || attempt != pendingAttempt_) {
            return clear(true);
        }
        switch (disposition) {
            case SidebarDisposition::installed:
                if (!exactOwnership) {
                    return clear(true);
                }
                return receiptPending_ ? publish(attempt) : clear(false);
            case SidebarDisposition::pendingActivation:
                if (!exactOwnership) {
                    return clear(true);
                }
                return {false, false, receiptPending_, epoch_};
            case SidebarDisposition::cleanupPending:
            case SidebarDisposition::failed:
            case SidebarDisposition::busy:
                return clear(receiptPending_ || published_);
        }
    }

    [[nodiscard]] Decision observeRetry(std::uint64_t attempt,
                                        Ownership ownership,
                                        bool exactOwnership) noexcept {
        if (published_) {
            if (attempt == activeAttempt_ && ownership == Ownership::active &&
                exactOwnership) {
                return {false, false, false, epoch_};
            }
            return clear(true);
        }
        if (!receiptPending_) {
            return {};
        }
        if (attempt == 0 || attempt != pendingAttempt_) {
            return clear(true);
        }
        switch (ownership) {
            case Ownership::active:
                return exactOwnership ? publish(attempt) : clear(true);
            case Ownership::pendingActivation:
                return exactOwnership
                           ? Decision{false, false, true, epoch_}
                           : clear(true);
            case Ownership::ready:
            case Ownership::cleanupPending:
                return clear(true);
        }
    }

    [[nodiscard]] Decision invalidate() noexcept {
        return clear(receiptPending_ || published_ || activeAttempt_ != 0);
    }

    [[nodiscard]] Snapshot snapshot() const noexcept {
        return {activeAttempt_, pendingAttempt_, epoch_, receiptPending_,
                published_};
    }

private:
    [[nodiscard]] Decision publish(std::uint64_t attempt) noexcept {
        if (epoch_ == UINT64_MAX) {
            return clear(true);
        }
        ++epoch_;
        activeAttempt_ = attempt;
        pendingAttempt_ = 0;
        receiptPending_ = false;
        published_ = true;
        return {true, false, false, epoch_};
    }

    [[nodiscard]] Decision clear(bool invalidated) noexcept {
        activeAttempt_ = 0;
        pendingAttempt_ = 0;
        receiptPending_ = false;
        published_ = false;
        return {false, invalidated, false, epoch_};
    }

    std::uint64_t activeAttempt_{0};
    std::uint64_t pendingAttempt_{0};
    std::uint64_t epoch_{0};
    bool receiptPending_{false};
    bool published_{false};
};

}

// ---- SidebarDiagnostic -----------------------------------------

#define YM_SIDEBAR_DIAGNOSTIC_LOG_SUBSYSTEM "com.sovietextension.sidebar"
#define YM_SIDEBAR_DIAGNOSTIC_LOG_CATEGORY "passive-diagnostic"
#define YM_SIDEBAR_DIAGNOSTIC_LOG_PREFIX "[YMNavigationSidebarDiagnostic]"
#define YM_SIDEBAR_DIAGNOSTIC_READY_LOG_FORMAT                           \
    YM_SIDEBAR_DIAGNOSTIC_LOG_PREFIX                                    \
    " event=loaded_ready callsite=image_install "                       \
    "fields=0x%{public}llx profile=exact bytes=exact"
#define YM_SIDEBAR_DIAGNOSTIC_ACTIVATION_LOG_FORMAT                      \
    YM_SIDEBAR_DIAGNOSTIC_LOG_PREFIX                                    \
    " event=secondary_activation callsite=native_activation "           \
    "fields=0x%{public}llx state=0x%{public}llx entry=0x%{public}llx "  \
    "owner=0x%{public}llx type=%{public}u container=%{public}u"

namespace ym::sidebar::diagnostic {

inline constexpr char kUnifiedLogSubsystem[] =
    YM_SIDEBAR_DIAGNOSTIC_LOG_SUBSYSTEM;
inline constexpr char kUnifiedLogCategory[] =
    YM_SIDEBAR_DIAGNOSTIC_LOG_CATEGORY;
inline constexpr char kDiagnosticLogPrefix[] =
    YM_SIDEBAR_DIAGNOSTIC_LOG_PREFIX;
inline constexpr char kUnifiedReadyLogFormat[] =
    YM_SIDEBAR_DIAGNOSTIC_READY_LOG_FORMAT;
inline constexpr char kUnifiedActivationLogFormat[] =
    YM_SIDEBAR_DIAGNOSTIC_ACTIVATION_LOG_FORMAT;

enum class Event : std::uint8_t {
    loadedReady,
    secondaryActivation,
};

struct InstallDecision {
    bool installSelectionHook{false};
    bool bypassInventoryApply{false};
    bool emitReady{false};
};

enum class InstallRoute : std::uint8_t {
    normal,
    diagnosticOnly,
};

inline constexpr std::size_t kNormalPatchStageCount = 6;
inline constexpr std::size_t kDiagnosticPatchStageCount = 1;

struct InstallPlan {
    InstallRoute route{InstallRoute::normal};
    std::size_t patchStageCount{kNormalPatchStageCount};
    bool applyInventory{true};
};

enum Field : std::uint64_t {
    stateIdentity = UINT64_C(1) << 0,
    entryIdentity = UINT64_C(1) << 1,
    ownerIdentity = UINT64_C(1) << 2,
    rawType = UINT64_C(1) << 3,
    fixedContainer = UINT64_C(1) << 4,
    exactProfile = UINT64_C(1) << 5,
    exactBytes = UINT64_C(1) << 6,
};

struct Record {
    Event event{Event::loadedReady};
    std::uint64_t fields{0};
    std::uintptr_t state{0};
    std::uintptr_t entry{0};
    std::uintptr_t owner{0};
    std::uint32_t type{0};
    std::uint32_t container{0};
};

struct State {
    bool emittedReady{false};
    bool hasActivation{false};
    Record lastActivation{};
    std::uint64_t nextActivationTick{0};
};

using RecordSink = bool (*)(
    void *, const Record &, const char *, std::size_t);
using UnifiedRecordSink = void (*)(void *, const Record &);
using SecondaryActivationOriginal = void (*)(
    std::uint32_t, void *, std::uint64_t, void *);

constexpr bool ModeEnabled(const char *value) noexcept {
    return value != nullptr && value[0] == '1' && value[1] == '\0';
}

constexpr InstallPlan PlanInstall(const char *modeValue) noexcept {
    return ModeEnabled(modeValue)
               ? InstallPlan{InstallRoute::diagnosticOnly,
                             kDiagnosticPatchStageCount,
                             false}
               : InstallPlan{InstallRoute::normal,
                             kNormalPatchStageCount,
                             true};
}

constexpr InstallDecision DecideInstall(bool modeEnabled,
                                        bool exactProfile,
                                        bool targetBytesMatch) noexcept {
    const bool allowed = modeEnabled && exactProfile && targetBytesMatch;
    return {allowed, allowed, allowed};
}

constexpr Record ReadyRecord() noexcept {
    return {
        Event::loadedReady,
        exactProfile | exactBytes,
    };
}

constexpr Record ActivationRecord(std::uintptr_t state,
                                  std::uintptr_t entry,
                                  std::uintptr_t owner,
                                  std::uint32_t type) noexcept {
    return {
        Event::secondaryActivation,
        stateIdentity | entryIdentity | ownerIdentity | rawType |
            fixedContainer,
        state,
        entry,
        owner,
        type,
        1,
    };
}

constexpr bool RecordIsAllowlisted(const Record &record) noexcept {
    constexpr std::uint64_t readyFields = exactProfile | exactBytes;
    constexpr std::uint64_t activationFields =
        stateIdentity | entryIdentity | ownerIdentity | rawType |
        fixedContainer;
    switch (record.event) {
        case Event::loadedReady:
            return record.fields == readyFields;
        case Event::secondaryActivation:
            return record.fields == activationFields && record.container == 1;
    }
    return false;
}

constexpr const char *UnifiedLogFormat(Event event) noexcept {
    switch (event) {
        case Event::loadedReady:
            return kUnifiedReadyLogFormat;
        case Event::secondaryActivation:
            return kUnifiedActivationLogFormat;
    }
    return nullptr;
}

inline bool EmitUnified(const Record &record,
                        void *context,
                        UnifiedRecordSink sink) noexcept {
    if (sink == nullptr || !RecordIsAllowlisted(record) ||
        UnifiedLogFormat(record.event) == nullptr) {
        return false;
    }
    sink(context, record);
    return true;
}

inline std::size_t FormatRecord(const Record &record,
                                char *output,
                                std::size_t capacity) noexcept {
    if (!RecordIsAllowlisted(record) || output == nullptr || capacity == 0) {
        return 0;
    }
    int length = 0;
    switch (record.event) {
        case Event::loadedReady:
            length = std::snprintf(
                output,
                capacity,
                "event=loaded_ready callsite=image_install "
                "profile=exact bytes=exact");
            break;
        case Event::secondaryActivation:
            length = std::snprintf(
                output,
                capacity,
                "event=secondary_activation callsite=native_activation "
                "state=0x%llx entry=0x%llx owner=0x%llx type=%u "
                "container=%u",
                static_cast<unsigned long long>(record.state),
                static_cast<unsigned long long>(record.entry),
                static_cast<unsigned long long>(record.owner),
                record.type,
                record.container);
            break;
    }
    if (length <= 0 || static_cast<std::size_t>(length) >= capacity) {
        output[0] = '\0';
        return 0;
    }
    return static_cast<std::size_t>(length);
}

inline bool Emit(const Record &record,
                 void *context,
                 RecordSink sink) noexcept {
    if (sink == nullptr || !RecordIsAllowlisted(record)) {
        return false;
    }
    char output[384]{};
    const std::size_t length = FormatRecord(record, output, sizeof(output));
    return length != 0 && sink(context, record, output, length);
}

inline bool EmitReady(State &state,
                      const InstallDecision &decision,
                      void *context,
                      RecordSink sink) noexcept {
    if (!decision.emitReady || state.emittedReady) {
        return false;
    }
    if (!Emit(ReadyRecord(), context, sink)) {
        return false;
    }
    state.emittedReady = true;
    return true;
}

constexpr bool SameActivation(const Record &left,
                              const Record &right) noexcept {
    return left.event == right.event && left.fields == right.fields &&
           left.state == right.state && left.entry == right.entry &&
           left.owner == right.owner && left.type == right.type &&
           left.container == right.container;
}

inline bool EmitActivation(State &state,
                           std::uint64_t tick,
                           const Record &record,
                           void *context,
                           RecordSink sink) noexcept {
    if (record.event != Event::secondaryActivation || sink == nullptr) {
        return false;
    }
    if ((state.hasActivation &&
         SameActivation(state.lastActivation, record)) ||
        tick < state.nextActivationTick || !Emit(record, context, sink)) {
        return false;
    }
    state.hasActivation = true;
    state.lastActivation = record;
    state.nextActivationTick = tick + 1;
    return true;
}

inline void ObserveSecondaryActivationAndForward(
    std::uint32_t operation,
    void *state,
    std::uint64_t x2,
    void *x3,
    void *context,
    bool (*readable)(void *, const void *, std::size_t) noexcept,
    void (*observer)(void *, const Record &) noexcept,
    SecondaryActivationOriginal original) {
    if (operation == 1 && state != nullptr && readable != nullptr &&
        observer != nullptr && readable(context, state, 0x24)) {
        const auto *bytes = static_cast<const std::uint8_t *>(state);
        std::uintptr_t entry = 0;
        std::uintptr_t owner = 0;
        std::uint32_t type = 0;
        std::memcpy(&entry, bytes + 0x10, sizeof(entry));
        std::memcpy(&owner, bytes + 0x18, sizeof(owner));
        std::memcpy(&type, bytes + 0x20, sizeof(type));
        observer(context,
                 ActivationRecord(reinterpret_cast<std::uintptr_t>(state),
                                  entry,
                                  owner,
                                  type));
    }
    if (original != nullptr) {
        original(operation, state, x2, x3);
    }
}

}

// ---- SidebarPatchOwnerState ------------------------------------

namespace ym::sidebar::patch_guard {

struct InstallGeneration final {
    std::uint64_t value{0};

    [[nodiscard]] constexpr bool valid() const noexcept { return value != 0; }
};

enum class OwnerEligibility : std::uint8_t {
    ineligible,
    eligible,
};

struct OwnerToken final {
    std::uint64_t installGeneration{0};
    std::uint64_t ownerGeneration{0};
    bool valid{false};
    OwnerEligibility eligibility{OwnerEligibility::ineligible};
};

class OwnerStateConsumer {
public:
    virtual ~OwnerStateConsumer() = default;

    virtual void InvalidateOwner(const OwnerToken &token) = 0;
    virtual void PublishOwner(const OwnerToken &token) = 0;
    virtual void TeardownOwner(const OwnerToken &token) = 0;
};

enum class CaptureDisposition : std::uint8_t {
    rejected,
    duplicate,
    published,
    terminal,
};

enum class DestructionDisposition : std::uint8_t {
    ignored,
    tornDown,
};

class OwnerState final {
public:
    struct CounterSeed final {
        std::uint64_t installGeneration{0};
        std::uint64_t ownerGeneration{0};
    };

    constexpr OwnerState() noexcept = default;

    explicit constexpr OwnerState(CounterSeed seed) noexcept
        : nextInstallGeneration_(seed.installGeneration),
          nextOwnerGeneration_(seed.ownerGeneration) {}

    [[nodiscard]] InstallGeneration BeginInstall(OwnerStateConsumer &consumer) {
        InvalidateCurrent(consumer);
        if (terminal_ || !Advance(nextInstallGeneration_)) {
            terminal_ = true;
            return {};
        }
        activeInstall_ = {nextInstallGeneration_};
        return activeInstall_;
    }

    [[nodiscard]] CaptureDisposition Capture(
        std::uint64_t ownerIdentity,
        OwnerEligibility eligibility,
        InstallGeneration install,
        const OwnerToken &observedToken,
        OwnerStateConsumer &consumer) {
        if (terminal_) {
            return CaptureDisposition::terminal;
        }
        if (!MatchesInstall(install) || ownerIdentity == 0) {
            return CaptureDisposition::rejected;
        }
        if (observedToken.valid && !SameToken(observedToken, current_)) {
            return CaptureDisposition::rejected;
        }
        if (eligibility != OwnerEligibility::eligible) {
            if (currentOwnerIdentity_ == ownerIdentity &&
                SameToken(observedToken, current_)) {
                InvalidateCurrent(consumer);
            }
            return CaptureDisposition::rejected;
        }
        if (current_.valid && currentOwnerIdentity_ == ownerIdentity) {
            return CaptureDisposition::duplicate;
        }

        InvalidateCurrent(consumer);
        if (!Advance(nextOwnerGeneration_)) {
            terminal_ = true;
            return CaptureDisposition::terminal;
        }
        currentOwnerIdentity_ = ownerIdentity;
        current_ = {
            activeInstall_.value,
            nextOwnerGeneration_,
            true,
            OwnerEligibility::eligible,
        };
        consumer.PublishOwner(current_);
        return CaptureDisposition::published;
    }

    [[nodiscard]] DestructionDisposition Destroy(
        std::uint64_t ownerIdentity,
        InstallGeneration install,
        const OwnerToken &observedToken,
        OwnerStateConsumer &consumer) {
        if (terminal_ || !MatchesInstall(install) || ownerIdentity == 0 ||
            currentOwnerIdentity_ != ownerIdentity ||
            !SameToken(observedToken, current_)) {
            return DestructionDisposition::ignored;
        }
        const OwnerToken token = current_;
        InvalidateCurrent(consumer);
        consumer.TeardownOwner(token);
        return DestructionDisposition::tornDown;
    }

    [[nodiscard]] constexpr OwnerToken current() const noexcept {
        return current_;
    }

    [[nodiscard]] constexpr bool CanPublish(const OwnerToken &token) const noexcept {
        return !terminal_ && token.valid &&
               token.eligibility == OwnerEligibility::eligible &&
               SameToken(token, current_);
    }

    [[nodiscard]] constexpr bool terminal() const noexcept { return terminal_; }

private:
    [[nodiscard]] static constexpr bool Advance(std::uint64_t &generation) noexcept {
        if (generation == std::numeric_limits<std::uint64_t>::max()) {
            return false;
        }
        ++generation;
        return generation != 0;
    }

    [[nodiscard]] constexpr bool MatchesInstall(
        InstallGeneration install) const noexcept {
        return install.valid() && activeInstall_.valid() &&
               install.value == activeInstall_.value;
    }

    [[nodiscard]] static constexpr bool SameToken(
        const OwnerToken &left,
        const OwnerToken &right) noexcept {
        return left.installGeneration == right.installGeneration &&
               left.ownerGeneration == right.ownerGeneration &&
               left.valid == right.valid && left.eligibility == right.eligibility;
    }

    void InvalidateCurrent(OwnerStateConsumer &consumer) {
        if (!current_.valid) {
            return;
        }
        const OwnerToken token = current_;
        current_ = {};
        currentOwnerIdentity_ = 0;
        consumer.InvalidateOwner(token);
    }

    std::uint64_t nextInstallGeneration_{0};
    std::uint64_t nextOwnerGeneration_{0};
    std::uint64_t currentOwnerIdentity_{0};
    InstallGeneration activeInstall_{};
    OwnerToken current_{};
    bool terminal_{false};
};

}

// ---- SidebarPatchOwnerBridge -----------------------------------

namespace ym::sidebar::patch_guard {

inline constexpr std::uint64_t kComponentSurfaceOffset = 0x180;

enum class BridgeLifecycleEvent : std::uint8_t {
    generationInvalidated,
    tokenCleared,
    surfaceRemoved,
};

using CandidateReader =
    std::function<bool(std::uint64_t, std::uint64_t, std::uint64_t &)>;
using BridgeLifecycleObserver =
    std::function<void(BridgeLifecycleEvent, const OwnerToken &)>;
using CandidateVisitor = std::function<bool(std::uint64_t)>;

class OwnerBridge final {
public:
    explicit OwnerBridge(CandidateReader reader,
                         BridgeLifecycleObserver lifecycleObserver = {});
    ~OwnerBridge();

    OwnerBridge(const OwnerBridge &) = delete;
    OwnerBridge &operator=(const OwnerBridge &) = delete;

    void setCandidateReader(CandidateReader reader);
    void setLifecycleObserver(BridgeLifecycleObserver observer);
    void bindPatchEpoch(std::uint64_t epoch, std::uint64_t installAttempt);
    void invalidatePatchEpoch();
    [[nodiscard]] CaptureDisposition captureOwner(
        std::uint64_t ownerIdentity,
        std::uint64_t mainWindowIdentity,
        const OwnerToken &observedToken = {});
    void revokeAtDestructorStart(std::uint64_t mainWindowIdentity);
    [[nodiscard]] bool withResolvedCandidate(const OwnerToken &token,
                                             const CandidateVisitor &visitor) const;

    [[nodiscard]] OwnerToken currentToken() const noexcept;

    [[nodiscard]] std::uint64_t patchEpoch() const noexcept;
    [[nodiscard]] std::uint64_t installAttempt() const noexcept;
    [[nodiscard]] std::size_t eligibleSnapshotCount() const noexcept;

private:
    class Implementation;
    std::unique_ptr<Implementation> implementation_;
};

OwnerBridge &SharedSidebarPatchOwnerBridge();

}

