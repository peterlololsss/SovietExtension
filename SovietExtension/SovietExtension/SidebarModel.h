#pragma once

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <map>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>
#include <stdexcept>

// ---- SidebarConfiguration --------------------------------------

namespace ym::sidebar {

enum class Entry : std::uint8_t {
    primaryChats,
    primaryContacts,
    primaryFavorites,
    // 发现. Managed for VISIBILITY only: WeChat's own primary order getter
    // always appends type 3 last (0xE55970 pushes 0,1,2 then conditionally 3),
    // so it is deliberately NOT part of the reorderable primary order.
    primaryDiscover,
    secondaryMoments,
    secondaryChannels,
    secondarySearch,
    secondaryGameCenter,
    secondaryMiniPrograms,
};

enum class Group : std::uint8_t {
    primary,
    secondary,
};

inline constexpr std::array<Entry, 9> kAllEntries = {
    Entry::primaryChats,
    Entry::primaryContacts,
    Entry::primaryFavorites,
    Entry::primaryDiscover,
    Entry::secondaryMoments,
    Entry::secondaryChannels,
    Entry::secondarySearch,
    Entry::secondaryGameCenter,
    Entry::secondaryMiniPrograms,
};

inline constexpr std::array<Entry, 3> kCanonicalPrimaryOrder = {
    Entry::primaryChats,
    Entry::primaryContacts,
    Entry::primaryFavorites,
};

inline constexpr std::array<Entry, 5> kCanonicalSecondaryOrder = {
    Entry::secondaryMoments,
    Entry::secondaryChannels,
    Entry::secondarySearch,
    Entry::secondaryGameCenter,
    Entry::secondaryMiniPrograms,
};

constexpr std::size_t EntryIndex(Entry entry) noexcept {
    switch (entry) {
        case Entry::primaryChats:
            return 0;
        case Entry::primaryContacts:
            return 1;
        case Entry::primaryFavorites:
            return 2;
        case Entry::secondaryMoments:
            return 3;
        case Entry::secondaryChannels:
            return 4;
        case Entry::secondarySearch:
            return 5;
        case Entry::secondaryGameCenter:
            return 6;
        case Entry::secondaryMiniPrograms:
            return 7;
        // Appended last on purpose: the existing indices must not shift, or a
        // saved configuration would be reinterpreted against the wrong entries.
        case Entry::primaryDiscover:
            return 8;
    }
    return 0;
}

constexpr std::string_view Identifier(Entry entry) noexcept {
    switch (entry) {
        case Entry::primaryChats:
            return "primary.chats";
        case Entry::primaryContacts:
            return "primary.contacts";
        case Entry::primaryFavorites:
            return "primary.favorites";
        case Entry::secondaryMoments:
            return "secondary.moments";
        case Entry::secondaryChannels:
            return "secondary.channels";
        case Entry::secondarySearch:
            return "secondary.search";
        case Entry::secondaryGameCenter:
            return "secondary.gameCenter";
        case Entry::secondaryMiniPrograms:
            return "secondary.miniPrograms";
        case Entry::primaryDiscover:
            return "primary.discover";
    }
    return {};
}

inline std::optional<Entry> EntryFromIdentifier(
    std::string_view identifier) noexcept {
    for (Entry entry : kAllEntries) {
        if (Identifier(entry) == identifier) {
            return entry;
        }
    }
    return std::nullopt;
}

constexpr Group GroupOf(Entry entry) noexcept {
    switch (entry) {
        case Entry::primaryChats:
        case Entry::primaryContacts:
        case Entry::primaryFavorites:
        case Entry::primaryDiscover:
            return Group::primary;
        case Entry::secondaryMoments:
        case Entry::secondaryChannels:
        case Entry::secondarySearch:
        case Entry::secondaryGameCenter:
        case Entry::secondaryMiniPrograms:
            return Group::secondary;
    }
    return Group::secondary;
}

struct Configuration {
    static constexpr std::int64_t kVersion = 2;

    std::int64_t version{kVersion};
    std::array<bool, kAllEntries.size()> states{};
    std::vector<Entry> primaryOrder{kCanonicalPrimaryOrder.begin(),
                                    kCanonicalPrimaryOrder.end()};
    std::vector<Entry> secondaryOrder{kCanonicalSecondaryOrder.begin(),
                                      kCanonicalSecondaryOrder.end()};

    Configuration() {
        states.fill(true);
    }

    [[nodiscard]] bool isEnabled(Entry entry) const noexcept {
        return states[EntryIndex(entry)];
    }

