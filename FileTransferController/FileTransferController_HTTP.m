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
WebDAV: http://www.ietf.org/rfc/rfc2518.txt and http://msdn.microsoft.com/en-us/library/aa142917(EXCHG.65).aspx
Amazon S3: http://docs.amazonwebservices.com/AmazonS3/2006-03-01/index.html?RESTAPI.html
HTTP Status Codes: http://www.w3.org/Protocols/rfc2616/rfc2616-sec10.html
*/

#import <CommonCrypto/CommonHMAC.h>
#import <SystemConfiguration/SystemConfiguration.h>
#if TARGET_OS_IPHONE
#import <MobileCoreServices/MobileCoreServices.h>
#endif

#import "FileTransferController_Internal.h"
#import "NSURL+Parameters.h"
#import "DataStream.h"
#import "MiniXMLParser.h"
#if !TARGET_OS_IPHONE
#import "Keychain.h"
#endif

#define __LOG_HTTP_MESSAGES__ 0

#define kUpdateInterval					0.5
#define kFileBufferSize					(256 * 1024)
#define kDefaultHTTPError				@"Unsupported HTTP response"
#define	kAmazonAWSSuffix				@".amazonaws.com"

#define MAKE_HTTP_ERROR(__STATUS__, ...) MAKE_ERROR(@"http", __STATUS__, __VA_ARGS__)

@interface HTTPTransferController () <DataStreamSource>
+ (BOOL) hasUploadDataStream;
@property(nonatomic, readonly) CFHTTPMessageRef responseHeaders;
@end

/* Required for the compiler not to complain */
@interface StreamTransferController (DataStreamSource)
- (BOOL) openDataStream:(id)userInfo;
- (NSInteger) readDataFromStream:(id)userInfo buffer:(void*)buffer maxLength:(NSUInteger)length;
- (void) closeDataStream:(id)userInfo;
@end

static char* NewBase64Encode(const void *buffer, size_t length, bool separateLines, size_t *outputLength);

@implementation HTTPTransferController

@synthesize SSLCertificateValidationDisabled=_disableSSLCertificates, keepConnectionAlive=_keepAlive, responseHeaders=_responseHeaders;

+ (NSString*) urlScheme;
{
	return @"http";
}

+ (BOOL) hasAtomicUploads
{
	return YES;
}

+ (BOOL) hasUploadDataStream
{
	return NO;
}

- (void) invalidate
{
	if(_responseHeaders) {
		CFRelease(_responseHeaders);
		_responseHeaders = NULL;
	}
	
	[super invalidate];
}

- (CFHTTPMessageRef) _newHTTPRequestWithMethod:(NSString*)method url:(NSURL*)url
{
	NSString*				user = [[self baseURL] user];
	NSString*				password = [[self baseURL] passwordByReplacingPercentEscapes];
	CFHTTPMessageRef		message;
	
	message = (url ? CFHTTPMessageCreateRequest(kCFAllocatorDefault, (CFStringRef)method, (CFURLRef)url, kCFHTTPVersion1_1) : NULL);
	if(message == NULL)
	return NULL;
	
	if(user && password) {
		if(!CFHTTPMessageAddAuthentication(message, NULL, (CFStringRef)user, (CFStringRef)password, kCFHTTPAuthenticationSchemeBasic, false)) {
			CFRelease(message);
			return NULL;
		}
	}
	
	CFHTTPMessageSetHeaderFieldValue(message, CFSTR("User-Agent"), (CFStringRef)NSStringFromClass([self class]));
	
	return message;
}

- (CFHTTPMessageRef) _newHTTPRequestWithMethod:(NSString*)method path:(NSString*)path
{
	return [self _newHTTPRequestWithMethod:method url:[self absoluteURLForRemotePath:path]];
}

