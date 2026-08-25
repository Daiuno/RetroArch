////
////  CheevosBridge.m
////  CheevosBridge
////
////  Created by Daiuno on 2025/8/13.
////  Copyright © 2025 Manic EMU. All rights reserved.
////

#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#import "CheevosBridge.h"
// 必须在包含 rc_client.h 之前定义
#define RC_CLIENT_SUPPORTS_HASH 1

#import "deps/rcheevos/include/rc_client.h"
#import "cheevos/cheevos.h"

@interface CheevosLoginCtx : NSObject
@property (nonatomic, copy) LoginCompletion block;
@end

@implementation CheevosLoginCtx
@end

@interface CheevosGameInfoCtx : NSObject
@property (nonatomic, copy) GetGameInfoCompletion block;
@property (nonatomic, copy) NSString *path;
@end

@implementation CheevosGameInfoCtx
@end

@implementation CheevosSubset

+ (BOOL)supportsSecureCoding { return YES; }

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeInteger:self._id forKey:@"id"];
    [coder encodeObject:self.title forKey:@"title"];
    [coder encodeObject:self.badgeName forKey:@"badgeName"];
    [coder encodeObject:self.badgeUrl forKey:@"badgeUrl"];
    [coder encodeInteger:self.numAchievements forKey:@"numAchievements"];
    [coder encodeBool:self.isCore forKey:@"isCore"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (!self) {
        return nil;
    }
    self._id = [coder decodeIntegerForKey:@"id"];
    self.title = [coder decodeObjectOfClass:[NSString class] forKey:@"title"];
    self.badgeName = [coder decodeObjectOfClass:[NSString class] forKey:@"badgeName"];
    self.badgeUrl = [coder decodeObjectOfClass:[NSString class] forKey:@"badgeUrl"];
    self.numAchievements = [coder decodeIntegerForKey:@"numAchievements"];
    self.isCore = [coder decodeBoolForKey:@"isCore"];
    return self;
}

@end

@implementation CheevosAchievement

+ (BOOL)supportsSecureCoding { return YES; }

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.title forKey:@"title"];
    [coder encodeObject:self._description forKey:@"description"];
    [coder encodeObject:self.badgeName forKey:@"badgeName"];
    [coder encodeObject:self.measuredProgress forKey:@"measuredProgress"];
    [coder encodeDouble:self.measuredPercent forKey:@"measuredPercent"];
    [coder encodeInteger:self._id forKey:@"id"];
    [coder encodeInteger:self.points forKey:@"points"];
    [coder encodeObject:self.unlockTime forKey:@"unlockTime"];
    [coder encodeInteger:self.state forKey:@"state"];
    [coder encodeInteger:self.category forKey:@"category"];
    [coder encodeInteger:self.bucket forKey:@"bucket"];
    [coder encodeBool:self.unlocked forKey:@"unlocked"];
    [coder encodeBool:self.hardcoreUnlocked forKey:@"hardcoreUnlocked"];
    [coder encodeBool:self.softcoreUnlocked forKey:@"softcoreUnlocked"];
    [coder encodeDouble:self.rarity forKey:@"rarity"];
    [coder encodeDouble:self.rarityHardcore forKey:@"rarityHardcore"];
    [coder encodeInteger:self.type forKey:@"type"];
    [coder encodeObject:self.unlockedBadgeUrl forKey:@"unlockedBadgeUrl"];
    [coder encodeObject:self.activeBadgeUrl forKey:@"activeBadgeUrl"];
    [coder encodeBool:self.isMissable forKey:@"isMissable"];
    [coder encodeBool:self.isProgression forKey:@"isProgression"];
    [coder encodeInteger:self.subsetId forKey:@"subsetId"];
    [coder encodeObject:self.subsetTitle forKey:@"subsetTitle"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (!self) {
        return nil;
    }
    self.title = [coder decodeObjectOfClass:[NSString class] forKey:@"title"];
    self._description = [coder decodeObjectOfClass:[NSString class] forKey:@"description"];
    self.badgeName = [coder decodeObjectOfClass:[NSString class] forKey:@"badgeName"];
    self.measuredProgress = [coder decodeObjectOfClass:[NSString class] forKey:@"measuredProgress"];
    self.measuredPercent = [coder decodeDoubleForKey:@"measuredPercent"];
    self._id = [coder decodeIntegerForKey:@"id"];
    self.points = [coder decodeIntegerForKey:@"points"];
    self.unlockTime = [coder decodeObjectOfClass:[NSDate class] forKey:@"unlockTime"];
    self.state = [coder decodeIntegerForKey:@"state"];
    self.category = [coder decodeIntegerForKey:@"category"];
    self.bucket = [coder decodeIntegerForKey:@"bucket"];
    self.unlocked = [coder decodeBoolForKey:@"unlocked"];
    self.hardcoreUnlocked = [coder decodeBoolForKey:@"hardcoreUnlocked"];
    self.softcoreUnlocked = [coder decodeBoolForKey:@"softcoreUnlocked"];
    self.rarity = [coder decodeDoubleForKey:@"rarity"];
    self.rarityHardcore = [coder decodeDoubleForKey:@"rarityHardcore"];
    self.type = [coder decodeIntegerForKey:@"type"];
    self.unlockedBadgeUrl = [coder decodeObjectOfClass:[NSString class] forKey:@"unlockedBadgeUrl"];
    self.activeBadgeUrl = [coder decodeObjectOfClass:[NSString class] forKey:@"activeBadgeUrl"];
    self.isMissable = [coder decodeBoolForKey:@"isMissable"];
    self.isProgression = [coder decodeBoolForKey:@"isProgression"];
    self.subsetId = [coder decodeIntegerForKey:@"subsetId"];
    self.subsetTitle = [coder decodeObjectOfClass:[NSString class] forKey:@"subsetTitle"];
    return self;
}

