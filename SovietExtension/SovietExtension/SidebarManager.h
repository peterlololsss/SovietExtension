#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const YMNavigationSidebarStateDidChangeNotification;
FOUNDATION_EXPORT NSErrorDomain const YMNavigationSidebarErrorDomain;

typedef NS_ERROR_ENUM(YMNavigationSidebarErrorDomain,
                      YMNavigationSidebarErrorCode) {
    YMNavigationSidebarErrorInvalidConfiguration = 1,
    YMNavigationSidebarErrorPersistence = 2,
    YMNavigationSidebarErrorPrimaryFallback = 3,
    YMNavigationSidebarErrorPersistenceRollback = 4,
    YMNavigationSidebarErrorNativeApply = 5,
    YMNavigationSidebarErrorAllPrimaryDisabled = 6,
};

@interface SidebarManager : NSObject

@property (nonatomic, readonly, getter=isSupported) BOOL supported;
@property (nonatomic, readonly, getter=isReady) BOOL ready;
@property (nonatomic, readonly, getter=isPendingRestart) BOOL pendingRestart;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, id> *currentConfiguration;

+ (instancetype)sharedManager;
+ (void)start;
+ (void)registerDefaults;

- (BOOL)saveConfiguration:(NSDictionary<NSString *, id> *)configuration
                     error:(NSError * _Nullable * _Nullable)error;

- (BOOL)isEntryTypeEnabled:(NSInteger)entryType;
- (BOOL)setEntryStates:(NSDictionary<NSNumber *, NSNumber *> *)entryStates
                  error:(NSError * _Nullable * _Nullable)error;
- (BOOL)setEntryType:(NSInteger)entryType
              enabled:(BOOL)enabled
                error:(NSError * _Nullable * _Nullable)error;

@end

@interface YMSidebarSettingsDraft : NSObject {
@private
    void *_storage;
}

- (nullable instancetype)initWithConfiguration:
        (NSDictionary<NSString *, id> *)configuration
                                         error:
        (NSError * _Nullable * _Nullable)error;

@property(nonatomic, copy, readonly) NSDictionary<NSString *, id> *configuration;
@property(nonatomic, copy, readonly, nullable) NSString *selectedIdentifier;
@property(nonatomic, readonly, getter=isDirty) BOOL dirty;
@property(nonatomic, readonly, getter=isVisibilityDirty) BOOL visibilityDirty;
@property(nonatomic, readonly, getter=isOrderDirty) BOOL orderDirty;

- (NSArray<NSDictionary<NSString *, id> *> *)rowsForGroup:(NSString *)group;
- (BOOL)selectIdentifier:(NSString *)identifier
                    error:(NSError * _Nullable * _Nullable)error;
- (BOOL)setIdentifier:(NSString *)identifier
                enabled:(BOOL)enabled
                  error:(NSError * _Nullable * _Nullable)error;
- (BOOL)moveIdentifier:(NSString *)identifier
                 offset:(NSInteger)offset
                  error:(NSError * _Nullable * _Nullable)error;
- (BOOL)moveIdentifier:(NSString *)identifier
                 toIndex:(NSUInteger)index
                 inGroup:(NSString *)group
                   error:(NSError * _Nullable * _Nullable)error;
- (void)cancel;

@end

NS_ASSUME_NONNULL_END

#if defined(__cplusplus) && __cplusplus >= 202002L

#include "SidebarModel.h"

#include <new>
#include <string>

NS_ASSUME_NONNULL_BEGIN

