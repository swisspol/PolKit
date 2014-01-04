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

@interface DiskImageController : NSObject
+ (DiskImageController*) sharedDiskImageController;

- (BOOL) makeSparseDiskImageAtPath:(NSString*)path withName:(NSString*)name size:(NSUInteger)size password:(NSString*)password; //The path must have the ".sparseimage" extension and the size is in Kb
- (BOOL) makeSparseBundleDiskImageAtPath:(NSString*)path withName:(NSString*)name password:(NSString*)password; //The path must have the ".sparsebundle" extension
- (BOOL) makeDiskImageAtPath:(NSString*)path withName:(NSString*)name size:(NSUInteger)size password:(NSString*)password;

- (BOOL) makeCompressedDiskImageAtPath:(NSString*)path withName:(NSString*)name contentsOfDirectory:(NSString*)directory password:(NSString*)password; //The path must have the ".dmg" extension
- (BOOL) makeCompressedDiskImageAtPath:(NSString*)destinationPath withDiskImage:(NSString*)sourcePath password:(NSString*)password; //The destination path must have the ".dmg" extension - The source image must not be password protected

- (NSString*) mountDiskImage:(NSString*)imagePath atPath:(NSString*)mountPath password:(NSString*)password; //Public and verify
- (NSString*) mountDiskImage:(NSString*)imagePath atPath:(NSString*)mountPath usingShadowFile:(NSString*)shadowPath password:(NSString*)password private:(BOOL)private verify:(BOOL)verify;
- (BOOL) unmountDiskImageAtPath:(NSString*)mountPath force:(BOOL)force;

- (NSDictionary*) infoForDiskImageAtPath:(NSString*)path password:(NSString*)password;
- (BOOL) compactSparseDiskImage:(NSString*)path password:(NSString*)password;
@end
