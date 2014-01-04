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

#import "LoginItems.h"

@implementation LoginItems

+ (LoginItems*) sharedLoginItems
{
	static LoginItems*		loginItems = nil;
	
	if(loginItems == nil)
	loginItems = [LoginItems new];
	
	return loginItems;
}

- (BOOL) addItemWithDisplayName:(NSString*)name url:(NSURL*)url hidden:(BOOL)hidden
{
	LSSharedFileListRef		list;
	LSSharedFileListItemRef	item;
	
	list = LSSharedFileListCreate(kCFAllocatorDefault, kLSSharedFileListSessionLoginItems, NULL);
	if(list == NULL) {
		NSLog(@"%s: Failed retrieving shared file list for session login items", __FUNCTION__);
		return NO;
	}
	
	item = LSSharedFileListInsertItemURL(list, kLSSharedFileListItemLast, (CFStringRef)name, NULL, (CFURLRef)url, (CFDictionaryRef)[NSDictionary dictionaryWithObject:[NSNumber numberWithBool:hidden] forKey:(id)kLSSharedFileListItemHidden], NULL);
	if(item)
	CFRelease(item);
	else
	NSLog(@"%s: Failed inserting entry \"%s\" into shared file list for session login items", __FUNCTION__, name);
	
	CFRelease(list);
	
	return (item ? YES : NO);
}

- (BOOL) removeItemWithDisplayName:(NSString*)name
{
	BOOL					success;
	LSSharedFileListRef		list;
	UInt32					seed;
	CFArrayRef				items;
	CFIndex					i;
	LSSharedFileListItemRef	item;
	
	list = LSSharedFileListCreate(kCFAllocatorDefault, kLSSharedFileListSessionLoginItems, NULL);
	if(list == NULL) {
		NSLog(@"%s: Failed retrieving shared file list for session login items", __FUNCTION__);
		return NO;
	}
	
	items = LSSharedFileListCopySnapshot(list, &seed);
	if(items) {
		success = YES;
		for(i = 0; i < CFArrayGetCount(items); ++i) {
			item = (LSSharedFileListItemRef)CFArrayGetValueAtIndex(items, i);
			if([(NSString*)[NSMakeCollectable(LSSharedFileListItemCopyDisplayName(item)) autorelease] isEqualToString:name]) {
				if(LSSharedFileListItemRemove(list, item) != noErr) {
					NSLog(@"%s: Failed removing entry \"%s\" from shared file list for session login items", __FUNCTION__, name);
					success = NO;
				}
				break;
			}
		}
		CFRelease(items);
	}
	else {
		NSLog(@"%s: Failed retrieving entries from shared file list for session login items", __FUNCTION__);
		success = NO;
	}
	
	CFRelease(list);
	
	return success;
}

- (BOOL) hasItemWithDisplayName:(NSString*)name
{
	BOOL					found = NO;
	LSSharedFileListRef		list;
	UInt32					seed;
	CFArrayRef				items;
	CFIndex					i;
	LSSharedFileListItemRef	item;
	
	list = LSSharedFileListCreate(kCFAllocatorDefault, kLSSharedFileListSessionLoginItems, NULL);
	if(list == NULL) {
		NSLog(@"%s: Failed retrieving shared file list for session login items", __FUNCTION__);
		return NO;
	}
	
	items = LSSharedFileListCopySnapshot(list, &seed);
	if(items) {
		for(i = 0; i < CFArrayGetCount(items); ++i) {
			item = (LSSharedFileListItemRef)CFArrayGetValueAtIndex(items, i);
			if([(NSString*)[NSMakeCollectable(LSSharedFileListItemCopyDisplayName(item)) autorelease] isEqualToString:name]) {
				found = YES;
				break;
			}
		}
		CFRelease(items);
	}
	else
	NSLog(@"%s: Failed retrieving entries from shared file list for session login items", __FUNCTION__);
	
	CFRelease(list);
	
	return found;
}

@end