    void setEnabled(Entry entry, bool enabled) noexcept {
        states[EntryIndex(entry)] = enabled;
    }

    friend bool operator==(const Configuration &,
                           const Configuration &) = default;
};

inline void EnforceFixedProductEntries(Configuration &configuration) noexcept {
    configuration.setEnabled(Entry::primaryChats, true);
}

struct PropertyList {
    std::int64_t version{Configuration::kVersion};
    std::map<std::string, bool, std::less<>> states;
    std::vector<std::string> primaryOrder;
    std::vector<std::string> secondaryOrder;

    friend bool operator==(const PropertyList &, const PropertyList &) = default;
};

class LegacyVisibility {
public:
    void set(Entry entry, bool enabled) noexcept {
        states_[EntryIndex(entry)] = enabled;
    }

    void setChatFiles(bool enabled) noexcept { chatFiles_ = enabled; }

    [[nodiscard]] std::optional<bool> value(Entry entry) const noexcept {
        return states_[EntryIndex(entry)];
    }

    [[nodiscard]] std::optional<bool> chatFilesValue() const noexcept {
        return chatFiles_;
    }

private:
    std::array<std::optional<bool>, kAllEntries.size()> states_{};
    std::optional<bool> chatFiles_;
};

enum class ValidationErrorCode : std::uint8_t {
    unsupportedVersion,
    unknownStateIdentifier,
    missingState,
    unknownOrderIdentifier,
    duplicateOrderIdentifier,
    crossGroupIdentifier,
    nonSortableIdentifier,
    incompleteOrder,
    allPrimaryDisabled,
};

struct ValidationError {
    ValidationErrorCode code;
    std::string message;
    std::string identifier;
};

class ValidationResult {
public:
    [[nodiscard]] static ValidationResult Success(
        Configuration configuration) {
        return ValidationResult(std::move(configuration), std::nullopt);
    }

    [[nodiscard]] static ValidationResult Failure(ValidationError error) {
        return ValidationResult(std::nullopt, std::move(error));
    }

    [[nodiscard]] const Configuration *configuration() const noexcept {
        return configuration_ ? &*configuration_ : nullptr;
    }

    [[nodiscard]] const ValidationError *error() const noexcept {
        return error_ ? &*error_ : nullptr;
    }

private:
    ValidationResult(std::optional<Configuration> configuration,
                     std::optional<ValidationError> error)
        : configuration_(std::move(configuration)), error_(std::move(error)) {}

