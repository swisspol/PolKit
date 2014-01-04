/*
	This file is part of the PolKit library.
	Copyright (C) 2008-2009 Pierre-Olivier Latour <info@pol-online.net>
	
	This program is free software: you can redistribute it and/or modify
	it under the terms of the GNU General Public License as published by
	the Free Software Foundation, either version 3 of the License, or
	(at your option) any later version.
	
	This program is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.
	
	You should have received a copy of the GNU General Public License
	along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#import <Foundation/Foundation.h>

@class AppleRemote, HIDController;

@protocol AppleRemoteDelegate <NSObject>
@optional
- (void) appleRemoteDidPressLeftButton:(AppleRemote*)remote;
- (void) appleRemoteDidHoldLeftButton:(AppleRemote*)remote;
- (void) appleRemoteDidPressRightButton:(AppleRemote*)remote;
- (void) appleRemoteDidHoldRightButton:(AppleRemote*)remote;
- (void) appleRemoteDidPressUpButton:(AppleRemote*)remote;
- (void) appleRemoteDidPressDownButton:(AppleRemote*)remote;
- (void) appleRemoteDidPressEnterButton:(AppleRemote*)remote;
- (void) appleRemoteDidPressMenuButton:(AppleRemote*)remote;
- (void) appleRemoteDidHoldMenuButton:(AppleRemote*)remote;
@end

@interface AppleRemote : NSObject
{
@private
	HIDController*					_remoteController;
	id<AppleRemoteDelegate>			_remoteDelegate;
}
- (id) initWithExclusiveUse:(BOOL)exclusive;

- (void) setDelegate:(id<AppleRemoteDelegate>)delegate;
- (id<AppleRemoteDelegate>) delegate;
@end