namespace ym::sidebar::objc_bridge {

inline bool NSStringToString(NSString *value, std::string &output) {
    if (![value isKindOfClass:NSString.class]) {
        return false;
    }
    const char *bytes = value.UTF8String;
    if (bytes == nullptr) {
        return false;
    }
    output.assign(bytes,
                  [value lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
    return true;
}

inline NSString *String(std::string_view value) {
    NSString *string =
        [[NSString alloc] initWithBytes:value.data()
                                length:value.size()
                              encoding:NSUTF8StringEncoding];
    return string ?: @"";
}

inline bool NSNumberIsBoolean(id _Nullable value) {
    return value != nil &&
           CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID();
}

inline bool ParseConfiguration(NSDictionary<NSString *, id> *dictionary,
                               PropertyList &output) {
    if (![dictionary isKindOfClass:NSDictionary.class] ||
        dictionary.count != 4) {
        return false;
    }
    id version = dictionary[@"version"];
    id statesValue = dictionary[@"states"];
    id primaryValue = dictionary[@"primaryOrder"];
    id secondaryValue = dictionary[@"secondaryOrder"];
    if (![version isKindOfClass:NSNumber.class] || NSNumberIsBoolean(version) ||
        CFNumberIsFloatType((__bridge CFNumberRef)version) ||
        ![statesValue isKindOfClass:NSDictionary.class] ||
        ![primaryValue isKindOfClass:NSArray.class] ||
        ![secondaryValue isKindOfClass:NSArray.class]) {
        return false;
    }

    PropertyList parsed;
    parsed.version = [version longLongValue];
    NSDictionary *states = static_cast<NSDictionary *>(statesValue);
    for (id key in states) {
        id enabled = states[key];
        std::string identifier;
        if (!NSNumberIsBoolean(enabled) ||
            !NSStringToString(static_cast<NSString *>(key), identifier)) {
            return false;
        }
        parsed.states.emplace(std::move(identifier), [enabled boolValue]);
    }
    for (id rawIdentifier in static_cast<NSArray *>(primaryValue)) {
        std::string identifier;
        if (!NSStringToString(static_cast<NSString *>(rawIdentifier),
                              identifier)) {
            return false;
        }
        parsed.primaryOrder.push_back(std::move(identifier));
    }
    for (id rawIdentifier in static_cast<NSArray *>(secondaryValue)) {
        std::string identifier;
        if (!NSStringToString(static_cast<NSString *>(rawIdentifier),
                              identifier)) {
            return false;
        }
        parsed.secondaryOrder.push_back(std::move(identifier));
    }
    output = std::move(parsed);
    return true;
}

inline NSDictionary<NSString *, id> *FoundationConfiguration(
    const Configuration &configuration) {
    NSMutableDictionary<NSString *, NSNumber *> *states =
        [NSMutableDictionary dictionaryWithCapacity:kAllEntries.size()];
    for (Entry entry : kAllEntries) {
        states[String(Identifier(entry))] = @(configuration.isEnabled(entry));
    }
    NSMutableArray<NSString *> *primary =
        [NSMutableArray arrayWithCapacity:configuration.primaryOrder.size()];
    for (Entry entry : configuration.primaryOrder) {
        [primary addObject:String(Identifier(entry))];
    }
    NSMutableArray<NSString *> *secondary =
        [NSMutableArray arrayWithCapacity:configuration.secondaryOrder.size()];
    for (Entry entry : configuration.secondaryOrder) {
        [secondary addObject:String(Identifier(entry))];
    }
    return @{
        @"version" : @(Configuration::kVersion),
        @"states" : [states copy],
        @"primaryOrder" : [primary copy],
        @"secondaryOrder" : [secondary copy],
    };
}

inline NSError *Error(SettingsErrorCode code,
                      NSString * _Nullable identifier = nil) {
    NSString *message = @"侧边栏配置无效，修改未保存。";
    YMNavigationSidebarErrorCode managerCode =
        YMNavigationSidebarErrorInvalidConfiguration;
    switch (code) {
        case SettingsErrorCode::none:
            break;
        case SettingsErrorCode::allPrimaryDisabled:
        case SettingsErrorCode::cannotDisableLastPrimary:
            managerCode = YMNavigationSidebarErrorAllPrimaryDisabled;
            message = @"至少保留一个主要入口。";
            break;
        case SettingsErrorCode::crossGroup:
            message = @"入口只能在当前分组内排序。";
            break;
        case SettingsErrorCode::unknownEntry:
        case SettingsErrorCode::staleEntry:
            message = @"拖放内容无效，排序未更改。";
            break;
        case SettingsErrorCode::outOfRange:
            message = @"拖放位置无效，排序未更改。";
            break;
        case SettingsErrorCode::noMove:
            message = @"该入口已经在边界位置。";
            break;
        case SettingsErrorCode::invalidSelection:
            message = @"请先选择要移动的入口。";
            break;
        case SettingsErrorCode::fixedEntry:
            message = @"聊天入口由微信管理，不能在这里修改。";
            break;
        case SettingsErrorCode::invalidConfiguration:
        case SettingsErrorCode::duplicateOrder:
        case SettingsErrorCode::missingOrder:
            break;
    }
    NSMutableDictionary<NSString *, id> *userInfo =
        [NSMutableDictionary dictionaryWithObject:message
                                           forKey:NSLocalizedDescriptionKey];
    if (identifier.length > 0) {
        userInfo[@"entryIdentifier"] = identifier;
    }
    return [NSError errorWithDomain:YMNavigationSidebarErrorDomain
                               code:managerCode
                           userInfo:userInfo];
}

inline void SetError(NSError * _Nullable * _Nullable error,
                     const SettingsOperationResult &result) {
    if (error != nullptr) {
        *error = result.succeeded()
            ? nil
            : Error(result.code, String(result.identifier));
    }
}

inline SidebarSettingsModel *Model(void *storage) {
    return static_cast<SidebarSettingsModel *>(storage);
}

inline std::optional<Group> ParseGroup(NSString *group) {
    if ([group isEqualToString:@"primary"]) {
        return Group::primary;
    }
    if ([group isEqualToString:@"secondary"]) {
        return Group::secondary;
    }
    return std::nullopt;
}

}

@implementation YMSidebarSettingsDraft

- (nullable instancetype)initWithConfiguration:
                    (NSDictionary<NSString *, id> *)configuration
                                 error:
                    (NSError * _Nullable * _Nullable)error {
    self = [super init];
    if (self == nil) {
        return nil;
    }
    ym::sidebar::PropertyList propertyList;
    if (!ym::sidebar::objc_bridge::ParseConfiguration(configuration,
                                                       propertyList)) {
        if (error != nullptr) {
            *error = ym::sidebar::objc_bridge::Error(
                ym::sidebar::SettingsErrorCode::invalidConfiguration);
        }
        return nil;
    }
    const ym::sidebar::ValidationResult validation =
        ym::sidebar::ValidateSaveInput(propertyList);
    if (validation.configuration() == nullptr) {
        if (error != nullptr) {
            *error = ym::sidebar::objc_bridge::Error(
                validation.error() != nullptr &&
                        validation.error()->code ==
                            ym::sidebar::ValidationErrorCode::allPrimaryDisabled
                    ? ym::sidebar::SettingsErrorCode::allPrimaryDisabled
                    : ym::sidebar::SettingsErrorCode::invalidConfiguration);
        }
        return nil;
    }
    _storage = new (std::nothrow)
        ym::sidebar::SidebarSettingsModel(*validation.configuration());
    if (_storage == nullptr) {
        if (error != nullptr) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                         code:NSFileWriteOutOfSpaceError
                                     userInfo:@{
                                         NSLocalizedDescriptionKey :
                                             @"无法创建侧边栏设置草稿。",
                                     }];
        }
        return nil;
    }
    if (error != nullptr) {
        *error = nil;
    }
    return self;
}