    std::optional<Configuration> configuration_;
    std::optional<ValidationError> error_;
};

inline PropertyList ToPropertyList(const Configuration &configuration) {
    Configuration normalized = configuration;
    EnforceFixedProductEntries(normalized);
    PropertyList propertyList;
    propertyList.version = normalized.version;
    for (Entry entry : kAllEntries) {
        propertyList.states.emplace(std::string(Identifier(entry)),
                                    normalized.isEnabled(entry));
    }
    for (Entry entry : normalized.primaryOrder) {
        propertyList.primaryOrder.emplace_back(Identifier(entry));
    }
    for (Entry entry : normalized.secondaryOrder) {
        propertyList.secondaryOrder.emplace_back(Identifier(entry));
    }
    return propertyList;
}

inline Configuration MigrateLegacyVisibility(const LegacyVisibility &legacy) {
    Configuration configuration;
    for (Entry entry : kAllEntries) {
        if (const std::optional<bool> enabled = legacy.value(entry)) {
            configuration.setEnabled(entry, *enabled);
        }
    }
    static_cast<void>(legacy.chatFilesValue());
    EnforceFixedProductEntries(configuration);
    return configuration;
}

namespace detail {

inline ValidationError Error(ValidationErrorCode code,
                             std::string message,
                             std::string identifier = {}) {
    return ValidationError{code, std::move(message), std::move(identifier)};
}

inline std::optional<ValidationError> ValidatePrimaryVisibility(
    const Configuration &configuration) {
    if (!configuration.isEnabled(Entry::primaryChats) &&
        !configuration.isEnabled(Entry::primaryContacts) &&
        !configuration.isEnabled(Entry::primaryFavorites)) {
        return Error(ValidationErrorCode::allPrimaryDisabled,
                     "at least one primary entry must remain enabled");
    }
    return std::nullopt;
}

template <std::size_t Size>
inline std::vector<Entry> NormalizeOrder(
    const std::vector<std::string> &stored,
    const std::array<Entry, Size> &canonical) {
    std::vector<Entry> normalized;
    normalized.reserve(Size);
    for (const std::string &identifier : stored) {
        const std::optional<Entry> entry = EntryFromIdentifier(identifier);
        if (!entry || std::find(canonical.begin(), canonical.end(), *entry) ==
                          canonical.end() ||
            std::find(normalized.begin(), normalized.end(), *entry) !=
                normalized.end()) {
            continue;
        }
        normalized.push_back(*entry);
    }
    for (Entry entry : canonical) {
        if (std::find(normalized.begin(), normalized.end(), entry) ==
            normalized.end()) {
            normalized.push_back(entry);
        }
    }
    return normalized;
}

template <std::size_t Size>
inline std::optional<ValidationError> ValidateOrder(
    const std::vector<std::string> &input,
    const std::array<Entry, Size> &canonical,
    Group expectedGroup,
    std::vector<Entry> &validated) {
    validated.clear();
    validated.reserve(Size);
    for (const std::string &identifier : input) {
        const std::optional<Entry> entry = EntryFromIdentifier(identifier);
        if (!entry) {
            return Error(ValidationErrorCode::unknownOrderIdentifier,
                         "unknown order identifier: " + identifier,
                         identifier);
        }
        if (std::find(canonical.begin(), canonical.end(), *entry) ==
            canonical.end()) {
            if (GroupOf(*entry) != expectedGroup) {
                return Error(ValidationErrorCode::crossGroupIdentifier,
                             "cross-group order identifier: " + identifier,
                             identifier);
            }
            return Error(ValidationErrorCode::nonSortableIdentifier,
                         "non-sortable order identifier: " + identifier,
                         identifier);
        }
        if (std::find(validated.begin(), validated.end(), *entry) !=
            validated.end()) {
            return Error(ValidationErrorCode::duplicateOrderIdentifier,
                         "duplicate order identifier: " + identifier,
                         identifier);
        }
        validated.push_back(*entry);
    }
    if (validated.size() != Size) {
        const std::string groupName =
            expectedGroup == Group::primary ? "primary" : "secondary";
        return Error(ValidationErrorCode::incompleteOrder,
                     "incomplete " + groupName + " order");
    }
    return std::nullopt;
}

}

inline ValidationResult NormalizeStoredConfiguration(
    const PropertyList &stored) {
    if (stored.version != Configuration::kVersion) {
        return ValidationResult::Failure(detail::Error(
            ValidationErrorCode::unsupportedVersion,
            "unsupported configuration version: " +
                std::to_string(stored.version)));
    }

    Configuration configuration;
    for (Entry entry : kAllEntries) {
        const auto found = stored.states.find(Identifier(entry));
        if (found != stored.states.end()) {
            configuration.setEnabled(entry, found->second);
        }
    }
    EnforceFixedProductEntries(configuration);
    configuration.primaryOrder = detail::NormalizeOrder(
        stored.primaryOrder, kCanonicalPrimaryOrder);
    configuration.secondaryOrder = detail::NormalizeOrder(
        stored.secondaryOrder, kCanonicalSecondaryOrder);
    if (const std::optional<ValidationError> error =
            detail::ValidatePrimaryVisibility(configuration)) {
        return ValidationResult::Failure(*error);
    }
    return ValidationResult::Success(std::move(configuration));
}

inline ValidationResult ValidateSaveInput(const PropertyList &input) {
    if (input.version != Configuration::kVersion) {
        return ValidationResult::Failure(detail::Error(
            ValidationErrorCode::unsupportedVersion,
            "unsupported configuration version: " +
                std::to_string(input.version)));
    }

    for (const auto &[identifier, enabled] : input.states) {
        static_cast<void>(enabled);
        if (!EntryFromIdentifier(identifier)) {
            return ValidationResult::Failure(detail::Error(
                ValidationErrorCode::unknownStateIdentifier,
                "unknown state identifier: " + identifier,
                identifier));
        }
    }
    for (Entry entry : kAllEntries) {
        if (!input.states.contains(Identifier(entry))) {
            const std::string identifier(Identifier(entry));
            return ValidationResult::Failure(detail::Error(
                ValidationErrorCode::missingState,
                "missing state identifier: " + identifier,
                identifier));
        }
    }

    std::vector<Entry> primaryOrder;
    if (const std::optional<ValidationError> error = detail::ValidateOrder(
            input.primaryOrder,
            kCanonicalPrimaryOrder,
            Group::primary,
            primaryOrder)) {
        return ValidationResult::Failure(*error);
    }
    std::vector<Entry> secondaryOrder;
    if (const std::optional<ValidationError> error = detail::ValidateOrder(
            input.secondaryOrder,
            kCanonicalSecondaryOrder,
            Group::secondary,
            secondaryOrder)) {
        return ValidationResult::Failure(*error);
    }

    Configuration configuration;
    for (Entry entry : kAllEntries) {
        const auto state = input.states.find(Identifier(entry));
        configuration.setEnabled(entry, state->second);
    }
    EnforceFixedProductEntries(configuration);
    configuration.primaryOrder = std::move(primaryOrder);
    configuration.secondaryOrder = std::move(secondaryOrder);
    if (const std::optional<ValidationError> error =
            detail::ValidatePrimaryVisibility(configuration)) {
        return ValidationResult::Failure(*error);
    }
    return ValidationResult::Success(std::move(configuration));
}

inline ValidationResult LoadConfiguration(
    const std::optional<PropertyList> &storedV2,
    const LegacyVisibility &legacy) {
    if (storedV2) {
        return NormalizeStoredConfiguration(*storedV2);
    }
    Configuration configuration = MigrateLegacyVisibility(legacy);
    if (const std::optional<ValidationError> error =
            detail::ValidatePrimaryVisibility(configuration)) {
        return ValidationResult::Failure(*error);
    }
    return ValidationResult::Success(std::move(configuration));
}

}