- (CFReadStreamRef) _newReadStreamWithHTTPRequest:(CFHTTPMessageRef)request bodyStream:(NSInputStream*)stream
{
	CFReadStreamRef			readStream = NULL;
	CFDictionaryRef			proxySettings;
	CFMutableDictionaryRef	sslSettings;
	
#if __LOG_HTTP_MESSAGES__
	NSLog(@"%@ [HTTP Request]\n%@", self, [[[NSString alloc] initWithData:[(id)CFHTTPMessageCopySerializedMessage(request) autorelease] encoding:NSUTF8StringEncoding] autorelease]);
#endif
	
	if(stream)
	readStream = CFReadStreamCreateForStreamedHTTPRequest(kCFAllocatorDefault, request, (CFReadStreamRef)stream);
	else {
		readStream = CFReadStreamCreateForHTTPRequest(kCFAllocatorDefault, request);
		CFReadStreamSetProperty(readStream, kCFStreamPropertyHTTPShouldAutoredirect, kCFBooleanTrue);
	}
	
	CFReadStreamSetProperty(readStream, kCFStreamPropertyHTTPAttemptPersistentConnection, (_keepAlive ? kCFBooleanTrue : kCFBooleanFalse));
	
	if([[[self class] urlScheme] isEqualToString:@"https"] && _disableSSLCertificates) {
		sslSettings = CFDictionaryCreateMutable(kCFAllocatorDefault, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
		CFDictionarySetValue(sslSettings, kCFStreamSSLValidatesCertificateChain, kCFBooleanFalse);
		CFReadStreamSetProperty(readStream, kCFStreamPropertySSLSettings, sslSettings); //kCFStreamSSLCertificates
		CFRelease(sslSettings);
	}
	
#if TARGET_OS_IPHONE
	if((proxySettings = CFNetworkCopySystemProxySettings()))
#else
	if((proxySettings = SCDynamicStoreCopyProxies(NULL)))
#endif
	{
    	CFReadStreamSetProperty(readStream, kCFStreamPropertyHTTPProxy, (proxySettings));
		CFRelease(proxySettings);
	}
	
	return readStream;
}

- (void) readStreamClientCallBack:(CFReadStreamRef)stream type:(CFStreamEventType)type
{
	CFStringRef					value;
	
	switch(type) {
		
		case kCFStreamEventHasBytesAvailable:
		if((_responseHeaders == NULL) && (_responseHeaders = (CFHTTPMessageRef)CFReadStreamCopyProperty(stream, kCFStreamPropertyHTTPResponseHeader))) {
			value = CFHTTPMessageCopyHeaderFieldValue(_responseHeaders, CFSTR("Content-Length"));
			if(value) {
				[self setMaxLength:[(NSString*)value integerValue]];
				CFRelease(value);
			}
		}
		break;
		
		case kCFStreamEventEndEncountered:
		if(_responseHeaders == NULL)
		_responseHeaders = (CFHTTPMessageRef)CFReadStreamCopyProperty(stream, kCFStreamPropertyHTTPResponseHeader);
		break;
		
	}
	
	[super readStreamClientCallBack:stream type:type];
}

- (id) processReadResultStream:(NSOutputStream*)stream userInfo:(id)info error:(NSError**)error
{
	NSInteger				status = (_responseHeaders ? CFHTTPMessageGetResponseStatusCode(_responseHeaders) : -1);
	NSString*				method = info;
	id						result = nil;
	NSString*				location;
	
	if(error)
	*error = nil;
	
#if __LOG_HTTP_MESSAGES__
	if([self isMemberOfClass:[HTTPTransferController class]])
	NSLog(@"%@ [HTTP Response]\n%@\n%@", self, [(id)(_responseHeaders ? CFHTTPMessageCopyResponseStatusLine(_responseHeaders) : NULL) autorelease], [(id)(_responseHeaders ? CFHTTPMessageCopyAllHeaderFields(_responseHeaders) : NULL) autorelease]);
#endif
	
	if([method isEqualToString:@"HEAD"]) {
		if((status == 200) || (status == 404))
		result = [NSMakeCollectable(CFHTTPMessageCopyRequestURL(_responseHeaders)) autorelease];
		else if((status == 301) || (status == 307)) {
			if((location = [NSMakeCollectable(CFHTTPMessageCopyHeaderFieldValue(_responseHeaders, CFSTR("Location"))) autorelease]))
			result = [NSURL URLWithString:location];
		}
	}
	else if([method isEqualToString:@"GET"]) {
		if(status == 200)
		result = [NSNumber numberWithBool:YES];
	}
	else if([method isEqualToString:@"PUT"]) {
		if((status == 200) || (status == 201) || (status == 204))
		result = [NSNumber numberWithBool:YES];
	}
	
	if((result == nil) && error && (*error == nil))
	*error = MAKE_HTTP_ERROR(status, kDefaultHTTPError);
	
	return result;
}

- (BOOL) _downloadFileFromPath:(NSString*)remotePath toStream:(NSOutputStream*)stream
{
	CFHTTPMessageRef		request;
	CFReadStreamRef			readStream;
	
	if(!stream || ([stream streamStatus] != NSStreamStatusNotOpen))
	return NO;
	
	request = [self _newHTTPRequestWithMethod:@"GET" path:remotePath];
	if(request == NULL)
	return NO;
	
	readStream = [self _newReadStreamWithHTTPRequest:request bodyStream:nil];
	CFRelease(request);
	
	return [[self runReadStream:readStream dataStream:stream userInfo:@"GET" isFileTransfer:YES] boolValue];
}

- (BOOL) openDataStream:(id)userInfo
{
	return ([userInfo isKindOfClass:[NSInputStream class]] ? [self openInputStream:userInfo isFileTransfer:YES] : [super openDataStream:userInfo]);
}

- (NSInteger) readDataFromStream:(id)userInfo buffer:(void*)buffer maxLength:(NSUInteger)length
{
	NSInteger				numBytes;
	
	if(![userInfo isKindOfClass:[NSInputStream class]])
	return [super readDataFromStream:userInfo buffer:buffer maxLength:length];
	
	//HACK: The StreamTransferController runloop is not necessarily running during the body upload, so we need to check for abort directly
	if(_hasShouldAbort && [[self delegate] fileTransferControllerShouldAbort:self])
	return -1;
	
	numBytes = [self readFromInputStream:userInfo bytes:buffer maxLength:length];
	if(numBytes > 0)
	[self setCurrentLength:([self currentLength] + numBytes)]; //FIXME: We could also use kCFStreamPropertyHTTPRequestBytesWrittenCount
	
	return numBytes;	
}

- (void) closeDataStream:(id)userInfo
{
	if([userInfo isKindOfClass:[NSInputStream class]])
	[self closeInputStream:userInfo];
	else
	[super closeDataStream:userInfo];
}

- (BOOL) _uploadFileToPath:(NSString*)remotePath fromStream:(NSInputStream*)stream
{
	NSString*				type = nil;
	NSString*				UTI;
	CFHTTPMessageRef		request;
	CFReadStreamRef			readStream;
	NSURL*					finalURL;
	
	if(!stream || ([stream streamStatus] != NSStreamStatusNotOpen))
	return NO;
	
	//HACK: Send a HEAD first to see if we have a redirect on this URL as CFReadStreamCreateForStreamedHTTPRequest() doesn't handle redirects
	finalURL = [self finalURLForPath:remotePath];
	if(finalURL == nil)
	return NO;
	
	//HACK: Force CFReadStreamCreateForStreamedHTTPRequest() to go through our stream methods by using a DataStream wrapper
	_hasShouldAbort = [[self delegate] respondsToSelector:@selector(fileTransferControllerShouldAbort:)];
	stream = [[[DataReadStream alloc] initWithDataSource:self userInfo:stream] autorelease];
	if(stream == nil)
	return NO;
	
	request = [self _newHTTPRequestWithMethod:@"PUT" url:finalURL];
	if(request == NULL)
	return NO;
	
	if([[remotePath pathExtension] length]) {
		UTI = (NSString*)[NSMakeCollectable(UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (CFStringRef)[remotePath pathExtension], NULL)) autorelease];
		if([UTI length])
		type = (NSString*)[NSMakeCollectable(UTTypeCopyPreferredTagWithClass((CFStringRef)UTI, kUTTagClassMIMEType)) autorelease];
	}
	if(![type length])
	type = @"application/octet-stream";
	CFHTTPMessageSetHeaderFieldValue(request, CFSTR("Content-Type"), (CFStringRef)type);
	
	if([self maxLength] > 0)
	CFHTTPMessageSetHeaderFieldValue(request, CFSTR("Content-Length"), (CFStringRef)[NSString stringWithFormat:@"%i", [self maxLength]]);
	
	readStream = [self _newReadStreamWithHTTPRequest:request bodyStream:stream];
	CFRelease(request);
	
	return [[self runReadStream:readStream dataStream:([[self class] hasUploadDataStream] ? [NSOutputStream outputStreamToMemory] : nil) userInfo:@"PUT" isFileTransfer:YES] boolValue];
}

- (NSURL*) finalURLForPath:(NSString*)remotePath
{
	CFHTTPMessageRef		request;
	CFReadStreamRef			stream;
	
	request = [self _newHTTPRequestWithMethod:@"HEAD" path:remotePath];
	if(request == NULL)
	return nil;
	
	stream = [self _newReadStreamWithHTTPRequest:request bodyStream:nil];
	CFRelease(request);
	
	return [self runReadStream:stream dataStream:([[self class] hasUploadDataStream] ? [NSOutputStream outputStreamToMemory] : nil) userInfo:@"HEAD" isFileTransfer:NO];
}

@end

@implementation SecureHTTPTransferController

+ (NSString*) urlScheme;
{
	return @"https";
}

@end

@implementation WebDAVTransferController