- (void)dealloc {
    delete ym::sidebar::objc_bridge::Model(_storage);
}

- (NSDictionary<NSString *, id> *)configuration {
    return ym::sidebar::objc_bridge::FoundationConfiguration(
        ym::sidebar::objc_bridge::Model(_storage)->configuration());
}

- (NSString * _Nullable)selectedIdentifier {
    const std::optional<ym::sidebar::Entry> selected =
        ym::sidebar::objc_bridge::Model(_storage)->selectedEntry();
    return selected ? ym::sidebar::objc_bridge::String(
                          ym::sidebar::Identifier(*selected))
                    : nil;
}

- (BOOL)isDirty {
    return ym::sidebar::objc_bridge::Model(_storage)->dirty();
}

- (BOOL)isVisibilityDirty {
    return ym::sidebar::objc_bridge::Model(_storage)->visibilityDirty();
}

- (BOOL)isOrderDirty {
    return ym::sidebar::objc_bridge::Model(_storage)->orderDirty();
}

- (NSArray<NSDictionary<NSString *, id> *> *)rowsForGroup:(NSString *)group {
    const std::optional<ym::sidebar::Group> parsedGroup =
        ym::sidebar::objc_bridge::ParseGroup(group);
    if (!parsedGroup) {
        return @[];
    }
    NSMutableArray<NSDictionary<NSString *, id> *> *rows =
        [NSMutableArray array];
    const std::vector<ym::sidebar::SettingsRow> modelRows =
        ym::sidebar::objc_bridge::Model(_storage)->rows();
    NSUInteger position = 0;
    for (const ym::sidebar::SettingsRow &row : modelRows) {
        if (row.group != *parsedGroup) {
            continue;
        }
        ++position;
        [rows addObject:@{
            @"group" : group,
            @"identifier" : ym::sidebar::objc_bridge::String(row.identifier),
            @"title" : ym::sidebar::objc_bridge::String(row.label),
            @"enabled" : @(row.enabled),
            @"selected" : @(row.selected),
            @"canMoveUp" : @(row.canMoveUp),
            @"canMoveDown" : @(row.canMoveDown),
            @"position" : @(position),
        }];
    }
    return [rows copy];
}