// ---- SidebarSettingsModel --------------------------------------

namespace ym::sidebar {

enum class SettingsErrorCode : std::uint8_t {
    none,
    invalidConfiguration,
    allPrimaryDisabled,
    unknownEntry,
    staleEntry,
    crossGroup,
    duplicateOrder,
    missingOrder,
    outOfRange,
    cannotDisableLastPrimary,
    noMove,
    invalidSelection,
    fixedEntry,
};

struct SettingsOperationResult {
    SettingsErrorCode code{SettingsErrorCode::none};
    bool changed{false};
    std::string identifier;

    [[nodiscard]] bool succeeded() const noexcept {
        return code == SettingsErrorCode::none;
    }

    [[nodiscard]] bool failed() const noexcept { return !succeeded(); }

    [[nodiscard]] SettingsErrorCode error() const noexcept { return code; }

    [[nodiscard]] SettingsErrorCode reason() const noexcept { return code; }

    [[nodiscard]] explicit operator bool() const noexcept { return succeeded(); }
};

struct SettingsValidationResult {
    SettingsErrorCode code{SettingsErrorCode::none};
    std::string message;

    [[nodiscard]] bool valid() const noexcept {
        return code == SettingsErrorCode::none;
    }

    [[nodiscard]] SettingsErrorCode error() const noexcept { return code; }
};

struct SettingsRow {
    Group group{Group::primary};
    Entry entry{Entry::primaryChats};
    std::string label;
    std::string identifier;
    bool enabled{false};
    bool selected{false};
    bool canMoveUp{false};
    bool canMoveDown{false};
    std::string accessibilityIdentifier;
};

inline constexpr std::string_view Label(Entry entry) noexcept {
    switch (entry) {
        case Entry::primaryChats:
            return "聊天";
        case Entry::primaryContacts:
            return "通讯录";
        case Entry::primaryFavorites:
            return "收藏";
        case Entry::secondaryMoments:
            return "朋友圈";
        case Entry::secondaryChannels:
            return "视频号";
        case Entry::secondarySearch:
            return "搜一搜";
        case Entry::secondaryGameCenter:
            return "游戏中心（小游戏）";
        case Entry::secondaryMiniPrograms:
            return "小程序";
        case Entry::primaryDiscover:
            return "发现";
    }
    return {};
}

inline constexpr std::string_view AccessibilityIdentifier(
    Entry entry) noexcept {
    return Identifier(entry);
}

class SidebarSettingsModel {
public:
    enum class DropPosition : std::uint8_t {
        before,
        after,
    };

    using Row = SettingsRow;
    using Result = SettingsOperationResult;
    using ErrorCode = SettingsErrorCode;

    SidebarSettingsModel() : SidebarSettingsModel(Configuration{}) {}

    explicit SidebarSettingsModel(Configuration configuration)
        : baseline_(std::move(configuration)), draft_(baseline_) {
        EnforceFixedProductEntries(baseline_);
        draft_ = baseline_;
        const SettingsValidationResult validation = Validate(baseline_);
        if (!validation.valid()) {
            throw std::invalid_argument(validation.message);
        }
        selected_ = Entry::primaryContacts;
        baselineSelection_ = selected_;
    }

