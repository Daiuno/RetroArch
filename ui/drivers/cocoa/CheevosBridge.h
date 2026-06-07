//
//  CheevosBridge.h
//  CheevosBridge
//
//  Created by Daiuno on 2025/8/13.
//  Copyright © 2025 Manic EMU. All rights reserved.
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>


@interface CheevosUser : NSObject

@property (nonatomic, copy) NSString *_Nullable displayName;
@property (nonatomic, copy) NSString *_Nullable userName;
@property (nonatomic, copy) NSString *_Nullable password;
@property (nonatomic, copy) NSString *_Nullable token;
@property (nonatomic, assign) NSInteger score;
@property (nonatomic, assign) NSInteger softcoreScore;

@end

@interface CheevosAchievement : NSObject

@property (nonatomic, copy) NSString *_Nullable title;
@property (nonatomic, copy) NSString *_Nullable _description;
@property (nonatomic, copy) NSString *_Nullable badgeName;
@property (nonatomic, copy) NSString *_Nullable measuredProgress;
@property (nonatomic, assign) CGFloat measuredPercent;
@property (nonatomic, assign) NSInteger _id;
@property (nonatomic, assign) NSInteger points;
@property (nonatomic, strong) NSDate *_Nullable unlockTime;
@property (nonatomic, assign) NSInteger state;
@property (nonatomic, assign) NSInteger category;
@property (nonatomic, assign) NSInteger bucket;
@property (nonatomic, assign) BOOL unlocked;
@property (nonatomic, assign) BOOL hardcoreUnlocked;
@property (nonatomic, assign) BOOL softcoreUnlocked;
@property (nonatomic, assign) CGFloat rarity;
@property (nonatomic, assign) CGFloat rarityHardcore;
@property (nonatomic, assign) NSInteger type;
@property (nonatomic, copy) NSString *_Nullable unlockedBadgeUrl;
@property (nonatomic, copy) NSString *_Nullable activeBadgeUrl;
@property (nonatomic, assign) BOOL isMissable;
@property (nonatomic, assign) BOOL isProgression;

@property (nonatomic, assign) BOOL isProgressAchievement;
@property (nonatomic, assign) BOOL isChallengeAchievement;
@property (nonatomic, assign) BOOL show;

@end

@interface CheevosGame : NSObject

@property (nonatomic, copy) NSString *_Nullable title;
@property (nonatomic, copy) NSString *_Nullable _hash;
@property (nonatomic, copy) NSString *_Nullable badgeName;
@property (nonatomic, assign) NSInteger _id;
@property (nonatomic, assign) NSInteger console_id;
@property (nonatomic, copy) NSArray<CheevosAchievement*>* _Nullable achievements;
@property (nonatomic, copy) NSString *_Nullable badgeUrl;
@property (nonatomic, assign) BOOL notSupportHardcore;

@end

@interface CheevosSummary : NSObject

@property (nonatomic, copy) NSString *_Nullable title;
@property (nonatomic, copy) NSString *_Nullable badgeUrl;
@property (nonatomic, assign) NSInteger coreAchievementsNum;
@property (nonatomic, assign) NSInteger unofficialAchievementsNum;
@property (nonatomic, assign) NSInteger unlockedAchievementsNum;
@property (nonatomic, assign) NSInteger unsupportedAchievementsNum;
@property (nonatomic, assign) NSInteger corePoints;
@property (nonatomic, assign) NSInteger unlockedPoints;

@end

@interface CheevosCompletion : NSObject
@end

@interface CheevosLeaderboardTracker : NSObject
@property (nonatomic, assign) BOOL show;
@property (nonatomic, assign) NSInteger _id;
@property (nonatomic, copy) NSString *_Nullable display;
@end

@interface CheevosLeaderboard : NSObject
@property (nonatomic, copy) NSString *_Nullable badgeUrl;
@property (nonatomic, strong) UIImage *_Nullable image;
@property (nonatomic, copy) NSString *_Nullable title;
@property (nonatomic, copy) NSString *_Nullable _description;
@end

///登录结果
typedef NS_ENUM(NSUInteger, LoginResult) {
   ///成功
   LoginResultSuccess,
   ///提供的凭证未被识别。
   LoginResultInvalid,
   ///提供的令牌已过期。用户应重新输入其凭证以生成新的令牌。
   LoginResultExpired,
   ///提供了有效的凭证，但用户尚未注册其电子邮件或已被封禁。
   LoginResultDenied,
   ///服务器错误
   LoginResultServerError,
   ///未知错误
   LoginResultUnknown,
};

///获取游戏信息结果
typedef NS_ENUM(NSUInteger, GetGameInfoResult) {
   ///成功
   GetGameInfoResultSuccess,
   ///游戏无法识别。
   GetGameInfoResultNoLoaded,
   ///需要登录用户。
   GetGameInfoResultNoLogin,
   ///服务器错误
   GetGameInfoResultServerError,
   ///未知错误
   GetGameInfoResultUnknown,
};

///请求用户凭证
typedef CheevosUser*_Nullable(^RequireCredentials)(void);
///用户凭证更新
typedef void(^UpdateCredentials)(CheevosUser * _Nullable);
///登录回调
typedef void(^LoginCompletion)(LoginResult result, CheevosUser * _Nullable user);
///获取游戏回调
typedef void(^GetGameInfoCompletion)(GetGameInfoResult result, CheevosGame * _Nullable game);

@interface CheevosBridge : NSObject

+ (void)setupWith:(NSString * _Nonnull)appVersion requireCredentials:(RequireCredentials _Nullable)requireCredentials updateCredentials:(UpdateCredentials _Nullable)updateCredentials;

+ (void)LoginCheevos:(NSString * _Nonnull)userName
            password:(NSString * _Nonnull)password
            callback:(LoginCompletion _Nullable)callback;

+ (void)LogoutCheevos;

+ (void)getCheevosGameInfo:(NSString * _Nonnull)gamePath
                  callback:(GetGameInfoCompletion _Nullable)callback;

@end
