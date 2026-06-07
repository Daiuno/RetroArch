////
////  CheevosBridge.m
////  CheevosBridge
////
////  Created by Daiuno on 2025/8/13.
////  Copyright © 2025 Manic EMU. All rights reserved.
////

#import <Foundation/Foundation.h>
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

@implementation CheevosGame
@end

@implementation CheevosAchievement
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
    char url1[256];
    if (rc_client_achievement_get_image_url(a, RC_CLIENT_ACHIEVEMENT_STATE_UNLOCKED, url1, sizeof(url1)) == RC_OK) {
        obj.unlockedBadgeUrl = [NSString stringWithCString:url1 encoding:NSUTF8StringEncoding];
    }
    char url2[256];
    if (rc_client_achievement_get_image_url(a, RC_CLIENT_ACHIEVEMENT_STATE_ACTIVE, url2, sizeof(url2)) == RC_OK) {
        obj.activeBadgeUrl = [NSString stringWithCString:url2 encoding:NSUTF8StringEncoding];
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

    rc_client_achievement_list_t* list =
        rc_client_create_achievement_list(client,
            RC_CLIENT_ACHIEVEMENT_CATEGORY_CORE_AND_UNOFFICIAL,
            RC_CLIENT_ACHIEVEMENT_LIST_GROUPING_PROGRESS);

    if (list) {
        NSMutableArray<CheevosAchievement*>* arr = [NSMutableArray array];
        for (uint32_t b = 0; b < list->num_buckets; b++) {
            rc_client_achievement_bucket_t* bucket = &list->buckets[b];
            if (bucket->bucket_type == RC_CLIENT_ACHIEVEMENT_BUCKET_LOCKED && bucket->num_achievements == 1) {
                rc_client_achievement_t* a = bucket->achievements[0];
                if (a->description && [[NSString stringWithCString:a->description encoding:NSUTF8StringEncoding] containsString:@"Hardcore unlocks cannot be earned"]) {
                    //如果Manic EMU没有获得RetroAchievements的审核认证，则不支持开启Hardcore
                    game.notSupportHardcore = YES;
                    continue;
                }
                
            }
            for (uint32_t i = 0; i < bucket->num_achievements; i++) {
                rc_client_achievement_t* a = bucket->achievements[i];
                CheevosAchievement* obj = buildAchievementObj(a);
                if (obj) [arr addObject:obj];
            }
        }
        game.achievements = arr;
        rc_client_destroy_achievement_list(list);
    }
    
    char url[256];
    if (rc_client_game_get_image_url(g, url, sizeof(url)) == RC_OK) {
        game.badgeUrl = [NSString stringWithCString:url encoding:NSUTF8StringEncoding];
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
}

+ (void)getCheevosGameInfo:(NSString * _Nonnull)gamePath
                  callback:(GetGameInfoCompletion _Nullable)callback {

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
