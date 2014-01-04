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

#import <libxml/parser.h>

#import "MiniXMLParser.h"

#define kPathSeparator			':'

@interface MiniXMLParser ()
@property(nonatomic, readonly) void* _namespace;
- (xmlNodePtr) _firstNodeAtUTF8Path:(const char*)path rootNode:(xmlNodePtr)node;
@end

@interface MiniXMLNode ()
- (id) initWithParser:(MiniXMLParser*)parser node:(xmlNodePtr)node;
@end

@implementation MiniXMLNode

- (id) initWithParser:(MiniXMLParser*)parser node:(xmlNodePtr)node
{
	if((self = [super init])) {
		_parser = [parser retain];
		_xmlNode = node;
	}
	
	return self;
}

- (void) dealloc
{
	[_value release];
	[_children release];
	[_name release];
	[_parser release];
	
	[super dealloc];
}

- (NSString*) name
{
	if(_name == nil)
	_name = [[NSString alloc] initWithUTF8String:(const char*)((xmlNodePtr)_xmlNode)->name];
	
	return _name;
}

- (NSArray*) _copyChildrenWithName:(NSString*)name
{
	NSMutableArray*		array = [NSMutableArray new];
	xmlNodePtr			child = ((xmlNodePtr)_xmlNode)->children;
	void*				namespace = [_parser _namespace];
	xmlChar*			string = (xmlChar*)[name UTF8String];
	MiniXMLNode*		node;
	
	while(child) {
		if((child->type == XML_ELEMENT_NODE) && (!namespace || (child->ns && child->ns->href && !xmlStrcmp(child->ns->href, namespace)))) {
			if(!string || (child->name && !xmlStrcmp(child->name, string))) {
				node = [[MiniXMLNode alloc] initWithParser:_parser node:child];
				[array addObject:node];
				[node release];
			}
		}
		child = child->next;
	}
	
	return array;
}

- (NSArray*) children
{
	if(_children == nil)
	_children = [self _copyChildrenWithName:nil];
	
	return _children;
}

- (NSString*) value
{
	xmlNodePtr			child = ((xmlNodePtr)_xmlNode)->children;
	
	if(_value == nil) {
		if(child && (child->next == NULL) && (child->type == XML_TEXT_NODE))
		_value = [[NSString alloc] initWithCString:(const char*)child->content encoding:NSUTF8StringEncoding];
	}
	
	return _value;
}

- (NSString*) firstValueAtSubpath:(NSString*)path
{
	xmlNodePtr			node = [_parser _firstNodeAtUTF8Path:[path UTF8String] rootNode:_xmlNode];
	
	if(node) {
		node = node->children;
		if(node && (node->type == XML_TEXT_NODE))
		return [NSString stringWithUTF8String:(const char*)node->content];
	}
	
	return nil;
}

- (MiniXMLNode*) firstNodeAtSubpath:(NSString*)path
{
	xmlNodePtr			node = [_parser _firstNodeAtUTF8Path:[path UTF8String] rootNode:_xmlNode];
	
	return (node ? [[[MiniXMLNode alloc] initWithParser:_parser node:node] autorelease] : nil);
}

- (NSArray*) childrenWithName:(NSString*)name
{
	return [[self _copyChildrenWithName:name] autorelease];
}

- (NSString*) description
{
	return [NSString stringWithFormat:@"<%@ | name = %s | content = %s>", [self class], ((xmlNodePtr)_xmlNode)->name, ((xmlNodePtr)_xmlNode)->content];
}

@end

@implementation MiniXMLParser

@synthesize _namespace=_namespace;

- (id) initWithXMLData:(NSData*)data nodeNamespace:(NSString*)namespace
{
	const char*			string = [namespace UTF8String];
	size_t				length;
	
	if((self = [super init])) {
		if(data)
		_xmlDoc = xmlParseMemory([data bytes], [data length]);
		if(!_xmlDoc || !xmlDocGetRootElement(_xmlDoc)) {
			[self release];
			return nil;
		}
		
		if(string && (length = strlen(string))) {
			_namespace = malloc(length + 1);
			bcopy(string, _namespace, length + 1);
		}
	}
	
	return self;
}

- (void) _cleanUp_MiniXMLParser
{
	if(_namespace)
	free(_namespace);
	if(_xmlDoc)
	xmlFreeDoc(_xmlDoc);
}

- (void) finalize
{
	[self _cleanUp_MiniXMLParser];
	
	[super finalize];
}

- (void) dealloc
{
	[self _cleanUp_MiniXMLParser];
	
	[super dealloc];
}

- (NSString*) nodeNamespace
{
	return (_namespace ? [NSString stringWithUTF8String:_namespace] : nil);
}

- (MiniXMLNode*) rootNode
{
	return [[[MiniXMLNode alloc] initWithParser:self node:xmlDocGetRootElement(_xmlDoc)] autorelease];
}

- (xmlNodePtr) _firstNodeAtUTF8Path:(const char*)path rootNode:(xmlNodePtr)node
{
	const char*			start = path;
	const char*			end = path;
	xmlNodePtr			child;
	xmlChar				buffer[256];
	
	if(path) {
		while(*end) {
			while(*end && (*end != kPathSeparator)) {
				++end;
			}
			if(end - start >= 256)
			break; //FIXME: Handle this situation better
			bcopy(start, buffer, end - start);
			buffer[end - start] = 0;
			
			child = node->children;
			while(child) {
				if((child->type == XML_ELEMENT_NODE) && (!_namespace || (child->ns && child->ns->href && !xmlStrcmp(child->ns->href, _namespace))) && !xmlStrcmp(child->name, buffer))
				break;
				child = child->next;
			}
			if(child == NULL)
			break;
			
			if(*end == kPathSeparator) {
				++end;
				start = end;
				node = child;
			}
			else
			return child;
		}
	}
	
	return NULL;
}

- (NSString*) firstValueAtPath:(NSString*)path
{
	xmlNodePtr			node = [self _firstNodeAtUTF8Path:[path UTF8String] rootNode:_xmlDoc];
	
	if(node) {
		node = node->children;
		if(node && (node->type == XML_TEXT_NODE))
		return [NSString stringWithUTF8String:(const char*)node->content];
	}
	
	return nil;
}

- (MiniXMLNode*) firstNodeAtPath:(NSString*)path
{
	xmlNodePtr			node = [self _firstNodeAtUTF8Path:[path UTF8String] rootNode:_xmlDoc];
	
	return (node ? [[[MiniXMLNode alloc] initWithParser:self node:node] autorelease] : nil);
}

static void _AppendNodeDescription(xmlNodePtr node, NSMutableString* string, NSString* prefix)
{
	if(!xmlIsBlankNode(node)) {
		if(node->ns && node->ns->prefix)
		[string appendFormat:@"%s:", node->ns->prefix];
		if(node->content)
		[string appendFormat:@"%@%s = %s\n", prefix, node->name, node->content];
		else
		[string appendFormat:@"%@%s\n", prefix, node->name];
		
		node = node->children;
		if(node) {
			prefix = [prefix stringByAppendingString:@"\t"];
			while(node) {
				_AppendNodeDescription(node, string, prefix);
				node = node->next;
			}
		}
	}
}

- (NSString*) description
{
	NSMutableString*	string = [NSMutableString string];
	
	_AppendNodeDescription(xmlDocGetRootElement(_xmlDoc), string, @"");
	
	return [NSString stringWithFormat:@"<%@>\n%@", [self class], string];
}

@end
