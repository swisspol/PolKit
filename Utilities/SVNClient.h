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

/*
- Required header search paths: "${SDKROOT}/usr/include/subversion-1" and "${SDKROOT}/usr/include/apr-1"
- Required libraries: "${SDKROOT}/usr/lib/libsvn_client-1.dylib", "${SDKROOT}/usr/lib/libsvn_subr-1.dylib" and "${SDKROOT}/usr/lib/libapr-1.dylib"
*/

#import <Foundation/Foundation.h>

@interface SVNClient : NSObject
{
@private
	NSString*			_path;
	void*				_masterPool;
	void*				_localPool;
	void*				_svnContext;
}
+ (void) setErrorReportingEnabled:(BOOL)flag;

+ (NSDictionary*) infoForURL:(NSString*)url;
+ (NSDictionary*) infoForPath:(NSString*)path;

+ (NSUInteger) checkOutURL:(NSString*)url toPath:(NSString*)path;
+ (NSUInteger) checkOutURL:(NSString*)url toPath:(NSString*)path revision:(NSUInteger)revision recursive:(BOOL)recursive ignoreExternals:(BOOL)ignore;
+ (NSUInteger) exportURL:(NSString*)url toPath:(NSString*)path;
+ (NSUInteger) exportURL:(NSString*)url toPath:(NSString*)path revision:(NSUInteger)revision recursive:(BOOL)recursive ignoreExternals:(BOOL)ignore;

+ (BOOL) importPath:(NSString*)path toURL:(NSString*)url withMessage:(NSString*)message;
+ (BOOL) createDirectoryAtURL:(NSString*)url withMessage:(NSString*)message;
+ (BOOL) copyURL:(NSString*)sourceURL toURL:(NSString*)destinationURL withMessage:(NSString*)message;
+ (BOOL) copyURL:(NSString*)sourceURL revision:(NSUInteger)revision toURL:(NSString*)destinationURL withMessage:(NSString*)message;
+ (BOOL) removeURL:(NSString*)url withMessage:(NSString*)message;

- (id) initWithRepositoryPath:(NSString*)directoryPath;

- (NSDictionary*) infoForPath:(NSString*)path;
- (NSDictionary*) statusForPath:(NSString*)path;

- (BOOL) cleanupPath:(NSString*)path;
- (NSUInteger) updatePath:(NSString*)path;
- (NSUInteger) updatePath:(NSString*)path revision:(NSUInteger)revision;
- (BOOL) createDirectory:(NSString*)name atPath:(NSString*)path;
- (BOOL) movePath:(NSString*)sourcePath toPath:(NSString*)destinationPath;
- (BOOL) copyPath:(NSString*)sourcePath toPath:(NSString*)destinationPath;
- (BOOL) addPath:(NSString*)path;
- (BOOL) removePath:(NSString*)path;
- (BOOL) commitPath:(NSString*)path withMessage:(NSString*)message;
- (BOOL) commitPaths:(NSArray*)paths withMessage:(NSString*)message;
- (BOOL) revertPath:(NSString*)path;

- (BOOL) setProperty:(NSString*)property forPath:(NSString*)path key:(NSString*)key;
- (BOOL) removePropertyForPath:(NSString*)path key:(NSString*)key;
- (NSString*) propertyForPath:(NSString*)path key:(NSString*)key;
- (NSDictionary*) propertiesForPath:(NSString*)path;
@end