- (BOOL)selectIdentifier:(NSString *)identifier
                    error:(NSError * _Nullable * _Nullable)error {
    std::string value;
    if (!ym::sidebar::objc_bridge::NSStringToString(identifier, value)) {
        if (error != nullptr) {
            *error = ym::sidebar::objc_bridge::Error(
                ym::sidebar::SettingsErrorCode::staleEntry);
        }
        return NO;
    }
    const ym::sidebar::SettingsOperationResult result =
        ym::sidebar::objc_bridge::Model(_storage)->select(value);
    ym::sidebar::objc_bridge::SetError(error, result);
    return result.succeeded();
}

- (BOOL)setIdentifier:(NSString *)identifier
                enabled:(BOOL)enabled
                  error:(NSError * _Nullable * _Nullable)error {
    std::string value;
    if (!ym::sidebar::objc_bridge::NSStringToString(identifier, value)) {
        if (error != nullptr) {
            *error = ym::sidebar::objc_bridge::Error(
                ym::sidebar::SettingsErrorCode::staleEntry);
        }
        return NO;
    }
    const ym::sidebar::SettingsOperationResult result =
        ym::sidebar::objc_bridge::Model(_storage)->setEnabled(value, enabled);
    ym::sidebar::objc_bridge::SetError(error, result);
    return result.succeeded();
}

- (BOOL)moveIdentifier:(NSString *)identifier
                 offset:(NSInteger)offset
                  error:(NSError * _Nullable * _Nullable)error {
    std::string value;
    if (!ym::sidebar::objc_bridge::NSStringToString(identifier, value)) {
        if (error != nullptr) {
            *error = ym::sidebar::objc_bridge::Error(
                ym::sidebar::SettingsErrorCode::staleEntry);
        }
        return NO;
    }
    const std::optional<ym::sidebar::Entry> entry =
        ym::sidebar::EntryFromIdentifier(value);
    if (!entry || (offset != -1 && offset != 1)) {
        if (error != nullptr) {
            *error = ym::sidebar::objc_bridge::Error(
                ym::sidebar::SettingsErrorCode::invalidSelection);
        }
        return NO;
    }
    ym::sidebar::SidebarSettingsModel *model =
        ym::sidebar::objc_bridge::Model(_storage);
    const ym::sidebar::SettingsOperationResult result =
        offset < 0 ? model->moveUp(*entry) : model->moveDown(*entry);
    ym::sidebar::objc_bridge::SetError(error, result);
    return result.succeeded();
}

- (BOOL)moveIdentifier:(NSString *)identifier
                 toIndex:(NSUInteger)index
                 inGroup:(NSString *)group
                   error:(NSError * _Nullable * _Nullable)error {
    std::string value;
    const std::optional<ym::sidebar::Group> parsedGroup =
        ym::sidebar::objc_bridge::ParseGroup(group);
    if (!parsedGroup ||
        !ym::sidebar::objc_bridge::NSStringToString(identifier, value)) {
        if (error != nullptr) {
            *error = ym::sidebar::objc_bridge::Error(
                ym::sidebar::SettingsErrorCode::staleEntry);
        }
        return NO;
    }
    const std::optional<ym::sidebar::Entry> entry =
        ym::sidebar::EntryFromIdentifier(value);
    if (!entry) {
        if (error != nullptr) {
            *error = ym::sidebar::objc_bridge::Error(
                ym::sidebar::SettingsErrorCode::staleEntry);
        }
        return NO;
    }
    const ym::sidebar::SettingsOperationResult result =
        ym::sidebar::objc_bridge::Model(_storage)->moveToIndex(
            *parsedGroup, *entry, index);
    ym::sidebar::objc_bridge::SetError(error, result);
    return result.succeeded();
}

- (void)cancel {
    static_cast<void>(ym::sidebar::objc_bridge::Model(_storage)->cancel());
}

@end

NS_ASSUME_NONNULL_END

#endif
