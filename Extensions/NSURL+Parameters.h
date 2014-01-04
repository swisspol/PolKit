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

/*
-[NSURL user] returns nil if not defined or the un-escaped string otherwise
-[NSURL password] returns nil if not defined or the original string otherwise (possibly escaped)
-[NSURL path] returns empty string if not defined or the un-escaped string otherwise (also strips the suffix slash if any)
-[NSURL query] returns nil if not defined or the original string otherwise (possibly escaped)
*/
@interface NSURL (Parameters)
+ (NSURL*) URLWithScheme:(NSString*)scheme host:(NSString*)host path:(NSString*)path;
+ (NSURL*) URLWithScheme:(NSString*)scheme user:(NSString*)user password:(NSString*)password host:(NSString*)host port:(UInt16)port path:(NSString*)path;
+ (NSURL*) URLWithScheme:(NSString*)scheme user:(NSString*)user password:(NSString*)password host:(NSString*)host port:(UInt16)port path:(NSString*)path query:(NSString*)query;
- (NSString*) passwordByReplacingPercentEscapes;
- (NSString*) queryByReplacingPercentEscapes;
- (NSURL*) URLByDeletingPassword;
- (NSURL*) URLByDeletingUserAndPassword;
@end