@end

@implementation CheevosGame

+ (BOOL)supportsSecureCoding { return YES; }

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.title forKey:@"title"];
    [coder encodeObject:self._hash forKey:@"hash"];
    [coder encodeObject:self.badgeName forKey:@"badgeName"];
    [coder encodeInteger:self._id forKey:@"id"];
    [coder encodeInteger:self.console_id forKey:@"console_id"];
    [coder encodeObject:self.achievements forKey:@"achievements"];
    [coder encodeObject:self.subsets forKey:@"subsets"];
    [coder encodeObject:self.badgeUrl forKey:@"badgeUrl"];
    [coder encodeBool:self.notSupportHardcore forKey:@"notSupportHardcore"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (!self) {
        return nil;
    }
    self.title = [coder decodeObjectOfClass:[NSString class] forKey:@"title"];
    self._hash = [coder decodeObjectOfClass:[NSString class] forKey:@"hash"];
    self.badgeName = [coder decodeObjectOfClass:[NSString class] forKey:@"badgeName"];
    self._id = [coder decodeIntegerForKey:@"id"];
    self.console_id = [coder decodeIntegerForKey:@"console_id"];
    self.achievements = [coder decodeArrayOfObjectsOfClass:[CheevosAchievement class] forKey:@"achievements"];
    self.subsets = [coder decodeArrayOfObjectsOfClass:[CheevosSubset class] forKey:@"subsets"];
    self.badgeUrl = [coder decodeObjectOfClass:[NSString class] forKey:@"badgeUrl"];
    self.notSupportHardcore = [coder decodeBoolForKey:@"notSupportHardcore"];
    return self;
}

@end

@implementation CheevosUser
@end

@implementation CheevosSummary
@end

@implementation CheevosCompletion
@end

@implementation CheevosLeaderboardTracker
@end

@implementation CheevosLeaderboard
@end

@interface CheevosGameCacheRecord : NSObject <NSSecureCoding>
@property (nonatomic, strong) NSDate *savedAt;
@property (nonatomic, strong) CheevosGame *game;
@end

@implementation CheevosGameCacheRecord

