#import <Foundation/Foundation.h>

#include <cstddef>
#include <cstdint>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SidebarPatchIntegrityFailure) {
    SidebarPatchIntegrityFailureNone = 0,
    SidebarPatchIntegrityFailureInvalidInput,
    SidebarPatchIntegrityFailureImageNotFound,
    SidebarPatchIntegrityFailureImageAmbiguous,
    SidebarPatchIntegrityFailureWrongPath,
    SidebarPatchIntegrityFailureOpen,
    SidebarPatchIntegrityFailureStat,
    SidebarPatchIntegrityFailureClose,
    SidebarPatchIntegrityFailureNotRegularFile,
    SidebarPatchIntegrityFailureRead,
    SidebarPatchIntegrityFailureHash,
    SidebarPatchIntegrityFailureSHAMismatch,
    SidebarPatchIntegrityFailurePathReplaced,
    SidebarPatchIntegrityFailureIdentityMismatch,
    SidebarPatchIntegrityFailureUUIDMismatch,
    SidebarPatchIntegrityFailureImageBounds,
    SidebarPatchIntegrityFailureUnreadableRange,
    SidebarPatchIntegrityFailurePatchBytes,
    SidebarPatchIntegrityFailureCallBytes,
    SidebarPatchIntegrityFailureInstallAttemptReuse,
};

typedef struct {
    uint64_t device;
    uint64_t inode;
    uint64_t size;
    int64_t mtimeSeconds;
    int64_t mtimeNanoseconds;
    uint32_t mode;
} YMSidebarPatchFileIdentity;

typedef struct {
    void *context;
    int (*openReadOnlyNoFollow)(void *context, const char *path);
    bool (*statDescriptor)(void *context,
                           int descriptor,
                           YMSidebarPatchFileIdentity *identity);
    std::ptrdiff_t (*readDescriptor)(void *context,
                                     int descriptor,
                                     uint8_t *destination,
                                     std::size_t capacity);
    int (*closeDescriptor)(void *context, int descriptor);
} YMSidebarPatchFileOperations;

typedef struct {
    const char *path;
    uintptr_t headerAddress;
    intptr_t slide;
    uintptr_t imageStart;
    std::size_t imageSize;
} YMSidebarPatchLoadedImage;

typedef bool (*YMSidebarPatchMemoryReader)(void *context,
                                                    uintptr_t address,
                                                    uint8_t *destination,
                                                    std::size_t length);

typedef struct {
    const YMSidebarPatchLoadedImage *images;
    std::size_t imageCount;
    const char *bundleIdentifier;
    const char *shortVersion;
    const char *buildVersion;
    const char *architecture;
    uint64_t installAttempt;
    YMSidebarPatchMemoryReader memoryReader;
    void *memoryReaderContext;
} YMSidebarPatchPreflightInput;

@interface SidebarPatchPreflightReceipt : NSObject <NSCopying>
+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
@property(nonatomic, readonly, copy) NSString *path;
@property(nonatomic, readonly) YMSidebarPatchFileIdentity fileIdentity;
@property(nonatomic, readonly, copy) NSString *fileSHA256;
@property(nonatomic, readonly) uintptr_t headerAddress;
@property(nonatomic, readonly) intptr_t slide;
@property(nonatomic, readonly) uintptr_t imageStart;
@property(nonatomic, readonly) NSUInteger imageSize;
@property(nonatomic, readonly, copy) NSString *guardSHA256;
@property(nonatomic, readonly) uint64_t installAttempt;
@property(nonatomic, readonly) NSUInteger patchGuardCount;
@property(nonatomic, readonly) NSUInteger callGuardCount;
@end

typedef struct {
    SidebarPatchIntegrityFailure failure;
    SidebarPatchPreflightReceipt * _Nullable receipt;
} YMSidebarPatchPreflightResult;

@interface SidebarPatchIntegrity : NSObject
- (instancetype)init;
- (instancetype)initWithFileOperations:
    (YMSidebarPatchFileOperations)operations NS_DESIGNATED_INITIALIZER;
- (YMSidebarPatchPreflightResult)verify:
    (const YMSidebarPatchPreflightInput *)input;
@end

FOUNDATION_EXPORT YMSidebarPatchFileOperations
YMSidebarPatchSystemFileOperations(void);

FOUNDATION_EXPORT NSString *YMSidebarPatchFailureName(
    SidebarPatchIntegrityFailure failure);

NS_ASSUME_NONNULL_END