    [[nodiscard]] static SettingsValidationResult Validate(
        const Configuration &configuration) {
        const ValidationResult strict =
            ValidateSaveInput(ToPropertyList(configuration));
        if (strict.configuration() == nullptr) {
            SettingsValidationResult result;
            result.code = SettingsErrorCode::invalidConfiguration;
            if (strict.error() != nullptr) {
                result.message = strict.error()->message;
                switch (strict.error()->code) {
                    case ValidationErrorCode::duplicateOrderIdentifier:
                        result.code = SettingsErrorCode::duplicateOrder;
                        break;
                    case ValidationErrorCode::incompleteOrder:
                        result.code = SettingsErrorCode::missingOrder;
                        break;
                    case ValidationErrorCode::crossGroupIdentifier:
                        result.code = SettingsErrorCode::crossGroup;
                        break;
                    case ValidationErrorCode::unknownOrderIdentifier:
                        result.code = SettingsErrorCode::staleEntry;
                        break;
                    case ValidationErrorCode::nonSortableIdentifier:
                        result.code = SettingsErrorCode::invalidConfiguration;
                        break;
                    case ValidationErrorCode::unsupportedVersion:
                    case ValidationErrorCode::unknownStateIdentifier:
                    case ValidationErrorCode::missingState:
                        result.code = SettingsErrorCode::invalidConfiguration;
                        break;
                    case ValidationErrorCode::allPrimaryDisabled:
                        result.code = SettingsErrorCode::allPrimaryDisabled;
                        break;
                }
            } else {
                result.message = "invalid sidebar configuration";
            }
            return result;
        }
        return {};
    }

    [[nodiscard]] const Configuration &configuration() const noexcept {
        return draft_;
    }

    [[nodiscard]] const Configuration &draftConfiguration() const noexcept {
        return draft_;
    }

    [[nodiscard]] const Configuration &baselineConfiguration() const noexcept {
        return baseline_;
    }

    [[nodiscard]] std::optional<Entry> selectedEntry() const noexcept {
        return selected_;
    }

    [[nodiscard]] bool isEnabled(Entry entry) const noexcept {
        return IsManagedEntry(entry) && draft_.isEnabled(entry);
    }

    [[nodiscard]] bool isSelected(Entry entry) const noexcept {
        return selected_ == entry;
    }

    [[nodiscard]] std::vector<Entry> order(Group group) const {
        if (group == Group::primary) {
            std::vector<Entry> managed;
            managed.reserve(3);
            for (Entry entry : draft_.primaryOrder) {
                if (entry != Entry::primaryChats) {
                    managed.push_back(entry);
                }
            }
            // 发现 is managed for visibility but is NOT part of the reorderable
            // primary order: WeChat's own primary order getter always appends
            // type 3 last, so any position we chose for it would be discarded.
            // Append it as a pinned tail row so it can be toggled, never moved.
            managed.push_back(Entry::primaryDiscover);
            return managed;
        }
        if (group == Group::secondary) {
            return draft_.secondaryOrder;
        }
        return {};
    }

    // The rows the user can actually permute. `order()` additionally carries the
    // pinned 发现 tail, which is displayed but never reordered, so every move
    // path works from this instead.
    [[nodiscard]] std::vector<Entry> sortableOrder(Group group) const {
        std::vector<Entry> result = order(group);
        result.erase(std::remove(result.begin(), result.end(),
                                 Entry::primaryDiscover),
                     result.end());
        return result;
    }

    [[nodiscard]] std::vector<Entry> primaryOrder() const {
        return order(Group::primary);
    }

    [[nodiscard]] std::vector<Entry> secondaryOrder() const {
        return draft_.secondaryOrder;
    }

    [[nodiscard]] std::vector<Row> rows() const {
        std::vector<Row> output;
        output.reserve(kAllEntries.size() - 1);
        AppendRows(Group::primary, order(Group::primary), output);
        AppendRows(Group::secondary, draft_.secondaryOrder, output);
        return output;
    }

    [[nodiscard]] Result select(Entry entry) {
        if (entry == Entry::primaryChats) {
            return Failure(SettingsErrorCode::fixedEntry,
                           std::string(Identifier(entry)));
        }
        if (!IsManagedEntry(entry)) {
            return Failure(SettingsErrorCode::unknownEntry);
        }
        if (selected_ == entry) {
            return Success(false);
        }
        selected_ = entry;
        return Success(true);
    }

    [[nodiscard]] Result select(std::string_view identifier) {
        const std::optional<Entry> entry = ResolveIdentifier(identifier);
        if (!entry) {
            return Failure(SettingsErrorCode::staleEntry,
                           std::string(identifier));
        }
        return select(*entry);
    }