+ (BOOL)supportsSecureCoding { return YES; }

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.savedAt forKey:@"savedAt"];
    [coder encodeObject:self.game forKey:@"game"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (!self) {
        return nil;
    }
    self.savedAt = [coder decodeObjectOfClass:[NSDate class] forKey:@"savedAt"];
    self.game = [coder decodeObjectOfClass:[CheevosGame class] forKey:@"game"];
    return self;
}

@end

@implementation CheevosBridge

#pragma mark - HTTP Server Call Implementation

// 实现 rcheevos_client_server_call 函数
static void rcheevos_client_server_call(const rc_api_request_t* request,
                                      rc_client_server_callback_t callback,
                                      void* callback_data,
                                      rc_client_t* client) {
    
    if (!request || !callback) {
        return;
    }
    
    // 创建 NSURL
    NSURL *url = [NSURL URLWithString:[NSString stringWithUTF8String:request->url]];
    if (!url) {
        // 创建空的响应
        rc_api_server_response_t response = {0};
        callback(&response, callback_data);
        return;
    }
    
    // 创建请求
    NSMutableURLRequest *urlRequest = [NSMutableURLRequest requestWithURL:url];
    
    if (request->post_data && request->post_data[0]) {
        // POST 请求
        urlRequest.HTTPMethod = @"POST";
        urlRequest.HTTPBody = [NSData dataWithBytes:request->post_data
                                            length:strlen(request->post_data)];
        [urlRequest setValue:@"application/x-www-form-urlencoded"
          forHTTPHeaderField:@"Content-Type"];
    } else {
        // GET 请求
        urlRequest.HTTPMethod = @"GET";
    }
    
    // 设置 User-Agent
    NSString *userAgent = [NSString stringWithFormat:@"ManicEMU/%@", g_appVersion];
    [urlRequest setValue:userAgent forHTTPHeaderField:@"User-Agent"];
    
    // 创建 NSURLSession 任务
    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:urlRequest
                                           completionHandler:^(NSData *data,
                                                              NSURLResponse *response,
                                                              NSError *error) {
        
        // 创建 rcheevos 响应结构
        rc_api_server_response_t server_response = {0};
        
        if (error) {
            // 网络错误
            server_response.http_status_code = -1;
            NSLog(@"\n<<CheevosBridge>>url:%@ error:%@\n", url.absoluteString, error.localizedDescription);
        } else {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            server_response.http_status_code = (int)httpResponse.statusCode;
            
            if (data && data.length > 0) {
                // 复制响应数据
                char *body = malloc(data.length + 1);
                if (body) {
                    memcpy(body, data.bytes, data.length);
                    body[data.length] = '\0';
                    server_response.body = body;
                    server_response.body_length = data.length;
                }
            }
            printf("\n\n<<CheevosBridge>>url:%s data:%s\n\n", [url.absoluteString cStringUsingEncoding:NSUTF8StringEncoding], [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] cStringUsingEncoding:NSUTF8StringEncoding]);
        }
        
        // 在主线程调用回调
        dispatch_async(dispatch_get_main_queue(), ^{
            callback(&server_response, callback_data);
            
            // 清理响应数据
            if (server_response.body) {
                free((void*)server_response.body);
            }
        });
    }];
    
    [task resume];
}

#pragma mark - Internals

static uint32_t dummy_read_memory(uint32_t address, uint8_t* buffer, uint32_t num_bytes, rc_client_t* client) {
    (void)address; (void)buffer; (void)num_bytes; (void)client;
    return 0;
}

static const NSTimeInterval kCheevosGameCacheTTL = 24.0 * 60.0 * 60.0;

static NSCache<NSString *, CheevosGame *> *gameInfoMemoryCache(void) {
    static NSCache<NSString *, CheevosGame *> *cache = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [NSCache new];
        cache.countLimit = 32;
        cache.name = @"CheevosGameInfo";
    });
    return cache;
}

