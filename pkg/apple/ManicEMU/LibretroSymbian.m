//
//  LibretroPSPGame.m
//  Libretro
//
//  Created by Daiuno on 2026/4/10.
//  Copyright © 2026 Manic EMU. All rights reserved.
//

#import "LibretroSymbian.h"

static id LibretroSymbianJSONString(NSString * _Nullable value) {
    return value.length ? value : [NSNull null];
}

static NSString *LibretroSymbianPrettyJSONString(id object) {
    if (!object) {
        return @"null";
    }
    if (![NSJSONSerialization isValidJSONObject:object]) {
        return [NSString stringWithFormat:@"%@", object];
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:object
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:NULL];
    if (!data) {
        return [NSString stringWithFormat:@"%@", object];
    }
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
        ?: [NSString stringWithFormat:@"%@", object];
}

static NSDictionary *LibretroSymbianDeviceJSONObject(LibretroSymbianDevice *device) {
    return @{
        @"index": @(device.index),
        @"epocVersion": @(device.epocVersion),
        @"machineUid": @(device.machineUid),
        @"machineUidString": [NSString stringWithFormat:@"0x%08lX", (long)device.machineUid],
        @"firmwareCode": LibretroSymbianJSONString(device.firmwareCode),
        @"manufacturer": LibretroSymbianJSONString(device.manufacturer),
        @"model": LibretroSymbianJSONString(device.model),
        @"screenWidth": @(device.screenWidth),
        @"screenHeight": @(device.screenHeight),
        @"symbianOsMajor": @(device.symbianOsMajor),
        @"symbianOsMinor": @(device.symbianOsMinor),
        @"symbianPlatform": LibretroSymbianJSONString(device.symbianPlatform),
    };
}

static NSDictionary *LibretroSymbianGamePackageJSONObject(LibretroSymbianGamePackage *package) {
    return @{
        @"uid": @(package.uid),
        @"uidString": [NSString stringWithFormat:@"0x%08lX", (long)package.uid],
        @"index": @(package.index),
        @"packageName": LibretroSymbianJSONString(package.packageName),
        @"vendorName": LibretroSymbianJSONString(package.vendorName),
    };
}

@implementation LibretroSymbianDevice

- (NSString *)description {
    return LibretroSymbianPrettyJSONString(LibretroSymbianDeviceJSONObject(self));
}

@end

@implementation LibretroSymbianGamePackage

- (NSString *)description {
    return LibretroSymbianPrettyJSONString(LibretroSymbianGamePackageJSONObject(self));
}

@end

@implementation LibretroSymbianGame

- (NSString *)uidString {
    return [NSString stringWithFormat: @"0x%08lX", (long)self.uid];
}

- (NSString *)description {
    NSMutableArray *packageObjects = [NSMutableArray array];
    for (LibretroSymbianGamePackage *package in self.packages) {
        [packageObjects addObject:LibretroSymbianGamePackageJSONObject(package)];
    }

    NSString *iconSummary = self.icon
        ? [NSString stringWithFormat:@"UIImage(%.0fx%.0f)",
           self.icon.size.width, self.icon.size.height]
        : nil;

    NSDictionary *object = @{
        @"uid": @(self.uid),
        @"uidString": self.uidString,
        @"shortCaption": LibretroSymbianJSONString(self.shortCaption),
        @"longCaption": LibretroSymbianJSONString(self.longCaption),
        @"driveLetter": LibretroSymbianJSONString(self.driveLetter),
        @"isSystemApp": @(self.isSystemApp),
        @"isHidden": @(self.isHidden),
        @"isUserInstalled": @(self.isUserInstalled),
        @"icon": LibretroSymbianJSONString(iconSummary),
        @"appPath": LibretroSymbianJSONString(self.appPath),
        @"compatibleDevice": self.compatibleDevice
            ? LibretroSymbianDeviceJSONObject(self.compatibleDevice)
            : [NSNull null],
        @"packages": packageObjects,
    };
    return LibretroSymbianPrettyJSONString(object);
}

@end