static NSDictionary* _DictionaryFromDAVProperties(MiniXMLNode* node)
{
	static NSDateFormatter*	formatter1 = nil; //FIXME: Is this class really thread-safe?
	static NSDateFormatter*	formatter2 = nil; //FIXME: Is this class really thread-safe?
	NSMutableDictionary*	dictionary = [NSMutableDictionary dictionary];
	NSString*				string;
	
	if(formatter1 == nil) {
		formatter1 = [NSDateFormatter new];
        [formatter1 setLocale:[[[NSLocale alloc] initWithLocaleIdentifier:@"en_US"] autorelease]];
		[formatter1 setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
		[formatter1 setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss'Z'"]; //FIXME: We ignore Z and assume UTC
	}
	if(formatter2 == nil) {
		formatter2 = [NSDateFormatter new];
		[formatter2 setLocale:[[[NSLocale alloc] initWithLocaleIdentifier:@"en_US"] autorelease]];
		[formatter2 setDateFormat:@"EEE, d MMM yyyy HH:mm:ss zzz"];
	}
	
	if([node firstNodeAtSubpath:@"resourcetype:collection"])
	[dictionary setObject:NSFileTypeDirectory forKey:NSFileType];
	else
	[dictionary setObject:NSFileTypeRegular forKey:NSFileType];
	
	if((string = [node firstValueAtSubpath:@"creationdate"]))
	[dictionary setValue:[formatter1 dateFromString:string] forKey:NSFileCreationDate];
	
	if((string = [node firstValueAtSubpath:@"modificationdate"]))
	[dictionary setValue:[formatter1 dateFromString:string] forKey:NSFileModificationDate];
	else if((string = [node firstValueAtSubpath:@"getlastmodified"]))
	[dictionary setValue:[formatter2 dateFromString:string] forKey:NSFileModificationDate];	
	
	if((string = [node firstValueAtSubpath:@"getcontentlength"]))
	[dictionary setValue:[NSNumber numberWithInteger:[string integerValue]] forKey:NSFileSize];
	
	return dictionary;
}	

- (id) processReadResultStream:(NSOutputStream*)stream userInfo:(id)info error:(NSError**)error
{
	NSData*					data = [stream propertyForKey:NSStreamDataWrittenToMemoryStreamKey];
	CFHTTPMessageRef		responseHeaders = [self responseHeaders];
	NSInteger				status = (responseHeaders ? CFHTTPMessageGetResponseStatusCode(responseHeaders) : -1);
	NSString*				method = info;
	NSStringEncoding		encoding = NSUTF8StringEncoding;
	id						result = nil;
	id						body = nil;
	NSString*				mime = nil;
	NSString*				type;
	NSRange					range;
	MiniXMLNode*			node;
	NSString*				path;
	
	if(error)
	*error = nil;
	
#if __LOG_HTTP_MESSAGES__
	NSLog(@"%@ [HTTP Response]\n%@\n%@", self, [(id)(responseHeaders ? CFHTTPMessageCopyResponseStatusLine(responseHeaders) : NULL) autorelease], [(id)(responseHeaders ? CFHTTPMessageCopyAllHeaderFields(responseHeaders) : NULL) autorelease]);
#endif
	
	if(responseHeaders && [data length]) {
		type = [(NSString*)[NSMakeCollectable(CFHTTPMessageCopyHeaderFieldValue(responseHeaders, CFSTR("Content-Type"))) autorelease] lowercaseString];
		if([type length]) {
			range = [type rangeOfString:@";" options:0 range:NSMakeRange(0, [type length])];
			if(range.location != NSNotFound)
			mime = [type substringToIndex:range.location];
			else
			mime = type;
			
			range = [type rangeOfString:@"charset=" options:0 range:NSMakeRange(0, [type length])];
			if(range.location != NSNotFound) {
				type = [type substringFromIndex:(range.location + range.length)];
				range = [type rangeOfString:@";" options:0 range:NSMakeRange(0, [type length])]; //FIXME: Should we trim spaces?
				if(range.location != NSNotFound)
				type = [type substringToIndex:range.location];
				if([type hasPrefix:@"\""] && [type hasSuffix:@"\""])
				type = [type substringWithRange:NSMakeRange(1, [type length] - 2)];
				encoding = CFStringConvertIANACharSetNameToEncoding((CFStringRef)type);
				if(encoding != kCFStringEncodingInvalidId)
				encoding = CFStringConvertEncodingToNSStringEncoding(encoding);
				else {
					NSLog(@"%s: Invalid charset value \"%@\"", __FUNCTION__, type);
					encoding = NSUTF8StringEncoding;
				}
			}
		}
		
		if([mime isEqualToString:@"text/plain"])
		body = [[NSString alloc] initWithData:data encoding:encoding];
		else if([mime isEqualToString:@"text/xml"] || [mime isEqualToString:@"application/xml"]) {
			body = [[MiniXMLParser alloc] initWithXMLData:data nodeNamespace:@"DAV:"];
			if((body == nil) && error)
			*error = MAKE_FILETRANSFERCONTROLLER_ERROR(@"Invalid XML response");
		}
		else if([mime length]) {
			if(error)
			*error = MAKE_FILETRANSFERCONTROLLER_ERROR(@"Unsupported MIME type \"%@\"", mime);
		}
	}
	
	if([method isEqualToString:@"PROPFIND"]) {
		if((status == 207) && [body isKindOfClass:[MiniXMLParser class]]) {
			result = [NSMutableDictionary dictionary];
			path = (id)kCFNull;
			for(node in [[(MiniXMLParser*)body firstNodeAtPath:@"multistatus"] children]) {
				if(path == (id)kCFNull) {
					path = nil;
					continue;
				}
				path = [[[node firstValueAtSubpath:@"href"] lastPathComponent] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
				if(path)
				[result setObject:_DictionaryFromDAVProperties([node firstNodeAtSubpath:@"propstat:prop"]) forKey:path];
			}
		}
	}
	else if([method isEqualToString:@"MOVE"] || [method isEqualToString:@"COPY"]) {
		if((status == 201) || (status == 204))
		result = [NSNumber numberWithBool:YES];
	}
	else if([method isEqualToString:@"DELETE"]) {
		if((status == 204) || (status == 404))
		result = [NSNumber numberWithBool:YES];
	}
	else if([method isEqualToString:@"MKCOL"]) {
		if(status == 201)
		result = [NSNumber numberWithBool:YES];
	}
	else
	result = [super processReadResultStream:stream userInfo:info error:error];
	
	[body release];
	
	if((result == nil) && error && (*error == nil))
	*error = MAKE_HTTP_ERROR(status, kDefaultHTTPError);
	
	return result;
}

- (NSDictionary*) contentsOfDirectoryAtPath:(NSString*)remotePath
{
	CFHTTPMessageRef		request;
	CFReadStreamRef			stream;
	
	if(![remotePath length])
	remotePath = @"/";
	else if(![remotePath hasSuffix:@"/"])
	remotePath = [remotePath stringByAppendingString:@"/"];
	
	request = [self _newHTTPRequestWithMethod:@"PROPFIND" path:remotePath];
	if(request == NULL)
	return nil;
	CFHTTPMessageSetHeaderFieldValue(request, CFSTR("Depth"), CFSTR("1"));
	CFHTTPMessageSetHeaderFieldValue(request, CFSTR("Brief"), CFSTR("T"));
	
	stream = [self _newReadStreamWithHTTPRequest:request bodyStream:nil];
	CFRelease(request);
	
	return [self runReadStream:stream dataStream:[NSOutputStream outputStreamToMemory] userInfo:@"PROPFIND" isFileTransfer:NO];
}

- (BOOL) createDirectoryAtPath:(NSString*)remotePath
{
	CFHTTPMessageRef		request;
	CFReadStreamRef			stream;
	
	request = [self _newHTTPRequestWithMethod:@"MKCOL" path:remotePath];
	if(request == NULL)
	return NO;
	
	stream = [self _newReadStreamWithHTTPRequest:request bodyStream:nil];
	CFRelease(request);
	
	return [[self runReadStream:stream dataStream:nil userInfo:@"MKCOL" isFileTransfer:NO] boolValue];
}

- (BOOL) _movePath:(NSString*)fromRemotePath toPath:(NSString*)toRemotePath copy:(BOOL)copy
{
	CFHTTPMessageRef		request;
	CFReadStreamRef			stream;
	
	request = [self _newHTTPRequestWithMethod:(copy ? @"COPY" : @"MOVE") path:fromRemotePath];
	if(request == NULL)
	return NO;
#if 0
	CFHTTPMessageSetHeaderFieldValue(request, CFSTR("Destination"), (CFStringRef)[[[self baseURL] path] stringByAppendingPathComponent:[toRemotePath stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]]);
#else
	CFHTTPMessageSetHeaderFieldValue(request, CFSTR("Destination"), (CFStringRef)[[self absoluteURLForRemotePath:toRemotePath] absoluteString]);
#endif
	CFHTTPMessageSetHeaderFieldValue(request, CFSTR("Overwrite"), CFSTR("T"));
	
	stream = [self _newReadStreamWithHTTPRequest:request bodyStream:nil];
	CFRelease(request);
	
	return [[self runReadStream:stream dataStream:nil userInfo:(copy ? @"COPY" : @"MOVE") isFileTransfer:NO] boolValue];
}

- (BOOL) movePath:(NSString*)fromRemotePath toPath:(NSString*)toRemotePath
{
	return [self _movePath:fromRemotePath toPath:toRemotePath copy:NO];
}

- (BOOL) copyPath:(NSString*)fromRemotePath toPath:(NSString*)toRemotePath
{
	return [self _movePath:fromRemotePath toPath:toRemotePath copy:YES];
}

- (BOOL) _deletePath:(NSString*)remotePath
{
	CFHTTPMessageRef		request;
	CFReadStreamRef			stream;
	
	request = [self _newHTTPRequestWithMethod:@"DELETE" path:remotePath];
	if(request == NULL)
	return NO;
	
	stream = [self _newReadStreamWithHTTPRequest:request bodyStream:nil];
	CFRelease(request);
	
	return [[self runReadStream:stream dataStream:nil userInfo:@"DELETE" isFileTransfer:NO] boolValue];
}

- (BOOL) deleteFileAtPath:(NSString*)remotePath
{
	return [self _deletePath:remotePath];
}

- (BOOL) deleteDirectoryRecursivelyAtPath:(NSString*)remotePath
{
	//NOTE: Some servers require the trailing slash, while some others don't
	if(![remotePath hasSuffix:@"/"])
	remotePath = [remotePath stringByAppendingString:@"/"];
	
	return [self _deletePath:remotePath];
}

@end

@implementation WebDAVTransferController (iDisk)

- (id) initWithIDiskForLocalUser:(NSString*)basePath
{
	return [self initWithIDiskForUser:nil basePath:basePath];
}

- (id) initWithIDiskForUser:(NSString*)username basePath:(NSString*)basePath
{
	return [self initWithIDiskForUser:username password:nil basePath:basePath];
}

- (id) initWithIDiskForUser:(NSString*)username password:(NSString*)password basePath:(NSString*)basePath
{
#if !TARGET_OS_IPHONE
	if(username == nil)
	username = [[NSUserDefaults standardUserDefaults] stringForKey:@"iToolsMember"];
	
	if([username length] && (password == nil))
	password = [[Keychain sharedKeychain] genericPasswordForService:@"iTools" account:username];
#endif
	
	if([username length] && ![username isEqualToString:@"public"] && ![basePath hasSuffix:[NSString stringWithFormat:@"/%@", username]] && ![basePath hasPrefix:[NSString stringWithFormat:@"/%@/", username]])
	basePath = [[NSString stringWithFormat:@"/%@", username] stringByAppendingPathComponent:basePath];
	
	return [self initWithHost:kFileTransferHost_iDisk port:0 username:username password:password basePath:basePath];
}

@end

@implementation SecureWebDAVTransferController

+ (NSString*) urlScheme;
{
	return @"https";
}

- (id) initWithIDiskForUser:(NSString*)username password:(NSString*)password basePath:(NSString*)basePath
{
	[self doesNotRecognizeSelector:_cmd];
	return nil;
}

@end

@implementation AmazonS3TransferController

@synthesize productToken=_productToken, userToken=_userToken, newBucketLocation=_newBucketLocation;

+ (NSDictionary*) activateDesktopProduct:(NSString*)productToken activationKey:(NSString*)activationKey expirationInterval:(NSTimeInterval)expirationInterval error:(NSError**)error
{
	NSOutputStream*				stream = [NSOutputStream outputStreamToMemory];
	NSMutableDictionary*		dictionary = nil;
	NSString*					string;
	HTTPTransferController*		transferController;
	NSData*						data;
	BOOL						success;
	NSURL*						url;
	MiniXMLParser*				parser;
	MiniXMLNode*				node;
	
	if(error)
	*error = nil;
	
	if(![productToken length] || ![activationKey length])
	return nil;
	
	string = [NSString stringWithFormat:@"https://ls.amazonaws.com/?Action=ActivateDesktopProduct&ActivationKey=%@&ProductToken=%@%@&Version=2008-04-28", activationKey, productToken, (expirationInterval > 0.0 ? [NSString stringWithFormat:@"&TokenExpiration=PT%.0fS", expirationInterval] : @"")]; //NOTE: http://en.wikipedia.org/wiki/ISO_8601#Durations
	url = [NSURL URLWithString:[string stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
	transferController = [[SecureHTTPTransferController alloc] initWithBaseURL:url];
	success = [transferController downloadFileFromPath:nil toStream:stream];
	[transferController release];
	
	data = [stream propertyForKey:NSStreamDataWrittenToMemoryStreamKey];
	if([data length]) {
		parser = [[MiniXMLParser alloc] initWithXMLData:data nodeNamespace:nil];
		if(parser) {
			if(success && (node = [parser firstNodeAtPath:@"ActivateDesktopProductResult"])) {
				dictionary = [NSMutableDictionary dictionary];
				[dictionary setValue:[node firstValueAtSubpath:@"UserToken"] forKey:kAmazonS3ActivationInfo_UserToken];
				[dictionary setValue:[node firstValueAtSubpath:@"AWSAccessKeyId"] forKey:kAmazonS3ActivationInfo_AccessKeyID];
				[dictionary setValue:[node firstValueAtSubpath:@"SecretAccessKey"] forKey:kAmazonS3ActivationInfo_SecretAccessKey];
				if([dictionary count] != 3) {
					if(error)
					*error = MAKE_ERROR(@"s3", -1, (string ? @"%@" : @"Incomplete response"), string);
					dictionary = nil;
				}
			}
			else if(error) {
				string = [parser firstValueAtPath:@"Error:Message"];
				if(string == nil)
				string = [parser firstValueAtPath:@"Error:Code"];
				*error = MAKE_ERROR(@"s3", -1, (string ? @"%@" : @"Invalid response"), string);
			}
			[parser release];
		}
		else {
			if(error)
			*error = MAKE_ERROR(@"s3", -1, @"Failed parsing response");
		}
	}
	else if(error)
	*error = MAKE_ERROR(@"s3", -1, @"Failed retrieving activation data");

	return dictionary;
}

/* http://docs.amazonwebservices.com/AmazonS3/latest/BucketRestrictions.html */
+ (BOOL) isBucketNameValid:(NSString*)name
{
	static NSMutableCharacterSet*	bucketCharacterSet = nil;
	
	//NOTE: We don't allow periods or dashes either which simplifies rules checking
	if(bucketCharacterSet == nil) {
		bucketCharacterSet = [NSMutableCharacterSet new];
		[bucketCharacterSet formUnionWithCharacterSet:[NSCharacterSet lowercaseLetterCharacterSet]];
		[bucketCharacterSet formUnionWithCharacterSet:[NSCharacterSet decimalDigitCharacterSet]];
		[bucketCharacterSet formUnionWithCharacterSet:[NSCharacterSet characterSetWithCharactersInString:@"-"]];
		[bucketCharacterSet invert];
	}
	
	if(([name length] < 3) && ([name length] > 63))
	return NO;
	if([name rangeOfCharacterFromSet:bucketCharacterSet].location != NSNotFound)
	return NO;
	if([name characterAtIndex:([name length] - 1)] == '-')
	return NO;
	
	return YES;
}

+ (BOOL) hasUploadDataStream
{
	return YES;
}

- (id) initWithBaseURL:(NSURL*)url
{
	if(![[url host] hasSuffix:kFileTransferHost_AmazonS3] || [url port] || ![url user] || ![url passwordByReplacingPercentEscapes] || (![[url host] isEqualToString:kFileTransferHost_AmazonS3] && [[url path] length])) {
		[self release];
		return nil;
	}
	
	return [super initWithBaseURL:url];
}

- (id) initWithAccessKeyID:(NSString*)accessKeyID secretAccessKey:(NSString*)secretAccessKey bucket:(NSString*)bucket
{
	if(![accessKeyID length] || ![secretAccessKey length]) {
		[self release];
		return nil;
	}
	
	return [self initWithHost:([bucket length] ? [NSString stringWithFormat:@"%@.%@", bucket, kFileTransferHost_AmazonS3] : kFileTransferHost_AmazonS3) port:0 username:accessKeyID password:secretAccessKey basePath:nil];
}

- (void) dealloc
{
	[_userToken release];
	[_productToken release];
	
	[super dealloc];
}

/* Override completely */
- (NSURL*) absoluteURLForRemotePath:(NSString*)path
{
	NSString*				host = [[self baseURL] host];
	NSRange					range;
	NSString*				query;
	NSURL*					url;
	
	range = [path rangeOfString:@"?"];
	if(range.location != NSNotFound) {
		query = [path substringFromIndex:(range.location + range.length)];
		path = [path substringToIndex:range.location];
	}
	else
	query = nil;
	
	path = [self absolutePathForRemotePath:path];
	if([host isEqualToString:kFileTransferHost_AmazonS3] && ![path isEqualToString:@"/"]) {
		range = [path rangeOfString:@"/" options:0 range:NSMakeRange(1, [path length] - 1)];
		if(range.location == NSNotFound) {
			host = [NSString stringWithFormat:@"%@.%@", [path substringFromIndex:1], kFileTransferHost_AmazonS3];
			path = nil;
		}
		else {
			host = [NSString stringWithFormat:@"%@.%@", [path substringWithRange:NSMakeRange(1, range.location - 1)], kFileTransferHost_AmazonS3];
			path = [path substringWithRange:NSMakeRange(range.location + 1, [path length] - range.location - 1)];
		}
	}
	
	url = [NSURL URLWithScheme:[[self class] urlScheme] user:nil password:nil host:host port:0 path:path query:query];
	if(![[url host] hasSuffix:kAmazonAWSSuffix])
	return nil;
	
	return url;
}

static NSData* _ComputeSHA1HMAC(NSData* data, NSString* key)
{
	NSMutableData*				hash = [NSMutableData dataWithLength:CC_SHA1_DIGEST_LENGTH];
	const char*					keyString = [key UTF8String];
	
	CCHmac(kCCHmacAlgSHA1, keyString, strlen(keyString), [data bytes], [data length], [hash mutableBytes]);
	
	return hash;
}

static NSString* _EncodeBase64(NSData* data)
{
	NSString*				string = nil;
	char*					buffer;
	size_t					length;
	
	buffer = NewBase64Encode([data bytes], [data length], false, &length);
	if(buffer) {
		string = [[[NSString alloc] initWithBytes:buffer length:length encoding:NSUTF8StringEncoding] autorelease];
		free(buffer);
	}
	
	return string;
}

/* See http://docs.amazonwebservices.com/AmazonS3/2006-03-01/index.html?RESTAuthentication.html */
- (CFReadStreamRef) _newReadStreamWithHTTPRequest:(CFHTTPMessageRef)request bodyStream:(id)stream
{
	static NSDateFormatter*	formatter = nil; //FIXME: Is this class really thread-safe?
	NSURL*					url = [NSMakeCollectable(CFHTTPMessageCopyRequestURL(request)) autorelease];
	NSString*				query = [url query];
	NSString*				host = [url host];
	NSMutableString*		amzHeaders = [NSMutableString string];
	NSMutableString*		buffer;
	NSString*				authorization;
	NSString*				dateString;
	NSDictionary*			headers;
	NSString*				header;
	NSRange					range;
	
	if(formatter == nil) {
		formatter = [NSDateFormatter new];
		[formatter setLocale:[[[NSLocale alloc] initWithLocaleIdentifier:@"en_US"] autorelease]];
		[formatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
		[formatter setDateFormat:@"EEE, d MMM yyyy HH:mm:ss Z"];
	}
	
	dateString = [formatter stringFromDate:[NSDate date]];
	CFHTTPMessageSetHeaderFieldValue(request, CFSTR("Date"), (CFStringRef)dateString);
	
	if(_productToken && _userToken)
	CFHTTPMessageSetHeaderFieldValue(request, CFSTR("x-amz-security-token"), (CFStringRef)[NSString stringWithFormat:@"%@,%@", _productToken, _userToken]);
	
	headers = [NSMakeCollectable(CFHTTPMessageCopyAllHeaderFields(request)) autorelease];
	buffer = [NSMutableString new];
	[buffer appendFormat:@"%@\n", [NSMakeCollectable(CFHTTPMessageCopyRequestMethod(request)) autorelease]];
	[buffer appendFormat:@"%@\n", ([headers objectForKey:@"Content-MD5"] ? [headers objectForKey:@"Content-MD5"] : @"")];
	[buffer appendFormat:@"%@\n", ([headers objectForKey:@"Content-Type"] ? [headers objectForKey:@"Content-Type"] : @"")];
	[buffer appendFormat:@"%@\n", dateString];
	for(header in [[headers allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
		if([header hasPrefix:@"X-Amz-"])
		[amzHeaders appendFormat:@"%@:%@\n", [header lowercaseString], [headers objectForKey:header]];
	}
	[buffer appendString:amzHeaders];
	if([host isEqualToString:kFileTransferHost_AmazonS3])
	[buffer appendString:@"/"];
	else {
		range = [host rangeOfString:@"." options:NSBackwardsSearch range:NSMakeRange(0, [host length] - [kAmazonAWSSuffix length])];
		if(range.location == NSNotFound)
		range.location = [host length]; //NOTE: This is not supposed to ever happen
		if([[url path] length])
		[buffer appendFormat:@"/%@%@", [host substringToIndex:range.location], [url path]];
		else
		[buffer appendFormat:@"/%@/", [host substringToIndex:range.location]];
	}
	if([query isEqualToString:@"location"] || [query isEqualToString:@"logging"] || [query isEqualToString:@"torrent"])
	[buffer appendFormat:@"?%@", query];
	authorization = _EncodeBase64(_ComputeSHA1HMAC([buffer dataUsingEncoding:NSUTF8StringEncoding], [[self baseURL] passwordByReplacingPercentEscapes]));
	[buffer release];
	
	CFHTTPMessageSetHeaderFieldValue(request, CFSTR("Authorization"), (CFStringRef)[NSString stringWithFormat:@"AWS %@:%@", [[self baseURL] user], authorization]);
	
	return [super _newReadStreamWithHTTPRequest:request bodyStream:stream];
}

static NSDictionary* _DictionaryFromS3Buckets(MiniXMLNode* node)
{
	static NSDateFormatter*	formatter = nil; //FIXME: Is this class really thread-safe?
	NSMutableDictionary*	dictionary = [NSMutableDictionary dictionary];
	NSString*				string;
	
	if(formatter == nil) {
		formatter = [NSDateFormatter new];
		[formatter setLocale:[[[NSLocale alloc] initWithLocaleIdentifier:@"en_US"] autorelease]];
		[formatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
		[formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"]; //FIXME: We ignore Z and assume UTC
	}
	
	[dictionary setObject:NSFileTypeDirectory forKey:NSFileType];
	
	if((string = [node firstValueAtSubpath:@"CreationDate"]))
	[dictionary setValue:[formatter dateFromString:string] forKey:NSFileCreationDate]; //FIXME: We ignore Z and assume UTC (%z)
	
	return dictionary;
}	

static NSDictionary* _DictionaryFromS3Objects(MiniXMLNode* node, NSString* basePath, NSString** path)
{
	static NSDateFormatter*	formatter = nil; //FIXME: Is this class really thread-safe?
	NSMutableDictionary*	dictionary = [NSMutableDictionary dictionary];
	BOOL					isDirectory = NO;
	NSString*				string;
	NSRange					range;
	
	if(formatter == nil) {
		formatter = [NSDateFormatter new];
		[formatter setLocale:[[[NSLocale alloc] initWithLocaleIdentifier:@"en_US"] autorelease]];
		[formatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
		[formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"]; //FIXME: We ignore Z and assume UTC
	}
	
	string = [node firstValueAtSubpath:@"Key"];
	if(basePath) {
		range = [string rangeOfString:@"/" options:0 range:NSMakeRange([basePath length] + 1, [string length] - [basePath length] - 1)];
		if((range.location != NSNotFound) && (range.location != [string length] - 1))
		return nil;
		
		if([string characterAtIndex:([string length] - 1)] == '/')
		isDirectory = YES;
		
		*path = [string lastPathComponent];
		if(isDirectory && [*path isEqualToString:basePath])
		return nil;
		
		[dictionary setObject:(isDirectory ? NSFileTypeDirectory : NSFileTypeRegular) forKey:NSFileType];
	}
	else
	*path = string;
	
	if((string = [node firstValueAtSubpath:@"LastModified"]))
	[dictionary setValue:[formatter dateFromString:string] forKey:NSFileModificationDate];
	
	if(isDirectory == NO) {
		if((string = [node firstValueAtSubpath:@"Size"]))
		[dictionary setValue:[NSNumber numberWithInteger:[string integerValue]] forKey:NSFileSize];
	}
	
	return dictionary;
}	

- (id) processReadResultStream:(NSOutputStream*)stream userInfo:(id)info error:(NSError**)error
{
	NSData*					data = [stream propertyForKey:NSStreamDataWrittenToMemoryStreamKey];
	CFHTTPMessageRef		responseHeaders = [self responseHeaders];
	NSInteger				status = (responseHeaders ? CFHTTPMessageGetResponseStatusCode(responseHeaders) : -1);
	NSString*				method = info;
	id						result = nil;
	id						body = nil;
	NSString*				mime = nil;
	NSString*				type;
	NSRange					range;
	MiniXMLNode*			node;
	NSDictionary*			properties;
	NSString*				path;
	NSString*				string;
	NSMutableDictionary*	dictionary;
	
	if(error)
	*error = nil;
	
#if __LOG_HTTP_MESSAGES__
	NSLog(@"%@ [HTTP Response]\n%@\n%@", self, [(id)(responseHeaders ? CFHTTPMessageCopyResponseStatusLine(responseHeaders) : NULL) autorelease], [(id)(responseHeaders ? CFHTTPMessageCopyAllHeaderFields(responseHeaders) : NULL) autorelease]);
#endif
	
	if(responseHeaders && [data length]) {
		type = [(NSString*)[NSMakeCollectable(CFHTTPMessageCopyHeaderFieldValue(responseHeaders, CFSTR("Content-Type"))) autorelease] lowercaseString];
		if([type length]) {
			range = [type rangeOfString:@";" options:0 range:NSMakeRange(0, [type length])];
			if(range.location != NSNotFound)
			mime = [type substringToIndex:range.location];
			else
			mime = type;
		}
		
		if([mime isEqualToString:@"application/xml"]) {
			body = [[MiniXMLParser alloc] initWithXMLData:data nodeNamespace:nil];
			if((body == nil) && error)
			*error = MAKE_FILETRANSFERCONTROLLER_ERROR(@"Invalid XML response");
		}
		else if([mime length]) {
			if(error)
			*error = MAKE_FILETRANSFERCONTROLLER_ERROR(@"Unsupported MIME type \"%@\"", mime);
		}
	}
	
	if([method isEqualToString:@"GET/"]) {
		if((status == 200) && [body isKindOfClass:[MiniXMLParser class]]) {
			string = [[(MiniXMLParser*)body rootNode] name];
			if([string isEqualToString:@"ListBucketResult"]) {
				dictionary = [NSMutableDictionary new];
				result = [NSMutableDictionary dictionary];
				for(node in [[(MiniXMLParser*)body rootNode] children]) {
					string = [node name];
					if([string isEqualToString:@"Contents"]) {
						properties = _DictionaryFromS3Objects(node, nil, &path);
						if(properties)
						[result setObject:properties forKey:path];
					}
					else if(string)
					[dictionary setValue:[node value] forKey:string];
				}
				[result setObject:dictionary forKey:[NSNull null]];
				[dictionary release];
			}
			else if([string isEqualToString:@"ListAllMyBucketsResult"]) {
				result = [NSMutableDictionary dictionary];
				for(node in [[(MiniXMLParser*)body firstNodeAtPath:@"ListAllMyBucketsResult:Buckets"] children]) {
					path = [node firstValueAtSubpath:@"Name"];
					if(path)
					[result setObject:_DictionaryFromS3Buckets(node) forKey:path];
				}
			}
		}
	}
	else if([method isEqualToString:@"GET?"]) {
		if((status == 200) && [body isKindOfClass:[MiniXMLParser class]]) {
			node = [(MiniXMLParser*)body rootNode];
			if([[node name] isEqualToString:@"LocationConstraint"]) {
				result = [node value];
				if(result == nil)
				result = @"";
			}
		}
	}
	else if([method isEqualToString:@"DELETE"]) {
		if(status == 204)
		result = [NSNumber numberWithBool:YES];
	}
	else if([method isEqualToString:@"COPY"]) {
		if((status == 200) && [body isKindOfClass:[MiniXMLParser class]] && [[[(MiniXMLParser*)body rootNode] name] isEqualToString:@"CopyObjectResult"])
		result = [NSNumber numberWithBool:YES];
	}
	else
	result = [super processReadResultStream:stream userInfo:info error:error];
	
	if((result == nil) && error && ((*error == nil) || [[*error localizedDescription] isEqualToString:kDefaultHTTPError])) {
		if([body isKindOfClass:[MiniXMLParser class]]) {
			string = [(MiniXMLParser*)body firstValueAtPath:@"Error:Message"];
			if(string == nil)
			string = [(MiniXMLParser*)body firstValueAtPath:@"Error:Code"];
		}
		else
		string = nil;
		if(string)
		*error = MAKE_HTTP_ERROR(status, @"Amazon S3 Error: %@", string);
		else
		*error = MAKE_HTTP_ERROR(status, kDefaultHTTPError);
	}
	
	[body release];
	
	return result;
}

- (NSDictionary*) bucketKeysForPath:(NSString*)remotePath withPrefix:(NSString*)prefix marker:(NSString*)marker delimiter:(NSString*)delimiter maxKeys:(NSUInteger)max isTruncated:(BOOL*)truncated
{
	CFHTTPMessageRef		request;
	CFReadStreamRef			stream;
	NSMutableString*		query;
	NSDictionary*			result;
	NSDictionary*			info;
	
	if([prefix length] || [marker length] || [delimiter length] || max) {
		query = [NSMutableString string];
		if([prefix length])
		[query appendFormat:@"prefix=%@", prefix];
		if([marker length]) {
			if([query length])
			[query appendString:@"&"];
			[query appendFormat:@"marker=%@", marker];
		}
		if([delimiter length]) {
			if([query length])
			[query appendString:@"&"];
			[query appendFormat:@"delimiter=%@", delimiter];
		}
		if(max) {
			if([query length])
			[query appendString:@"&"];
			[query appendFormat:@"max-keys=%lu", max];
		}
		remotePath = (remotePath ? [remotePath stringByAppendingFormat:@"?%@", query] : [NSString stringWithFormat:@"?%@", query]);
	}
	
	request = [self _newHTTPRequestWithMethod:@"GET" path:remotePath];
	if(request == NULL)
	return nil;
	
	stream = [self _newReadStreamWithHTTPRequest:request bodyStream:nil];
	CFRelease(request);
	
	result = [self runReadStream:stream dataStream:[NSOutputStream outputStreamToMemory] userInfo:@"GET/" isFileTransfer:NO];
	if(result == nil)
	return nil;
	
	if((info = [result objectForKey:[NSNull null]])) {
		if(truncated)
		*truncated = ([info objectForKey:@"IsTruncated"] && ([[info objectForKey:@"IsTruncated"] caseInsensitiveCompare:@"true"] == NSOrderedSame));
		result = [NSMutableDictionary dictionaryWithDictionary:result];
		[(NSMutableDictionary*)result removeObjectForKey:[NSNull null]];
	}
	else if(truncated)
	*truncated = NO;
	
	return result;
}

- (NSDictionary*) contentsOfDirectoryAtPath:(NSString*)remotePath
{
	NSMutableDictionary*	allResults = [NSMutableDictionary dictionary];
	NSString*				marker = nil;
	NSAutoreleasePool*		localPool;
	BOOL					isTruncated;
	NSDictionary*			result;
	
	do {
		localPool = [NSAutoreleasePool new];
		result = [self bucketKeysForPath:remotePath withPrefix:nil marker:marker delimiter:nil maxKeys:0 isTruncated:&isTruncated];
		if(isTruncated)
		marker = [[[[result allKeys] sortedArrayUsingSelector:@selector(compare:)] lastObject] retain];
		else
		marker = nil;
		[allResults addEntriesFromDictionary:result];
		[localPool drain];
		[marker autorelease];
		if(result == nil)
		return nil;
	} while(marker);
	
	return allResults;
}

- (BOOL) _deletePath:(NSString*)remotePath
{
	CFHTTPMessageRef		request;
	CFReadStreamRef			stream;
	
	request = [self _newHTTPRequestWithMethod:@"DELETE" path:remotePath];
	if(request == NULL)
	return NO;
	
	stream = [self _newReadStreamWithHTTPRequest:request bodyStream:nil];
	CFRelease(request);
	
	return [[self runReadStream:stream dataStream:[NSOutputStream outputStreamToMemory] userInfo:@"DELETE" isFileTransfer:NO] boolValue];
}

- (BOOL) deleteFileAtPath:(NSString*)remotePath
{
	return [self _deletePath:remotePath];
}

- (BOOL) copyPath:(NSString*)fromRemotePath toPath:(NSString*)toRemotePath
{
	NSString*				host = [[self baseURL] host];
	CFHTTPMessageRef		request;
	CFReadStreamRef			stream;
	
	if(![fromRemotePath length])
	return NO;
	if([fromRemotePath characterAtIndex:0] != '/') {
		if([host isEqualToString:kFileTransferHost_AmazonS3])
		return NO;
		fromRemotePath = [NSString stringWithFormat:@"%@/%@", [host substringToIndex:([host length] - [kFileTransferHost_AmazonS3 length] - 1)], fromRemotePath];
	}
	
	request = [self _newHTTPRequestWithMethod:@"PUT" path:toRemotePath];
	if(request == NULL)
	return NO;
	
	fromRemotePath = [NSMakeCollectable(CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, (CFStringRef)fromRemotePath, NULL, NULL, kCFStringEncodingUTF8)) autorelease];
	CFHTTPMessageSetHeaderFieldValue(request, CFSTR("x-amz-copy-source"), (CFStringRef)fromRemotePath);
	
	stream = [self _newReadStreamWithHTTPRequest:request bodyStream:nil];
	CFRelease(request);
	
	return [[self runReadStream:stream dataStream:[NSOutputStream outputStreamToMemory] userInfo:@"COPY" isFileTransfer:NO] boolValue];
}

- (BOOL) createDirectoryAtPath:(NSString*)remotePath
{
	CFHTTPMessageRef		request;
	CFReadStreamRef			stream;
	NSString*				xmlString;
	NSData*					xmlData;
	
	request = [self _newHTTPRequestWithMethod:@"PUT" path:remotePath];
	if(request == NULL)
	return NO;
	
	if([_newBucketLocation length]) {
		xmlString = [NSString stringWithFormat:@"<CreateBucketConfiguration><LocationConstraint>%@</LocationConstraint></CreateBucketConfiguration>", _newBucketLocation];
		xmlData = [xmlString dataUsingEncoding:NSUTF8StringEncoding];
		CFHTTPMessageSetHeaderFieldValue(request, CFSTR("Content-Length"), (CFStringRef)[NSString stringWithFormat:@"%i", [xmlData length]]);
		CFHTTPMessageSetBody(request, (CFDataRef)xmlData);
	}
	
	stream = [self _newReadStreamWithHTTPRequest:request bodyStream:nil];
	CFRelease(request);
	
	return [[self runReadStream:stream dataStream:[NSOutputStream outputStreamToMemory] userInfo:@"PUT" isFileTransfer:NO] boolValue];
}

- (BOOL) deleteDirectoryAtPath:(NSString*)remotePath
{
	return [self _deletePath:remotePath];
}

- (NSString*) locationForPath:(NSString*)remotePath
{
	NSString*				host = [[self baseURL] host];
	NSRange					range;
	CFHTTPMessageRef		request;
	CFReadStreamRef			stream;
	
	if([host length] > [kFileTransferHost_AmazonS3 length])
	remotePath = @"?location";
	else {
		if([remotePath hasPrefix:@"/"])
		remotePath = [remotePath substringFromIndex:1];
		range = [remotePath rangeOfString:@"/"];
		if(range.location != NSNotFound)
		remotePath = [remotePath substringToIndex:range.location];
		remotePath = [remotePath stringByAppendingString:@"?location"];
	}
	
	request = [self _newHTTPRequestWithMethod:@"GET" path:remotePath];
	if(request == NULL)
	return nil;
	
	stream = [self _newReadStreamWithHTTPRequest:request bodyStream:nil];
	CFRelease(request);
	
	return [self runReadStream:stream dataStream:[NSOutputStream outputStreamToMemory] userInfo:@"GET?" isFileTransfer:NO];
}

@end

@implementation SecureAmazonS3TransferController

+ (NSString*) urlScheme;
{
	return @"https";
}

@end

/* Source below was copied from http://cocoawithlove.com/2009/06/base64-encoding-options-on-mac-and.html */

//
//  NSData+Base64.h
//  base64
//
//  Created by Matt Gallagher on 2009/06/03.
//  Copyright 2009 Matt Gallagher. All rights reserved.
//
//  Permission is given to use this source code file, free of charge, in any
//  project, commercial or otherwise, entirely at your risk, with the condition
//  that any redistribution (in part or whole) of source code must retain
//  this copyright and permission notice. Attribution in compiled projects is
//  appreciated but not required.
//

static unsigned char base64EncodeLookup[65] =
	"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

//
// Fundamental sizes of the binary and base64 encode/decode units in bytes
//
#define BINARY_UNIT_SIZE 3
#define BASE64_UNIT_SIZE 4

//
// NewBase64Decode
//
// Encodes the arbitrary data in the inputBuffer as base64 into a newly malloced
// output buffer.
//
//  inputBuffer - the source data for the encode
//	length - the length of the input in bytes
//  separateLines - if zero, no CR/LF characters will be added. Otherwise
//		a CR/LF pair will be added every 64 encoded chars.
//	outputLength - if not-NULL, on output will contain the encoded length
//		(not including terminating 0 char)
//
// returns the encoded buffer. Must be free'd by caller. Length is given by
//	outputLength.
//
static char *NewBase64Encode(
	const void *buffer,
	size_t length,
	bool separateLines,
	size_t *outputLength)
{
	const unsigned char *inputBuffer = (const unsigned char *)buffer;
	
	#define MAX_NUM_PADDING_CHARS 2
	#define OUTPUT_LINE_LENGTH 64
	#define INPUT_LINE_LENGTH ((OUTPUT_LINE_LENGTH / BASE64_UNIT_SIZE) * BINARY_UNIT_SIZE)
	#define CR_LF_SIZE 2
	
	//
	// Byte accurate calculation of final buffer size
	//
	size_t outputBufferSize =
			((length / BINARY_UNIT_SIZE)
				+ ((length % BINARY_UNIT_SIZE) ? 1 : 0))
					* BASE64_UNIT_SIZE;
	if (separateLines)
	{
		outputBufferSize +=
			(outputBufferSize / OUTPUT_LINE_LENGTH) * CR_LF_SIZE;
	}
	
	//
	// Include space for a terminating zero
	//
	outputBufferSize += 1;

	//
	// Allocate the output buffer
	//
	char *outputBuffer = (char *)malloc(outputBufferSize);
	if (!outputBuffer)
	{
		return NULL;
	}

	size_t i = 0;
	size_t j = 0;
	const size_t lineLength = separateLines ? INPUT_LINE_LENGTH : length;
	size_t lineEnd = lineLength;
	
	while (true)
	{
		if (lineEnd > length)
		{
			lineEnd = length;
		}

		for (; i + BINARY_UNIT_SIZE - 1 < lineEnd; i += BINARY_UNIT_SIZE)
		{
			//
			// Inner loop: turn 48 bytes into 64 base64 characters
			//
			outputBuffer[j++] = base64EncodeLookup[(inputBuffer[i] & 0xFC) >> 2];
			outputBuffer[j++] = base64EncodeLookup[((inputBuffer[i] & 0x03) << 4)
				| ((inputBuffer[i + 1] & 0xF0) >> 4)];
			outputBuffer[j++] = base64EncodeLookup[((inputBuffer[i + 1] & 0x0F) << 2)
				| ((inputBuffer[i + 2] & 0xC0) >> 6)];
			outputBuffer[j++] = base64EncodeLookup[inputBuffer[i + 2] & 0x3F];
		}
		
		if (lineEnd == length)
		{
			break;
		}
		
		//
		// Add the newline
		//
		outputBuffer[j++] = '\r';
		outputBuffer[j++] = '\n';
		lineEnd += lineLength;
	}
	
	if (i + 1 < length)
	{
		//
		// Handle the single '=' case
		//
		outputBuffer[j++] = base64EncodeLookup[(inputBuffer[i] & 0xFC) >> 2];
		outputBuffer[j++] = base64EncodeLookup[((inputBuffer[i] & 0x03) << 4)
			| ((inputBuffer[i + 1] & 0xF0) >> 4)];
		outputBuffer[j++] = base64EncodeLookup[(inputBuffer[i + 1] & 0x0F) << 2];
		outputBuffer[j++] =	'=';
	}
	else if (i < length)
	{
		//
		// Handle the double '=' case
		//
		outputBuffer[j++] = base64EncodeLookup[(inputBuffer[i] & 0xFC) >> 2];
		outputBuffer[j++] = base64EncodeLookup[(inputBuffer[i] & 0x03) << 4];
		outputBuffer[j++] = '=';
		outputBuffer[j++] = '=';
	}
	outputBuffer[j] = 0;
	
	//
	// Set the output length and return the buffer
	//
	if (outputLength)
	{
		*outputLength = j;
	}
	return outputBuffer;
}