static dispatch_queue_t gameInfoDiskQueue(void) {
    static dispatch_queue_t queue = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("com.aoshuang.manicemu.cheevos.game-cache", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static NSString *cacheKeyForPath(NSString *path) {
    const char *bytes = path.UTF8String ?: "";
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(bytes, (CC_LONG)strlen(bytes), digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [hex appendFormat:@"%02x", digest[i]];
    }
    return hex;
}

static NSURL *gameInfoCacheDirectoryURL(void) {
    NSURL *caches = [[NSFileManager defaultManager] URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *dir = [caches URLByAppendingPathComponent:@"CheevosGameInfo" isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

static NSURL *gameInfoCacheFileURL(NSString *path) {
    return [gameInfoCacheDirectoryURL() URLByAppendingPathComponent:[cacheKeyForPath(path) stringByAppendingPathExtension:@"archive"]];
}

static NSSet<Class> *gameInfoCacheAllowedClasses(void) {
    return [NSSet setWithObjects:[CheevosGameCacheRecord class], [CheevosGame class],
            [CheevosSubset class], [CheevosAchievement class], [NSArray class],
            [NSString class], [NSDate class], [NSNumber class], nil];
}

static CheevosGame *loadGameInfoFromDisk(NSString *path) {
    NSURL *fileURL = gameInfoCacheFileURL(path);
    NSData *data = [NSData dataWithContentsOfURL:fileURL];
    if (!data) {
        return nil;
    }
    NSError *error = nil;
    CheevosGameCacheRecord *record = [NSKeyedUnarchiver unarchivedObjectOfClasses:gameInfoCacheAllowedClasses()
                                                                         fromData:data
                                                                            error:&error];
    if (![record isKindOfClass:[CheevosGameCacheRecord class]] || !record.game || !record.savedAt) {
        [[NSFileManager defaultManager] removeItemAtURL:fileURL error:nil];
        return nil;
    }
    if ([[NSDate date] timeIntervalSinceDate:record.savedAt] > kCheevosGameCacheTTL) {
        [[NSFileManager defaultManager] removeItemAtURL:fileURL error:nil];
        return nil;
    }
    return record.game;
}

static void writeGameInfoToDisk(NSString *path, CheevosGame *game) {
    CheevosGameCacheRecord *record = [CheevosGameCacheRecord new];
    record.savedAt = [NSDate date];
    record.game = game;
    NSError *error = nil;
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:record requiringSecureCoding:YES error:&error];
    if (!data) {
        return;
    }
    [data writeToURL:gameInfoCacheFileURL(path) atomically:YES];
}

static void cacheGameInfo(NSString *path, CheevosGame *game) {
    if (path.length == 0 || !game) {
        return;
    }
    [gameInfoMemoryCache() setObject:game forKey:path];
    dispatch_async(gameInfoDiskQueue(), ^{
        writeGameInfoToDisk(path, game);
    });
}

static CheevosGame *cachedGameInfo(NSString *path) {
    if (path.length == 0) {
        return nil;
    }
    CheevosGame *memory = [gameInfoMemoryCache() objectForKey:path];
    if (memory) {
        return memory;
    }
    CheevosGame *disk = loadGameInfoFromDisk(path);
    if (disk) {
        [gameInfoMemoryCache() setObject:disk forKey:path];
    }
    return disk;
}

static void clearGameInfoCache(void) {
    [gameInfoMemoryCache() removeAllObjects];
    dispatch_async(gameInfoDiskQueue(), ^{
        NSURL *dir = gameInfoCacheDirectoryURL();
        [[NSFileManager defaultManager] removeItemAtURL:dir error:nil];
        [[NSFileManager defaultManager] createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
    });
}

static rc_client_t* ensure_client(void) {
    static rc_client_t* client = NULL;
    if (!client) {
        client = rc_client_create(dummy_read_memory, rcheevos_client_server_call);
        rc_client_enable_logging(client, RC_CLIENT_LOG_LEVEL_VERBOSE, NULL);
        rc_client_set_host(client, "https://retroachievements.org");
    }
    return client;
}

static CheevosUser* buildUserObj(const rc_client_user_t* u) {
    if (!u) return nil;
    CheevosUser* user = [CheevosUser new];
    user.displayName = u->display_name ? [NSString stringWithUTF8String:u->display_name] : nil;
    user.userName    = u->username ? [NSString stringWithUTF8String:u->username] : nil;
    user.token       = u->token ? [NSString stringWithUTF8String:u->token] : nil;
    user.score       = (NSInteger)u->score;
    user.softcoreScore = (NSInteger)u->score_softcore;
    user.password = g_password;
    return user;
}

static CheevosAchievement* buildAchievementObj(const rc_client_achievement_t* a) {
    if (!a) return nil;
    CheevosAchievement* obj = [CheevosAchievement new];
    obj.title = a->title ? [NSString stringWithUTF8String:a->title] : nil;
    obj._description = a->description ? [NSString stringWithUTF8String:a->description] : nil;
    obj.badgeName = [NSString stringWithUTF8String:a->badge_name];
    obj.measuredProgress = [NSString stringWithUTF8String:a->measured_progress];
    obj.measuredPercent = (CGFloat)a->measured_percent;
    obj._id = (NSInteger)a->id;
    obj.points = (NSInteger)a->points;
    obj.unlockTime = (a->unlock_time ? [NSDate dateWithTimeIntervalSince1970:a->unlock_time] : nil);
    obj.state = (NSInteger)a->state;
    obj.category = (NSInteger)a->state;
    obj.bucket = (NSInteger)a->bucket;
    if (a->unlocked & RC_CLIENT_ACHIEVEMENT_UNLOCKED_HARDCORE) {
        obj.hardcoreUnlocked = YES;
    }
    if (a->unlocked & RC_CLIENT_ACHIEVEMENT_UNLOCKED_SOFTCORE) {
        obj.softcoreUnlocked = YES;
    }
    obj.unlocked = (a->unlocked != RC_CLIENT_ACHIEVEMENT_UNLOCKED_NONE);
    obj.rarity = (CGFloat)a->rarity;
    obj.rarityHardcore = (CGFloat)a->rarity_hardcore;
    obj.type = (NSInteger)a->type;
    if (a->type & RC_CLIENT_ACHIEVEMENT_TYPE_MISSABLE) {
        obj.isMissable = YES;
    }
    if (a->type & RC_CLIENT_ACHIEVEMENT_TYPE_PROGRESSION) {
        obj.isProgression = YES;
    }
    if (a->badge_url && a->badge_url[0]) {
        obj.unlockedBadgeUrl = [NSString stringWithUTF8String:a->badge_url];
    } else {
        char url1[256];
        if (rc_client_achievement_get_image_url(a, RC_CLIENT_ACHIEVEMENT_STATE_UNLOCKED, url1, sizeof(url1)) == RC_OK) {
            obj.unlockedBadgeUrl = [NSString stringWithCString:url1 encoding:NSUTF8StringEncoding];
        }
    }
    if (a->badge_locked_url && a->badge_locked_url[0]) {
        obj.activeBadgeUrl = [NSString stringWithUTF8String:a->badge_locked_url];
    } else {
        char url2[256];
        if (rc_client_achievement_get_image_url(a, RC_CLIENT_ACHIEVEMENT_STATE_ACTIVE, url2, sizeof(url2)) == RC_OK) {
            obj.activeBadgeUrl = [NSString stringWithCString:url2 encoding:NSUTF8StringEncoding];
        }
    }
    return obj;
}

static CheevosGame* buildGameObj(rc_client_t* client) {
    const rc_client_game_t* g = rc_client_get_game_info(client);
    if (!g) return nil;

    CheevosGame* game = [CheevosGame new];
    game.title = g->title ? [NSString stringWithUTF8String:g->title] : nil;
    if ([game.title isEqualToString:@"Unsupported Game Version"]) {
        return nil;
    }
    game._hash = g->hash ? [NSString stringWithUTF8String:g->hash] : nil;
    game.badgeName = g->badge_name ? [NSString stringWithUTF8String:g->badge_name] : nil;
    game._id = (NSInteger)g->id;
    game.console_id = (NSInteger)g->console_id;

    NSMutableArray<CheevosSubset*>* subsetArr = [NSMutableArray array];
    NSMutableDictionary<NSNumber*, CheevosSubset*>* subsetById = [NSMutableDictionary dictionary];
    rc_client_subset_list_t* subset_list = rc_client_create_subset_list(client);
    if (subset_list) {
        for (uint32_t i = 0; i < subset_list->num_subsets; i++) {
            const rc_client_subset_t* s = subset_list->subsets[i];
            if (!s) {
                continue;
            }
            CheevosSubset* obj = [CheevosSubset new];
            obj._id = (NSInteger)s->id;
            obj.title = s->title ? [NSString stringWithUTF8String:s->title] : nil;
            obj.badgeName = s->badge_name[0] ? [NSString stringWithUTF8String:s->badge_name] : nil;
            obj.numAchievements = (NSInteger)s->num_achievements;
            obj.isCore = (i == 0);
            if (s->badge_url && s->badge_url[0]) {
                obj.badgeUrl = [NSString stringWithUTF8String:s->badge_url];
            }
            [subsetArr addObject:obj];
            subsetById[@(obj._id)] = obj;
        }
        rc_client_destroy_subset_list(subset_list);
    }
    game.subsets = subsetArr;
    NSInteger fallbackSubsetId = subsetArr.firstObject ? subsetArr.firstObject._id : 0;

    /* LOCK_STATE puts each achievement in a per-subset bucket so subset_id is reliable. */
    rc_client_achievement_list_t* list =
        rc_client_create_achievement_list(client,
            RC_CLIENT_ACHIEVEMENT_CATEGORY_CORE_AND_UNOFFICIAL,
            RC_CLIENT_ACHIEVEMENT_LIST_GROUPING_LOCK_STATE);

    if (list) {
        NSMutableArray<CheevosAchievement*>* arr = [NSMutableArray array];
        NSMutableSet<NSNumber*>* seen = [NSMutableSet set];
        for (uint32_t b = 0; b < list->num_buckets; b++) {
            const rc_client_achievement_bucket_t* bucket = &list->buckets[b];
            if (bucket->bucket_type == RC_CLIENT_ACHIEVEMENT_BUCKET_LOCKED && bucket->num_achievements == 1) {
                const rc_client_achievement_t* a = bucket->achievements[0];
                if (a->description && [[NSString stringWithCString:a->description encoding:NSUTF8StringEncoding] containsString:@"Hardcore unlocks cannot be earned"]) {
                    /* RA has not certified this client for Hardcore. */
                    game.notSupportHardcore = YES;
                    continue;
                }
            }
            NSInteger subsetId = bucket->subset_id ? (NSInteger)bucket->subset_id : fallbackSubsetId;
            CheevosSubset* subset = subsetById[@(subsetId)];
            for (uint32_t i = 0; i < bucket->num_achievements; i++) {
                const rc_client_achievement_t* a = bucket->achievements[i];
                if (!a || [seen containsObject:@(a->id)]) {
                    continue;
                }
                [seen addObject:@(a->id)];
                CheevosAchievement* obj = buildAchievementObj(a);
                if (!obj) {
                    continue;
                }
                obj.subsetId = subsetId;
                obj.subsetTitle = subset.title;
                [arr addObject:obj];
            }
        }
        game.achievements = arr;
        rc_client_destroy_achievement_list(list);
    }

    if (g->badge_url && g->badge_url[0]) {
        game.badgeUrl = [NSString stringWithUTF8String:g->badge_url];
    } else {
        char url[256];
        if (rc_client_game_get_image_url(g, url, sizeof(url)) == RC_OK) {
            game.badgeUrl = [NSString stringWithCString:url encoding:NSUTF8StringEncoding];
        }
    }

    return game;
}

#pragma mark - C callbacks

static void login_callback_c(int result, const char* error_message, rc_client_t* client, void* userdata) {
    CheevosLoginCtx* ctx = (__bridge_transfer CheevosLoginCtx*)userdata;
    LoginCompletion block = ctx.block;

    BOOL ok = (result == RC_OK);
    CheevosUser* user = ok ? buildUserObj(rc_client_get_user_info(client)) : nil;

    if (block) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (g_updateCredentials) {
                g_updateCredentials(user);
            }
            /**
             RC_OK    User was successfully logged in.
             用户已成功登录。
             
             RC_INVALID_CREDENTIALS    The provided credentials were not recognized.
             提供的凭证未被识别。
             
             RC_EXPIRED_TOKEN    The provided token has expired. The user should re-enter their credentials to generate a new token.
             提供的令牌已过期。用户应重新输入其凭证以生成新的令牌。
             
             RC_ACCESS_DENIED    Valid credentials were provided, but the user has not registered their email or has been banned.
             提供了有效的凭证，但用户尚未注册其电子邮件或已被封禁。
             
             RC_INVALID_STATE    Generic failure. See error_message for details.
             通用失败。详情请见 error_message 。
             
             RC_INVALID_JSON    Server response could not be processed.
             服务器响应无法处理。
             
             RC_MISSING_VALUE    Server response was not complete.
             服务器响应不完整。
             
             RC_API_FAILURE    Error occurred on the server. See error_message for details.
             服务器发生错误。详情请见 error_message 。
             */
            LoginResult loginResult = LoginResultSuccess;
            if (result != RC_OK) {
                if (result == RC_INVALID_CREDENTIALS) {
                    loginResult = LoginResultInvalid;
                } else if (result == RC_EXPIRED_TOKEN) {
                    loginResult = LoginResultExpired;
                } else if (result == RC_ACCESS_DENIED) {
                    loginResult = LoginResultDenied;
                } else {
                    loginResult = LoginResultServerError;
                }
            }
            block(loginResult, user);
        });
    }
}

static void load_game_callback_c(int result, const char* error_message, rc_client_t* client, void* userdata) {
    CheevosGameInfoCtx* ctx = (__bridge_transfer CheevosGameInfoCtx*)userdata;
    GetGameInfoCompletion block = ctx.block;

    BOOL ok = (result == RC_OK) && rc_client_is_game_loaded(client);
    
    CheevosGame* game = ok ? buildGameObj(client) : nil;
    if (game) {
        cacheGameInfo(ctx.path, game);
    }

    if (block) {
        dispatch_async(dispatch_get_main_queue(), ^{
            
            if (!game) {
                block(GetGameInfoResultNoLoaded, nil);
                return;
            }
            
            /**
             RC_OK    Game was successfully loaded.
             游戏已成功加载。
             
             RC_NO_GAME_LOADED    The game could not be identified.
             游戏无法识别。
             
             RC_LOGIN_REQUIRED    A logged in user is required.
             需要登录用户。
             
             RC_ABORTED    The process was canceled before it finished (rc_client_unload_game was called, or another game started loading).
             过程在完成前被取消（调用了 rc_client_unload_game，或开始加载其他游戏）。
             
             RC_INVALID_STATE    Generic failure. See error_message for details.
             通用失败。详情请见 error_message 。
             
             RC_INVALID_JSON    Server response could not be processed.
             服务器响应无法处理。
             
             RC_MISSING_VALUE    Server response was not complete.
             服务器响应不完整。
             
             RC_API_FAILURE    Error occurred on the server. See error_message for details.
             服务器发生错误。详情请见 error_message 。
             */
            
            GetGameInfoResult getGameInfoResult = GetGameInfoResultSuccess;
            if (result != RC_OK) {
                if (result == RC_NO_GAME_LOADED) {
                    getGameInfoResult = GetGameInfoResultNoLoaded;
                } else if (result == RC_LOGIN_REQUIRED) {
                    getGameInfoResult = GetGameInfoResultNoLogin;
                } else if (result == RC_INVALID_STATE || result == RC_ABORTED) {
                    getGameInfoResult = GetGameInfoResultUnknown;
                } else {
                    getGameInfoResult = GetGameInfoResultServerError;
                }
            }
            block(getGameInfoResult, game);
        });
    }
}

#pragma mark - Public methods
static NSString *g_appVersion = nil;
static RequireCredentials g_requireCredentials = nil;
static UpdateCredentials g_updateCredentials = nil;
static NSString *g_password = nil;

+ (void)setupWith:(NSString * _Nonnull)appVersion requireCredentials:(RequireCredentials _Nullable)requireCredentials updateCredentials:(UpdateCredentials _Nullable)updateCredentials {
    g_appVersion = appVersion;
    g_requireCredentials = requireCredentials;
    g_updateCredentials = updateCredentials;
}

+ (void)LoginCheevos:(NSString * _Nonnull)userName
            password:(NSString * _Nonnull)password
            callback:(LoginCompletion _Nullable)callback {
    g_password = password;

    rc_client_t* client = ensure_client();
    if (!client) {
        if (callback) callback(LoginResultUnknown, nil);
        return;
    }

    CheevosLoginCtx* ctx = [CheevosLoginCtx new];
    ctx.block = callback;

    clearGameInfoCache();

    rc_client_begin_login_with_password(client,
        userName.UTF8String ?: "",
        password.UTF8String ?: "",
        login_callback_c, (__bridge_retained void*)ctx);
}

+ (void)LogoutCheevos {
    rc_client_t* client = ensure_client();
    if (client) {
        rc_client_logout(client);
    }
    clearGameInfoCache();
}

+ (CheevosGame *)cachedGameInfoForPath:(NSString *)gamePath {
    if (gamePath.length == 0) {
        return nil;
    }
    return cachedGameInfo(gamePath);
}

+ (void)getCheevosGameInfo:(NSString *)gamePath
                  callback:(GetGameInfoCompletion)callback {
    [self getCheevosGameInfo:gamePath reuseInGameClient:NO callback:callback];
}

+ (void)getCheevosGameInfo:(NSString * _Nonnull)gamePath
         reuseInGameClient:(BOOL)reuseInGameClient
                  callback:(GetGameInfoCompletion _Nullable)callback {
    if (reuseInGameClient) {
        rc_client_t *inGameClient = (rc_client_t *)rcheevos_get_client();
        if (inGameClient) {
            CheevosGame *game = buildGameObj(inGameClient);
            if (game) {
                cacheGameInfo(gamePath, game);
                if (callback) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        callback(GetGameInfoResultSuccess, game);
                    });
                }
                return;
            }
        }
    }

    rc_client_t* client = ensure_client();
    if (!client) {
        if (callback) callback(GetGameInfoResultUnknown, nil);
        return;
    }
    if (gamePath.length == 0) {
        if (callback) callback(GetGameInfoResultNoLoaded, nil);
        return;
    }

    if (!rc_client_get_user_info(client)) {
        if (g_requireCredentials) {
            CheevosUser *user = g_requireCredentials();
            if (user == nil) {
                if (callback) callback(GetGameInfoResultNoLogin, nil);
                return;
            }
            [CheevosBridge LoginCheevos:user.userName password:user.password callback:^(LoginResult result, CheevosUser * _Nullable user) {
                if (user) {
                    CheevosGameInfoCtx* ctx = [CheevosGameInfoCtx new];
                    ctx.block = callback;
                    ctx.path = gamePath;
                    
                    rcheevos_reset_cdreader_hooks();

                    rc_client_begin_identify_and_load_game(client, 0 /* RC_CONSOLE_UNKNOWN */,
                        ctx.path.UTF8String, NULL, 0, load_game_callback_c, (__bridge_retained void*)ctx);
                } else {
                    if (callback) callback(GetGameInfoResultNoLogin, nil);
                    return;
                }
            }];
        }
        return;
    }

    CheevosGameInfoCtx* ctx = [CheevosGameInfoCtx new];
    ctx.block = callback;
    ctx.path = gamePath;

    rcheevos_reset_cdreader_hooks();
    
    rc_client_begin_identify_and_load_game(client, 0 /* RC_CONSOLE_UNKNOWN */,
        ctx.path.UTF8String, NULL, 0, load_game_callback_c, (__bridge_retained void*)ctx);
}

@end
