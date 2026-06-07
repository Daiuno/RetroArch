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

@interface LibretroPSPGame : NSObject

@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong, nullable) UIImage *icon;
@property (nonatomic, copy) NSString *gameID;
@property (nonatomic, copy) NSString *gamePath; //eg. GAME/pspkvm/EBOOT.PBP

@end

NS_ASSUME_NONNULL_END
