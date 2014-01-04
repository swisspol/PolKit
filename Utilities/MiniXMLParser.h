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
- Required header search path: "${SDKROOT}/usr/include/libxml2"
- Required library: "${SDKROOT}/usr/lib/libxml2.dylib"
*/

#import <Foundation/Foundation.h>

@class MiniXMLNode;

@interface MiniXMLParser : NSObject
{
@private
	void*				_xmlDoc;
	void*				_namespace;
}
- (id) initWithXMLData:(NSData*)data nodeNamespace:(NSString*)namespace;
@property(nonatomic, readonly) NSString* nodeNamespace;

@property(nonatomic, readonly) MiniXMLNode* rootNode;

- (NSString*) firstValueAtPath:(NSString*)path;
- (MiniXMLNode*) firstNodeAtPath:(NSString*)path;
@end

@interface MiniXMLNode : NSObject
{
@private
	MiniXMLParser*		_parser;
	void*				_xmlNode;
	NSString*			_name;
	NSArray*			_children;
	NSString*			_value;
}
@property(nonatomic, readonly) NSString* name;
@property(nonatomic, readonly) NSArray* children;
@property(nonatomic, readonly) NSString* value;
- (NSString*) firstValueAtSubpath:(NSString*)path;
- (MiniXMLNode*) firstNodeAtSubpath:(NSString*)path;
- (NSArray*) childrenWithName:(NSString*)name;
@end