    [[nodiscard]] Result clearSelection() {
        if (!selected_) {
            return Success(false);
        }
        selected_.reset();
        return Success(true);
    }

    [[nodiscard]] Result setEnabled(Entry entry, bool enabled) {
        if (entry == Entry::primaryChats) {
            return Failure(SettingsErrorCode::fixedEntry,
                           std::string(Identifier(entry)));
        }
        if (!IsManagedEntry(entry)) {
            return Failure(SettingsErrorCode::unknownEntry);
        }
        if (draft_.isEnabled(entry) == enabled) {
            return Success(false);
        }
        draft_.setEnabled(entry, enabled);
        return Success(true, std::string(Identifier(entry)));
    }

    [[nodiscard]] Result setEnabled(std::string_view identifier, bool enabled) {
        const std::optional<Entry> entry = ResolveIdentifier(identifier);
        if (!entry) {
            return Failure(SettingsErrorCode::staleEntry,
                           std::string(identifier));
        }
        return setEnabled(*entry, enabled);
    }

    [[nodiscard]] Result setOrder(Group group,
                                  const std::vector<Entry> &newOrder) {
        const std::vector<Entry> current = order(group);
        const std::size_t expectedSize = GroupSize(group);
        if (expectedSize == 0) {
            return Failure(SettingsErrorCode::unknownEntry);
        }
        if (newOrder.size() != expectedSize) {
            return Failure(SettingsErrorCode::missingOrder);
        }
        std::vector<Entry> checked;
        checked.reserve(newOrder.size());
        for (Entry entry : newOrder) {
            if (entry == Entry::primaryChats) {
                return Failure(SettingsErrorCode::fixedEntry,
                               std::string(Identifier(entry)));
            }
            if (!IsManagedEntry(entry)) {
                return Failure(SettingsErrorCode::unknownEntry);
            }
            if (GroupOf(entry) != group) {
                return Failure(SettingsErrorCode::crossGroup,
                               std::string(Identifier(entry)));
            }
            if (std::find(checked.begin(), checked.end(), entry) !=
                checked.end()) {
                return Failure(SettingsErrorCode::duplicateOrder,
                               std::string(Identifier(entry)));
            }
            checked.push_back(entry);
        }

        if (current == checked) {
            return Success(false);
        }
        if (group == Group::primary) {
            auto replacement = checked.begin();
            for (Entry &entry : draft_.primaryOrder) {
                if (entry != Entry::primaryChats) {
                    entry = *replacement++;
                }
            }
        } else {
            draft_.secondaryOrder = std::move(checked);
        }
        return Success(true);
    }

    [[nodiscard]] Result moveToIndex(Entry entry, std::size_t targetIndex) {
        if (entry == Entry::primaryChats) {
            return Failure(SettingsErrorCode::fixedEntry,
                           std::string(Identifier(entry)));
        }
        if (!IsManagedEntry(entry)) {
            return Failure(SettingsErrorCode::unknownEntry);
        }
        return moveToIndex(GroupOf(entry), entry, targetIndex);
    }

    [[nodiscard]] Result moveToIndex(std::string_view identifier,
                                     std::size_t targetIndex) {
        const std::optional<Entry> entry = ResolveIdentifier(identifier);
        if (!entry) {
            return Failure(SettingsErrorCode::staleEntry,
                           std::string(identifier));
        }
        return moveToIndex(*entry, targetIndex);
    }

    [[nodiscard]] Result moveToIndex(Group group,
                                     Entry entry,
                                     std::size_t targetIndex) {
        if (entry == Entry::primaryChats) {
            return Failure(SettingsErrorCode::fixedEntry,
                           std::string(Identifier(entry)));
        }
        if (!IsManagedEntry(entry)) {
            return Failure(SettingsErrorCode::unknownEntry);
        }
        if (GroupOf(entry) != group) {
            return Failure(SettingsErrorCode::crossGroup,
                           std::string(Identifier(entry)));
        }

        if (entry == Entry::primaryDiscover) {
            // Managed for visibility only: WeChat always appends type 3 last,
            // so any position chosen here would be discarded natively.
            return Failure(SettingsErrorCode::fixedEntry,
                           std::string(Identifier(entry)));
        }
        const std::vector<Entry> current = sortableOrder(group);
        const auto found = std::find(current.begin(), current.end(), entry);
        if (found == current.end()) {
            return Failure(SettingsErrorCode::staleEntry,
                           std::string(Identifier(entry)));
        }
        if (targetIndex >= current.size()) {
            return Failure(SettingsErrorCode::outOfRange,
                           std::string(Identifier(entry)));
        }
        const std::size_t currentIndex =
            static_cast<std::size_t>(std::distance(current.begin(), found));
        if (currentIndex == targetIndex) {
            return Failure(SettingsErrorCode::noMove,
                           std::string(Identifier(entry)));
        }

        std::vector<Entry> next = current;
        next.erase(next.begin() + static_cast<std::ptrdiff_t>(currentIndex));
        next.insert(next.begin() + static_cast<std::ptrdiff_t>(targetIndex),
                    entry);
        Result result = setOrder(group, next);
        if (result.succeeded()) {
            result.identifier = std::string(Identifier(entry));
        }
        return result;
    }

