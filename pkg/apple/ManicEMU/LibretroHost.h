//
//  LibretroHost.h
//  Libretro
//
//  Created by Daiuno on 2026/8/10.
//  Copyright © 2026 Manic EMU. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// How a netplay host can be reached
typedef NS_ENUM(NSInteger, LibretroHostMethod) {
    LibretroHostMethodUnknown = 0,
    LibretroHostMethodManual  = 1,
    LibretroHostMethodUPNP    = 2,
    /// Relayed through the official MITM server
    LibretroHostMethodMITM    = 3,
};

/// Info for a joinable netplay host (room)
@interface LibretroHost : NSObject

#pragma mark - Display
/// Host player nickname
@property (nonatomic, copy, nullable) NSString *nickname;
/// Core name
@property (nonatomic, copy, nullable) NSString *coreName;
/// Core version
@property (nonatomic, copy, nullable) NSString *coreVersion;
/// Filename of the game currently being played
@property (nonatomic, copy, nullable) NSString *content;
/// Content CRC32 (used to verify both sides have the same ROM; 0 means unknown)
@property (nonatomic, assign) NSInteger contentCRC;
/// Host RetroArch version
@property (nonatomic, copy, nullable) NSString *retroarchVersion;
/// Host frontend identifier (e.g. "darwin arm64")
@property (nonatomic, copy, nullable) NSString *frontend;
/// Subsystem name ("N/A" for non-subsystem games)
@property (nonatomic, copy, nullable) NSString *subsystemName;
/// Country code (internet rooms only)
@property (nonatomic, copy, nullable) NSString *country;

#pragma mark - Status
/// Whether a password is required to join as a player
@property (nonatomic, assign) BOOL hasPassword;
/// Whether a password is required to spectate
@property (nonatomic, assign) BOOL hasSpectatePassword;
/// Whether this is a LAN host
@property (nonatomic, assign) BOOL isLan;
/// Whether connectable (internet rooms may not be reachable due to NAT)
@property (nonatomic, assign) BOOL connectable;

#pragma mark - Connection
/// Host address
@property (nonatomic, copy, nullable) NSString *address;
/// Host port
@property (nonatomic, assign) NSInteger port;
/// Connection method
@property (nonatomic, assign) LibretroHostMethod hostMethod;
/// MITM server address (MITM only)
@property (nonatomic, copy, nullable) NSString *mitmAddress;
/// MITM server port (MITM only)
@property (nonatomic, assign) NSInteger mitmPort;
/// MITM session ID (MITM only)
@property (nonatomic, copy, nullable) NSString *mitmSession;

@end

NS_ASSUME_NONNULL_END
