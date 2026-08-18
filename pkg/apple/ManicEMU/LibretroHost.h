//
//  LibretroHost.h
//  Libretro
//
//  Created by Daiuno on 2026/8/10.
//  Copyright © 2026 Manic EMU. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 联机主机的连接方式
typedef NS_ENUM(NSInteger, LibretroHostMethod) {
    LibretroHostMethodUnknown = 0,
    LibretroHostMethodManual  = 1,
    LibretroHostMethodUPNP    = 2,
    /// 通过官方中继服务器转发
    LibretroHostMethodMITM    = 3,
};

/// 一个可加入的联机主机(房间)信息
@interface LibretroHost : NSObject

#pragma mark - 显示信息
/// 主机玩家昵称
@property (nonatomic, copy, nullable) NSString *nickname;
/// 核心名称
@property (nonatomic, copy, nullable) NSString *coreName;
/// 核心版本
@property (nonatomic, copy, nullable) NSString *coreVersion;
/// 正在游玩的游戏文件名
@property (nonatomic, copy, nullable) NSString *content;
/// 游戏内容 CRC32(用于校验双方 ROM 是否一致, 0 表示未知)
@property (nonatomic, assign) NSInteger contentCRC;
/// 主机的 RetroArch 版本号
@property (nonatomic, copy, nullable) NSString *retroarchVersion;
/// 主机前端标识(如 "darwin arm64")
@property (nonatomic, copy, nullable) NSString *frontend;
/// 子系统名称(非子系统游戏为 "N/A")
@property (nonatomic, copy, nullable) NSString *subsystemName;
/// 国家代码(仅互联网房间)
@property (nonatomic, copy, nullable) NSString *country;

#pragma mark - 状态
/// 加入游玩是否需要密码
@property (nonatomic, assign) BOOL hasPassword;
/// 观战是否需要密码
@property (nonatomic, assign) BOOL hasSpectatePassword;
/// 是否为局域网主机
@property (nonatomic, assign) BOOL isLan;
/// 是否可连接(互联网房间可能因 NAT 不可直连)
@property (nonatomic, assign) BOOL connectable;

#pragma mark - 连接信息
/// 主机地址
@property (nonatomic, copy, nullable) NSString *address;
/// 主机端口
@property (nonatomic, assign) NSInteger port;
/// 连接方式
@property (nonatomic, assign) LibretroHostMethod hostMethod;
/// 中继服务器地址(仅 MITM)
@property (nonatomic, copy, nullable) NSString *mitmAddress;
/// 中继服务器端口(仅 MITM)
@property (nonatomic, assign) NSInteger mitmPort;
/// 中继会话 ID(仅 MITM)
@property (nonatomic, copy, nullable) NSString *mitmSession;

@end

NS_ASSUME_NONNULL_END
