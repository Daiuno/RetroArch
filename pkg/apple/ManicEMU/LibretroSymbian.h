//
//  LibretroPSPGame.h
//  Libretro
//
//  Created by Daiuno on 2026/4/10.
//  Copyright © 2026 Manic EMU. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, LibretroSymbianRomInstallResult) {
    LibretroSymbianRomInstallResultOK = 0,
    LibretroSymbianRomInstallResultNotExist = 1,
    LibretroSymbianRomInstallResultInsufficient = 2,
    LibretroSymbianRomInstallResultRpkgCorrupt = 3,
    LibretroSymbianRomInstallResultDetermineProductFail = 4,
    LibretroSymbianRomInstallResultAlreadyExist = 5,
    LibretroSymbianRomInstallResultGeneralFailure = 6,
    LibretroSymbianRomInstallResultRomFailToCopy = 7,
    LibretroSymbianRomInstallResultVplFileInvalid = 8,
    LibretroSymbianRomInstallResultRofsCorrupt = 9,
    LibretroSymbianRomInstallResultRomFileCorrupt = 10,
    LibretroSymbianRomInstallResultFpsxCorrupt = 11,
    LibretroSymbianRomInstallResultUnknown = 99,
};

typedef NS_ENUM(NSUInteger, LibretroSymbianGameInstallResult) {
    LibretroSymbianGameInstallResultOK = 0,
    LibretroSymbianGameInstallResultNot_exist = 1,
    LibretroSymbianGameInstallResultAlreadyExist = 5,
    LibretroSymbianGameInstallResultGeneralFailure = 6,
    LibretroSymbianGameInstallResultAborted = 50,
    LibretroSymbianGameInstallResultInvalidPackage = 51,
    LibretroSymbianGameInstallResultUnsupportedFirmware = 52,
    LibretroSymbianGameInstallResultUnknown = 99,
};

typedef NS_OPTIONS(NSUInteger, LibretroSymbianAppKind) {
    LibretroSymbianAppKindSystem   = 1 << 0,
    LibretroSymbianAppKindFirmware = 1 << 1,
    LibretroSymbianAppKindUser     = 1 << 2,
    LibretroSymbianAppKindAll      = (LibretroSymbianAppKindSystem |
                                      LibretroSymbianAppKindFirmware |
                                      LibretroSymbianAppKindUser),
};

/**
 [{
   "index" : 2,
   "machineUidString" : "0x2000DA5A",
   "symbianOsMajor" : 9,
   "symbianPlatform" : "S60v3 FP2",
   "machineUid" : 536926810,
   "screenHeight" : 320,
   "firmwareCode" : "RM-409",
   "manufacturer" : "(c)Nokia",
   "symbianOsMinor" : 3,
   "epocVersion" : 9,
   "model" : "Nokia 5320d-1 (05.01)",
   "screenWidth" : 240
 }]
 */
@interface LibretroSymbianDevice : NSObject

@property (nonatomic, assign) NSInteger index; /* position inside device_manager */
@property (nonatomic, assign) NSInteger epocVersion; /* eka2l1::epocver as raw integer */
@property (nonatomic, assign) NSInteger machineUid; /* Symbian machine UID */
@property (nonatomic, copy) NSString *firmwareCode; /* e.g. "RM-356", "RM-237" */
@property (nonatomic, copy) NSString *manufacturer; /* e.g. "Nokia" */
@property (nonatomic, copy) NSString *model; /* human-readable model name */
@property (nonatomic, assign) NSInteger screenWidth;
@property (nonatomic, assign) NSInteger screenHeight;
@property (nonatomic, assign) NSInteger symbianOsMajor;
@property (nonatomic, assign) NSInteger symbianOsMinor;
@property (nonatomic, copy) NSString *symbianPlatform;
@end

/**
 {
   "uidString" : "0x2000730F",
   "uid" : 536900367,
   "packageName" : "Snakes",
   "vendorName" : "Nokia",
   "index" : 0
 }
 */
@interface LibretroSymbianGamePackage : NSObject

@property (nonatomic, assign) NSInteger uid; //for uninstall
@property (nonatomic, assign) NSInteger index;
@property (nonatomic, copy) NSString *packageName;
@property (nonatomic, copy) NSString *vendorName;

@end

/**
 {
   "compatibleDevice" : {
     "index" : 2,
     "machineUidString" : "0x2000DA5A",
     "symbianOsMajor" : 9,
     "symbianPlatform" : "S60v3 FP2",
     "machineUid" : 536926810,
     "screenHeight" : 320,
     "firmwareCode" : "RM-409",
     "manufacturer" : "(c)Nokia",
     "symbianOsMinor" : 3,
     "epocVersion" : 9,
     "model" : "Nokia 5320d-1 (05.01)",
     "screenWidth" : 240
   },
   "longCaption" : "Snakes",
   "uid" : 536900367,
   "shortCaption" : "Snakes",
   "appPath" : "E:\\system\\programs\\6r45_1b.exe",
   "isHidden" : false,
   "isSystemApp" : false,
   "isUserInstalled" : true,
   "icon" : "UIImage(600x600)",
   "driveLetter" : "e",
   "packages" : [
     {
       "uidString" : "0x2000730F",
       "uid" : 536900367,
       "packageName" : "Snakes",
       "vendorName" : "Nokia",
       "index" : 0
     }
   ],
   "uidString" : "0x2000730F"
 }
 */
@interface LibretroSymbianGame : NSObject

//app info
@property (nonatomic, assign) NSInteger uid; //for launch
@property (nonatomic, copy, readonly) NSString *uidString;
@property (nonatomic, copy, nullable) NSString *shortCaption;
@property (nonatomic, copy, nullable) NSString *longCaption;
@property (nonatomic, copy) NSString *driveLetter;
@property (nonatomic, assign) BOOL isSystemApp;
@property (nonatomic, assign) BOOL isHidden;
@property (nonatomic, assign) BOOL isUserInstalled;
@property (nonatomic, copy, nullable) UIImage *icon;
@property (nonatomic, copy, nullable) NSString *appPath;

/// Firmware that exposes a launchable AppList entry for this game.
@property (nonatomic, strong, nullable) LibretroSymbianDevice *compatibleDevice;

//package info
@property (nonatomic, copy) NSArray<LibretroSymbianGamePackage *> *packages;

@end



NS_ASSUME_NONNULL_END