    [[nodiscard]] Result moveUp(Entry entry) {
        if (!IsManagedEntry(entry)) {
            return Failure(SettingsErrorCode::unknownEntry);
        }
        const std::vector<Entry> current = order(GroupOf(entry));
        const auto found = std::find(current.begin(), current.end(), entry);
        if (found == current.end()) {
            return Failure(SettingsErrorCode::staleEntry,
                           std::string(Identifier(entry)));
        }
        if (found == current.begin()) {
            return Failure(SettingsErrorCode::noMove,
                           std::string(Identifier(entry)));
        }
        const std::size_t index =
            static_cast<std::size_t>(std::distance(current.begin(), found));
        return moveToIndex(entry, index - 1);
    }

    [[nodiscard]] Result moveDown(Entry entry) {
        if (!IsManagedEntry(entry)) {
            return Failure(SettingsErrorCode::unknownEntry);
        }
        const std::vector<Entry> current = order(GroupOf(entry));
        const auto found = std::find(current.begin(), current.end(), entry);
        if (found == current.end()) {
            return Failure(SettingsErrorCode::staleEntry,
                           std::string(Identifier(entry)));
        }
        const std::size_t index =
            static_cast<std::size_t>(std::distance(current.begin(), found));
        if (index + 1 >= current.size()) {
            return Failure(SettingsErrorCode::noMove,
                           std::string(Identifier(entry)));
        }
        return moveToIndex(entry, index + 1);
    }

    [[nodiscard]] Result dragDrop(Entry dragged,
                                  Group destinationGroup,
                                  std::size_t targetIndex) {
        return moveToIndex(destinationGroup, dragged, targetIndex);
    }

    [[nodiscard]] Result dragDrop(Entry dragged,
                                  Entry target,
                                  DropPosition position = DropPosition::before) {
        if (dragged == Entry::primaryChats || target == Entry::primaryChats) {
            return Failure(SettingsErrorCode::fixedEntry,
                           std::string(Identifier(Entry::primaryChats)));
        }
        if (!IsManagedEntry(dragged) || !IsManagedEntry(target)) {
            return Failure(SettingsErrorCode::unknownEntry);
        }
        if (GroupOf(dragged) != GroupOf(target)) {
            return Failure(SettingsErrorCode::crossGroup,
                           std::string(Identifier(dragged)));
        }
        if (dragged == target) {
            return Failure(SettingsErrorCode::noMove,
                           std::string(Identifier(dragged)));
        }
        const Group group = GroupOf(dragged);
        const std::vector<Entry> current = order(group);
        const auto draggedIt = std::find(current.begin(), current.end(), dragged);
        const auto targetIt = std::find(current.begin(), current.end(), target);
        if (draggedIt == current.end() || targetIt == current.end()) {
            return Failure(SettingsErrorCode::staleEntry);
        }
        std::size_t destination = static_cast<std::size_t>(
            std::distance(current.begin(), targetIt));
        if (position == DropPosition::after) {
            ++destination;
        }
        const std::size_t draggedIndex = static_cast<std::size_t>(
            std::distance(current.begin(), draggedIt));
        if (draggedIndex < destination) {
            --destination;
        }
        return moveToIndex(group, dragged, destination);
    }

    [[nodiscard]] Result dragDrop(std::string_view dragged,
                                  std::string_view target,
                                  DropPosition position = DropPosition::before) {
        const std::optional<Entry> draggedEntry = ResolveIdentifier(dragged);
        const std::optional<Entry> targetEntry = ResolveIdentifier(target);
        if (!draggedEntry || !targetEntry) {
            return Failure(SettingsErrorCode::staleEntry,
                           !draggedEntry ? std::string(dragged)
                                         : std::string(target));
        }
        return dragDrop(*draggedEntry, *targetEntry, position);
    }

