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

#import "NSFileManager+LockedItems.h"

@implementation NSFileManager (LockedItems)

- (BOOL) lockItemAtPath:(NSString*)path error:(NSError**)error
{
	return [self setAttributes:[NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:NSFileImmutable] ofItemAtPath:path error:error];
}

- (BOOL) unlockItemAtPath:(NSString*)path error:(NSError**)error
{
	return [self setAttributes:[NSDictionary dictionaryWithObject:[NSNumber numberWithBool:NO] forKey:NSFileImmutable] ofItemAtPath:path error:error];
}

- (BOOL) isItemLockedAtPath:(NSString*)path
{
	return [[[self attributesOfItemAtPath:path error:NULL] objectForKey:NSFileImmutable] boolValue];
}

- (BOOL) forceRemoveItemAtPath:(NSString*)path error:(NSError**)error
{
	NSDictionary*				attributes;
	NSDirectoryEnumerator*		enumerator;
	NSString*					entry;
	
	if(error)
	*error = nil;
	
	attributes = [self attributesOfItemAtPath:path error:error];
	if(attributes == nil)
	return NO;
	
	if([[attributes objectForKey:NSFileImmutable] boolValue]) {
		if(![self setAttributes:[NSDictionary dictionaryWithObject:[NSNumber numberWithBool:NO] forKey:NSFileImmutable] ofItemAtPath:path error:error])
		return NO;
	}
	
	if([[attributes objectForKey:NSFileType] isEqualToString:NSFileTypeDirectory]) {
		enumerator = [self enumeratorAtPath:path];
		if(enumerator == nil) {
			return NO;
		}
		attributes = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:NO] forKey:NSFileImmutable];
		for(entry in enumerator) {
			if([[[enumerator fileAttributes] objectForKey:NSFileImmutable] boolValue]) {
				if(![self setAttributes:attributes ofItemAtPath:[path stringByAppendingPathComponent:entry] error:error])
				return NO;
			}
		}
	}
	
	return [self removeItemAtPath:path error:error];
}

@end
