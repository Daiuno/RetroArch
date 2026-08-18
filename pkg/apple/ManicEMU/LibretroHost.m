//
//  LibretroHost.m
//  Libretro
//
//  Created by Daiuno on 2026/8/10.
//  Copyright © 2026 Manic EMU. All rights reserved.
//

#import "LibretroHost.h"

#include <string.h>
#include "../../../network/netplay/netplay.h"
#include "../../../network/netplay/netplay_defines.h"

static NSString *LibretroHostNSString(const char *cstr)
{
    if (!cstr || !cstr[0])
        return nil;
    return [NSString stringWithUTF8String:cstr];
}

@implementation LibretroHost

+ (instancetype)hostWithRoom:(const struct netplay_room *)room
{
    if (!room)
        return nil;

    LibretroHost *host = [[LibretroHost alloc] init];
    host.nickname = LibretroHostNSString(room->nickname);
    host.coreName = LibretroHostNSString(room->corename);
    host.coreVersion = LibretroHostNSString(room->coreversion);
    host.content = LibretroHostNSString(room->gamename);
    host.contentCRC = room->gamecrc;
    host.retroarchVersion = LibretroHostNSString(room->retroarch_version);
    host.frontend = LibretroHostNSString(room->frontend);
    host.subsystemName = LibretroHostNSString(room->subsystem_name);
    host.country = LibretroHostNSString(room->country);

    host.hasPassword = room->has_password;
    host.hasSpectatePassword = room->has_spectate_password;
    host.isLan = room->lan;
    host.connectable = room->connectable;

    host.address = LibretroHostNSString(room->address);
    host.port = room->port;
    host.hostMethod = (LibretroHostMethod)room->host_method;
    host.mitmAddress = LibretroHostNSString(room->mitm_address);
    host.mitmPort = room->mitm_port;
    host.mitmSession = LibretroHostNSString(room->mitm_session);
    return host;
}

+ (instancetype)hostWithLANHost:(const struct netplay_host *)lanHost
{
    if (!lanHost)
        return nil;

    LibretroHost *host = [[LibretroHost alloc] init];
    host.nickname = LibretroHostNSString(lanHost->nick);
    host.coreName = LibretroHostNSString(lanHost->core);
    host.coreVersion = LibretroHostNSString(lanHost->core_version);
    host.content = LibretroHostNSString(lanHost->content);
    host.contentCRC = lanHost->content_crc;
    host.retroarchVersion = LibretroHostNSString(lanHost->retroarch_version);
    host.frontend = LibretroHostNSString(lanHost->frontend);
    host.subsystemName = LibretroHostNSString(lanHost->subsystem_name);

    host.hasPassword = lanHost->has_password;
    host.hasSpectatePassword = lanHost->has_spectate_password;
    host.isLan = YES;
    host.connectable = YES;

    host.address = LibretroHostNSString(lanHost->address);
    host.port = lanHost->port;
    host.hostMethod = LibretroHostMethodManual;
    return host;
}

- (NSString *)description
{
    static NSString * const hostMethodNames[] = {
        @"unknown", @"manual", @"upnp", @"mitm"
    };
    NSString *methodName = (self.hostMethod >= LibretroHostMethodUnknown
                            && self.hostMethod <= LibretroHostMethodMITM)
        ? hostMethodNames[self.hostMethod]
        : @"unknown";

    NSDictionary *json = @{
        @"nickname": self.nickname ?: [NSNull null],
        @"coreName": self.coreName ?: [NSNull null],
        @"coreVersion": self.coreVersion ?: [NSNull null],
        @"content": self.content ?: [NSNull null],
        @"contentCRC": @(self.contentCRC),
        @"retroarchVersion": self.retroarchVersion ?: [NSNull null],
        @"frontend": self.frontend ?: [NSNull null],
        @"subsystemName": self.subsystemName ?: [NSNull null],
        @"country": self.country ?: [NSNull null],
        @"hasPassword": @(self.hasPassword),
        @"hasSpectatePassword": @(self.hasSpectatePassword),
        @"isLan": @(self.isLan),
        @"connectable": @(self.connectable),
        @"address": self.address ?: [NSNull null],
        @"port": @(self.port),
        @"hostMethod": methodName,
        @"mitmAddress": self.mitmAddress ?: [NSNull null],
        @"mitmPort": @(self.mitmPort),
        @"mitmSession": self.mitmSession ?: [NSNull null]
    };

    NSData *data = [NSJSONSerialization dataWithJSONObject:json
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:nil];
    if (!data)
        return [super description];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

@end