    [[nodiscard]] Result drop(Entry dragged,
                              Entry target,
                              DropPosition position = DropPosition::before) {
        return dragDrop(dragged, target, position);
    }

    [[nodiscard]] Result reset() {
        const bool changed = draft_ != baseline_ || selected_ != baselineSelection_;
        if (!changed) {
            return Success(false);
        }
        draft_ = baseline_;
        selected_ = baselineSelection_;
        return Success(true);
    }

    [[nodiscard]] Result cancel() { return reset(); }

    [[nodiscard]] Result acceptSaved() {
        const bool changed = draft_ != baseline_ || selected_ != baselineSelection_;
        baseline_ = draft_;
        baselineSelection_ = selected_;
        return Success(changed);
    }

    [[nodiscard]] Result acceptSaved(const Configuration &saved) {
        Configuration normalized = saved;
        EnforceFixedProductEntries(normalized);
        const SettingsValidationResult validation = Validate(normalized);
        if (!validation.valid()) {
            return Failure(validation.code);
        }
        const bool changed = draft_ != normalized || baseline_ != normalized;
        draft_ = normalized;
        baseline_ = normalized;
        baselineSelection_ = selected_;
        return Success(changed);
    }

    [[nodiscard]] Result accept(const Configuration &saved) {
        return acceptSaved(saved);
    }

    [[nodiscard]] bool visibilityDirty() const noexcept {
        for (Entry entry : kAllEntries) {
            if (draft_.isEnabled(entry) != baseline_.isEnabled(entry)) {
                return true;
            }
        }
        return false;
    }

    [[nodiscard]] bool orderDirty() const noexcept {
        return draft_.primaryOrder != baseline_.primaryOrder ||
               draft_.secondaryOrder != baseline_.secondaryOrder;
    }

    [[nodiscard]] bool dirty() const noexcept {
        return visibilityDirty() || orderDirty();
    }

    [[nodiscard]] bool requiresRestart() const noexcept { return orderDirty(); }

private:
    static bool IsKnownEntry(Entry entry) noexcept {
        return std::find(kAllEntries.begin(), kAllEntries.end(), entry) !=
               kAllEntries.end();
    }

    static bool IsManagedEntry(Entry entry) noexcept {
        return IsKnownEntry(entry) && entry != Entry::primaryChats;
    }

    static std::optional<Entry> ResolveIdentifier(
        std::string_view identifier) noexcept {
        return EntryFromIdentifier(identifier);
    }

    static std::size_t GroupSize(Group group) noexcept {
        if (group == Group::primary) {
            return kCanonicalPrimaryOrder.size() - 1;
        }
        if (group == Group::secondary) {
            return kCanonicalSecondaryOrder.size();
        }
        return 0;
    }

    [[nodiscard]] std::vector<Entry> &OrderRef(Group group) noexcept {
        if (group == Group::primary) {
            return draft_.primaryOrder;
        }
        return draft_.secondaryOrder;
    }

    [[nodiscard]] const std::vector<Entry> &OrderRef(Group group) const noexcept {
        if (group == Group::primary) {
            return draft_.primaryOrder;
        }
        return draft_.secondaryOrder;
    }

    static Result Success(bool changed, std::string identifier = {}) {
        return {SettingsErrorCode::none, changed, std::move(identifier)};
    }

    static Result Failure(SettingsErrorCode code, std::string identifier = {}) {
        return {code, false, std::move(identifier)};
    }

    void AppendRows(Group group,
                    const std::vector<Entry> &order,
                    std::vector<Row> &output) const {
        for (std::size_t index = 0; index < order.size(); ++index) {
            const Entry entry = order[index];
            Row row;
            row.group = group;
            row.entry = entry;
            row.label = std::string(Label(entry));
            row.identifier = std::string(Identifier(entry));
            row.enabled = draft_.isEnabled(entry);
            row.selected = selected_ == entry;
            // The pinned 发现 tail row cannot move, and the row above it
            // cannot move down past it.
            const bool pinned = (entry == Entry::primaryDiscover);
            row.canMoveUp = !pinned && index > 0;
            row.canMoveDown = !pinned && index + 1 < order.size() &&
                              order[index + 1] != Entry::primaryDiscover;
            row.accessibilityIdentifier =
                std::string(AccessibilityIdentifier(entry));
            output.push_back(std::move(row));
        }
    }

    Configuration baseline_;
    Configuration draft_;
    std::optional<Entry> baselineSelection_;
    std::optional<Entry> selected_;
};

using SidebarSettingsDraft = SidebarSettingsModel;

}
