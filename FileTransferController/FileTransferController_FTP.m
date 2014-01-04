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

#import <SystemConfiguration/SystemConfiguration.h>
#import <curl/curl.h>

#import "FileTransferController_Internal.h"
#import "NSURL+Parameters.h"

#define __USE_COMMAND_PROGRESS__ 0
#define __USE_LISTING_PROGRESS__ 0

@interface FTPTransferController ()
@property(nonatomic, readonly) void* handle;
- (void) _reset;
@end

static inline NSError* _MakeCURLError(CURLcode code, const char* message, id transcript)
{
	return [NSError errorWithDomain:@"curl" code:code userInfo:[NSDictionary dictionaryWithObjectsAndKeys:[NSString stringWithUTF8String:message], NSLocalizedDescriptionKey, transcript, @"Last Server Message", nil]];
}

@implementation FTPTransferController

@synthesize handle=_handle, stringEncoding=_stringEncoding, keepConnectionAlive=_keepAlive;

+ (void) initialize
{
	if(self == [FTPTransferController class])
	curl_global_init(CURL_GLOBAL_DEFAULT);
}

+ (NSString*) urlScheme;
{
	return @"ftp";
}

- (id) initWithBaseURL:(NSURL*)url
{
	if((self = [super initWithBaseURL:url])) {
		_handle = curl_easy_init();
		if(_handle == NULL) {
			NSLog(@"%s: curl_easy_init() failed", __FUNCTION__);
			[self release];
			return nil;
		}
		_stringEncoding = NSISOLatin1StringEncoding;
	}
	
	return self;
}

- (void) _cleanUp_FTPTransferController
{
	if(_handle)
	curl_easy_cleanup(_handle);
}

- (void) finalize
{
	[self _cleanUp_FTPTransferController];
	
	[super finalize];
}

- (void) dealloc
{
	[self _cleanUp_FTPTransferController];
	
	[_transcript release];
	
	[super dealloc];
}

static int _DebugCallback(CURL* handle, curl_infotype type, char* data, size_t size, void* userptr)
{
	FTPTransferController*	self = (FTPTransferController*)userptr;
	NSString*				string;
	
#ifdef __DEBUG__
	if((type == CURLINFO_HEADER_IN) || (type == CURLINFO_TEXT) || (type == CURLINFO_HEADER_OUT))
#else
	if(type == CURLINFO_HEADER_IN)
#endif
	{
		if(data[size - 1] == '\n')
		--size;
		if(data[size - 1] == '\r')
		--size;
		string = [[NSString alloc] initWithBytes:data length:size encoding:self->_stringEncoding];
#ifdef __DEBUG__
		if(self->_transcript == nil)
		self->_transcript = [NSMutableArray new];
		[self->_transcript addObject:string];
		[string release];
#else
		[self->_transcript release];
		self->_transcript = string;
#endif
	}
	
	return 0;
}

- (void) _reset
{
	NSTimeInterval			timeOut = [self timeOut];
	CFDictionaryRef			proxySettings;
	const char*				host;
	long					port;
	//NSArray*				array;
	
	[_transcript release];
	_transcript = nil;
	curl_easy_reset(_handle);
	
	curl_easy_setopt(_handle, CURLOPT_FORBID_REUSE, (long)(_keepAlive ? 0 : 1));
	curl_easy_setopt(_handle, CURLOPT_IPRESOLVE, (long)CURL_IPRESOLVE_V4); //HACK: Work around an issue with Bonjour hostnames that resolve to IPv6 and passive connections can't be established
	if(timeOut > 0.0)
	curl_easy_setopt(_handle, CURLOPT_FTP_RESPONSE_TIMEOUT, (long)ceil(timeOut));
	
	curl_easy_setopt(_handle, CURLOPT_VERBOSE, (long)1);
	curl_easy_setopt(_handle, CURLOPT_DEBUGFUNCTION, _DebugCallback);
	curl_easy_setopt(_handle, CURLOPT_DEBUGDATA, self);
	
	if((proxySettings = SCDynamicStoreCopyProxies(NULL))) {
		if([[(NSDictionary*)proxySettings objectForKey:(id)kSCPropNetProxiesFTPEnable] boolValue]) {
			if((host = [[(NSDictionary*)proxySettings objectForKey:(id)kSCPropNetProxiesFTPProxy] UTF8String]))
			curl_easy_setopt(_handle, CURLOPT_PROXY, host);
			if((port = [[(NSDictionary*)proxySettings objectForKey:(id)kSCPropNetProxiesFTPPort] longValue]))
			curl_easy_setopt(_handle, CURLOPT_PROXYPORT, port);
			/*
			if((array = [(NSDictionary*)proxySettings objectForKey:(id)kSCPropNetProxiesExceptionsList])) 
			curl_easy_setopt(_handle, CURLOPT_NOPROXY, [[array componentsJoinedByString:@","] UTF8String]);
			*/
		}
		CFRelease(proxySettings);
	}
}

- (const char*) _convertURL:(NSURL*)url
{
	return [[url absoluteString] cStringUsingEncoding:_stringEncoding];
}

static int _WriteProgressCallback(void* clientp, double dltotal, double dlnow, double ultotal, double ulnow)
{
	void**					params = (void*)clientp;
	FTPTransferController*	self = (FTPTransferController*)params[0];
	
	if(![self maxLength])
	[self setMaxLength:dltotal];
	
	[self setCurrentLength:dlnow];
	
	return (params[2] ? [[self delegate] fileTransferControllerShouldAbort:self] : 0);
}

static size_t _WriteCallback(void* buffer, size_t size, size_t nmemb, void* userp)
{
	void**					params = (void*)userp;
	FTPTransferController*	self = (FTPTransferController*)params[0];
	NSOutputStream*			stream = (NSOutputStream*)params[1];
	
	return ([self writeToOutputStream:stream bytes:buffer maxLength:(size * nmemb)] ? size * nmemb : -1);
}

- (BOOL) _downloadFileFromPath:(NSString*)remotePath toStream:(NSOutputStream*)stream
{
	NSURL*					url = [self fullAbsoluteURLForRemotePath:remotePath];
	BOOL					success = NO;
	void*					params[3];
	CURLcode				result;
	char					buffer[CURL_ERROR_SIZE];
	NSError*				error;
	
	if(!stream || ([stream streamStatus] != NSStreamStatusNotOpen))
	return NO;
	
	params[0] = self;
	params[1] = stream;
	params[2] = ([[self delegate] respondsToSelector:@selector(fileTransferControllerShouldAbort:)] ? self : NULL);
	
	[self _reset];
	curl_easy_setopt(_handle, CURLOPT_URL, [self _convertURL:url]);
	curl_easy_setopt(_handle, CURLOPT_ERRORBUFFER, buffer);
	curl_easy_setopt(_handle, CURLOPT_WRITEFUNCTION, _WriteCallback);
	curl_easy_setopt(_handle, CURLOPT_WRITEDATA, params);
	curl_easy_setopt(_handle, CURLOPT_NOPROGRESS, (long)0);
	curl_easy_setopt(_handle, CURLOPT_PROGRESSFUNCTION, _WriteProgressCallback);
	curl_easy_setopt(_handle, CURLOPT_PROGRESSDATA, params);
	
	if([self openOutputStream:stream isFileTransfer:YES]) {
		if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidStart:)])
		[[self delegate] fileTransferControllerDidStart:self];
		
		result = curl_easy_perform(_handle);
		if(result == CURLE_OK) {
			if([self flushOutputStream:stream]) {
				if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidSucceed:)])
				[[self delegate] fileTransferControllerDidSucceed:self];
				success = YES;
			}
			else {
				error = [stream streamError];
				[[self delegate] fileTransferControllerDidFail:self withError:([error code] ? error : MAKE_FILETRANSFERCONTROLLER_ERROR(@"Failed flushing output stream (status = %i)", [stream streamStatus]))];
			}
		}
		else {
			if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
			[[self delegate] fileTransferControllerDidFail:self withError:_MakeCURLError(result, buffer, _transcript)];
		}
		
		[self closeOutputStream:stream];
	}
	
	return success;
}

static int _ReadProgressCallback(void* clientp, double dltotal, double dlnow, double ultotal, double ulnow)
{
	void**					params = (void*)clientp;
	FTPTransferController*	self = (FTPTransferController*)params[0];
	
	[self setCurrentLength:ulnow];
	
	return (params[2] ? [[self delegate] fileTransferControllerShouldAbort:self] : 0);
}

static size_t _ReadCallback(char* bufptr, size_t size, size_t nitems, void* userp)
{
	void**					params = (void*)userp;
	FTPTransferController*	self = (FTPTransferController*)params[0];
	NSInputStream*			stream = (NSInputStream*)params[1];
	
	return [self readFromInputStream:stream bytes:bufptr maxLength:(size * nitems)];
}

- (BOOL) _uploadFileToPath:(NSString*)remotePath fromStream:(NSInputStream*)stream
{
	NSURL*					url = [self fullAbsoluteURLForRemotePath:remotePath];
	BOOL					success = NO;
	void*					params[3];
	CURLcode				result;
	char					buffer[CURL_ERROR_SIZE];
	
	if(!stream || ([stream streamStatus] != NSStreamStatusNotOpen))
	return NO;
	
	params[0] = self;
	params[1] = stream;
	params[2] = ([[self delegate] respondsToSelector:@selector(fileTransferControllerShouldAbort:)] ? self : NULL);
	
	[self _reset];
	curl_easy_setopt(_handle, CURLOPT_URL, [self _convertURL:url]);
	curl_easy_setopt(_handle, CURLOPT_ERRORBUFFER, buffer);
	curl_easy_setopt(_handle, CURLOPT_READFUNCTION, _ReadCallback);
	curl_easy_setopt(_handle, CURLOPT_READDATA, params);
	curl_easy_setopt(_handle, CURLOPT_NOPROGRESS, (long)0);
	curl_easy_setopt(_handle, CURLOPT_PROGRESSFUNCTION, _ReadProgressCallback);
	curl_easy_setopt(_handle, CURLOPT_PROGRESSDATA, params);
	curl_easy_setopt(_handle, CURLOPT_UPLOAD, (long)1);
	curl_easy_setopt(_handle, CURLOPT_INFILESIZE, (long)[self maxLength]);
	
	if([self openInputStream:stream isFileTransfer:YES]) {
		if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidStart:)])
		[[self delegate] fileTransferControllerDidStart:self];
		
		result = curl_easy_perform(_handle);
		if(result == CURLE_OK) {
			if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidSucceed:)])
			[[self delegate] fileTransferControllerDidSucceed:self];
			success = YES;
		}
		else {
			if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
			[[self delegate] fileTransferControllerDidFail:self withError:_MakeCURLError(result, buffer, _transcript)];
		}
		
		[self closeInputStream:stream];
	}
	
	return success;
}

- (NSDictionary*) _ParseFTPDirectoryListing:(NSData*)data
{
	NSMutableDictionary*	result = [NSMutableDictionary dictionary];
	NSUInteger				offset = 0;
	NSMutableDictionary*	dictionary;
	CFDictionaryRef			entry;
	CFIndex					length;
	NSInteger				type;
	NSString*				string;
	
	//HACK: CFFTPCreateParsedResourceListing() creates strings with the kCFStringEncodingMacRoman encoding
	if(_stringEncoding != NSMacOSRomanStringEncoding) {
		string = [[NSString alloc] initWithData:data encoding:_stringEncoding];
		data = [string dataUsingEncoding:NSMacOSRomanStringEncoding];
		[string release];
		if(data == nil)
		return nil;
	}
	
	while(1) {
		length = CFFTPCreateParsedResourceListing(kCFAllocatorDefault, (unsigned char*)[data bytes] + offset, [data length] - offset, &entry);
		if((length <= 0) || (entry == NULL))
		break;
		
		if(![(NSString*)CFDictionaryGetValue(entry, kCFFTPResourceName) isEqualToString:@"."] && ![(NSString*)CFDictionaryGetValue(entry, kCFFTPResourceName) isEqualToString:@".."]) {
			type = [(NSNumber*)CFDictionaryGetValue(entry, kCFFTPResourceType) integerValue];
			
			dictionary = [NSMutableDictionary new];
			if(type == 8) {
				[dictionary setObject:NSFileTypeRegular forKey:NSFileType];
				[dictionary setObject:(id)CFDictionaryGetValue(entry, kCFFTPResourceSize) forKey:NSFileSize];
			}
			else if(type == 4)
			[dictionary setObject:NSFileTypeDirectory forKey:NSFileType];
			[dictionary setObject:(id)CFDictionaryGetValue(entry, kCFFTPResourceModDate) forKey:NSFileModificationDate];
			[result setObject:dictionary forKey:(id)CFDictionaryGetValue(entry, kCFFTPResourceName)];
			[dictionary release];
		}
		
		CFRelease(entry);
		offset += length;
	}
	
	return result;
}

#if __USE_LISTING_PROGRESS__
static int _ListingProgressCallback(void* clientp, double dltotal, double dlnow, double ultotal, double ulnow)
{
	void**					params = (void*)clientp;
	FTPTransferController*	self = (FTPTransferController*)params[1];
	
	return (params[2] ? [[self delegate] fileTransferControllerShouldAbort:self] : 0);
}
#endif

static size_t _ListingCallback(void* buffer, size_t size, size_t nmemb, void* userp)
{
	void**					params = (void*)userp;
	NSMutableData*			data = (NSMutableData*)params[0];
	
	[data appendBytes:buffer length:(size * nmemb)];
	
	return (size * nmemb);
}

- (NSDictionary*) contentsOfDirectoryAtPath:(NSString*)remotePath
{
	NSMutableData*			data = [NSMutableData data];
	NSDictionary*			dictionary = nil;
	NSURL*					url;
	CURLcode				result;
	char					buffer[CURL_ERROR_SIZE];
#if __USE_LISTING_PROGRESS__
	void*					params[3];
#else
	void*					params[1];
#endif
	
	if(remotePath) {
		if(![remotePath hasSuffix:@"/"])
		remotePath = [remotePath stringByAppendingString:@"/"];
	}
	else
	remotePath = @"/";
	url = [self fullAbsoluteURLForRemotePath:remotePath];
	
	params[0] = data;
#if __USE_LISTING_PROGRESS__
	params[1] = self;
	params[2] = ([[self delegate] respondsToSelector:@selector(fileTransferControllerShouldAbort:)] ? self : NULL);
#endif
	
	[self _reset];
	curl_easy_setopt(_handle, CURLOPT_URL, [self _convertURL:url]);
	curl_easy_setopt(_handle, CURLOPT_ERRORBUFFER, buffer);
	curl_easy_setopt(_handle, CURLOPT_WRITEFUNCTION, _ListingCallback);
	curl_easy_setopt(_handle, CURLOPT_WRITEDATA, params);
#if __USE_LISTING_PROGRESS__
	curl_easy_setopt(_handle, CURLOPT_NOPROGRESS, (long)0);
	curl_easy_setopt(_handle, CURLOPT_PROGRESSFUNCTION, _ListingProgressCallback);
	curl_easy_setopt(_handle, CURLOPT_PROGRESSDATA, params);
#else
	curl_easy_setopt(_handle, CURLOPT_NOPROGRESS, (long)1);
#endif
	
	if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidStart:)])
	[[self delegate] fileTransferControllerDidStart:self];
	
	result = curl_easy_perform(_handle);
	if(result == CURLE_OK) {
		dictionary = [self _ParseFTPDirectoryListing:data];
		if(dictionary) {
			if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidSucceed:)])
			[[self delegate] fileTransferControllerDidSucceed:self];
		}
		else {
			if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
			[[self delegate] fileTransferControllerDidFail:self withError:MAKE_FILETRANSFERCONTROLLER_ERROR(@"Failed parsing FTP listing (invalid character encoding)")];
		}
	}
	else {
		if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
		[[self delegate] fileTransferControllerDidFail:self withError:_MakeCURLError(result, buffer, _transcript)];
	}
	
	return dictionary;
}

#if __USE_COMMAND_PROGRESS__
static int _CommandProgressCallback(void* clientp, double dltotal, double dlnow, double ultotal, double ulnow)
{
	void**					params = (void*)clientp;
	FTPTransferController*	self = (FTPTransferController*)params[0];
	
	return (params[1] ? [[self delegate] fileTransferControllerShouldAbort:self] : 0);
}
#endif

/* This method takes ownership of the header list */
- (BOOL) _performQuote:(struct curl_slist*)headerList url:(NSURL*)url
{
	BOOL					success = NO;
	CURLcode				result;
	char					buffer[CURL_ERROR_SIZE];
	FILE*					file;
#if __USE_COMMAND_PROGRESS__
	void*					params[2];
#endif
	
#if __USE_COMMAND_PROGRESS__
	params[0] = self;
	params[1] = ([[self delegate] respondsToSelector:@selector(fileTransferControllerShouldAbort:)] ? self : NULL);
#endif
	file = fopen("/dev/null", "a");
	
	[self _reset];
	curl_easy_setopt(_handle, CURLOPT_URL, [self _convertURL:url]);
	curl_easy_setopt(_handle, CURLOPT_ERRORBUFFER, buffer);
	curl_easy_setopt(_handle, CURLOPT_WRITEDATA, file);
#if __USE_COMMAND_PROGRESS__
	curl_easy_setopt(_handle, CURLOPT_NOPROGRESS, (long)0);
	curl_easy_setopt(_handle, CURLOPT_PROGRESSFUNCTION, _CommandProgressCallback);
	curl_easy_setopt(_handle, CURLOPT_PROGRESSDATA, params);
#else
	curl_easy_setopt(_handle, CURLOPT_NOPROGRESS, (long)1);
#endif
	if(headerList)
	curl_easy_setopt(_handle, CURLOPT_POSTQUOTE, headerList);
	else
	curl_easy_setopt(_handle, CURLOPT_FTP_CREATE_MISSING_DIRS, (long)1);
	
	if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidStart:)])
	[[self delegate] fileTransferControllerDidStart:self];
	
	result = curl_easy_perform(_handle);
	if(result == CURLE_OK) {
		if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidSucceed:)])
		[[self delegate] fileTransferControllerDidSucceed:self];
		success = YES;
	}
	else {
		if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
		[[self delegate] fileTransferControllerDidFail:self withError:_MakeCURLError(result, buffer, _transcript)];
	}
	
	if(headerList)
	curl_slist_free_all(headerList);
	fclose(file);
	
	return success;
}

- (BOOL) movePath:(NSString*)fromRemotePath toPath:(NSString*)toRemotePath
{
	struct curl_slist*		headerList = NULL;
	
	if([fromRemotePath hasPrefix:@"/"])
	fromRemotePath = [fromRemotePath substringFromIndex:1];
	headerList = curl_slist_append(headerList, [[NSString stringWithFormat:@"RNFR %@", fromRemotePath] cStringUsingEncoding:_stringEncoding]);
	
	if([toRemotePath hasPrefix:@"/"])
	toRemotePath = [toRemotePath substringFromIndex:1];
	headerList = curl_slist_append(headerList, [[NSString stringWithFormat:@"RNTO %@", toRemotePath] cStringUsingEncoding:_stringEncoding]);
	
	return [self _performQuote:headerList url:[self fullAbsoluteURLForRemotePath:@"/"]];
}

- (BOOL) createDirectoryAtPath:(NSString*)remotePath
{
#if 1 //FIXME: Work around CURL bug that closes the connection when doing CURLOPT_POSTQUOTE inside an empty directory 
	if(![remotePath hasSuffix:@"/"])
	remotePath = [remotePath stringByAppendingString:@"/"];
	
	return [self _performQuote:NULL url:[self fullAbsoluteURLForRemotePath:remotePath]];
#else	
	struct curl_slist*		headerList = NULL;
	
	if([remotePath hasPrefix:@"/"])
	remotePath = [remotePath substringFromIndex:1];
	headerList = curl_slist_append(headerList, [[NSString stringWithFormat:@"MKD %@", remotePath] cStringUsingEncoding:_stringEncoding]);
	
	return [self _performQuote:headerList withURL:[self fullAbsoluteURLForRemotePath:@"/"]];
#endif
}

- (BOOL) deleteFileAtPath:(NSString*)remotePath
{
	struct curl_slist*		headerList = NULL;
	
	if([remotePath hasPrefix:@"/"])
	remotePath = [remotePath substringFromIndex:1];
	headerList = curl_slist_append(headerList, [[NSString stringWithFormat:@"DELE %@", remotePath] cStringUsingEncoding:_stringEncoding]);
	
	return [self _performQuote:headerList url:[self fullAbsoluteURLForRemotePath:@"/"]];
}

- (BOOL) deleteDirectoryAtPath:(NSString*)remotePath
{
	struct curl_slist*		headerList = NULL;
	
	if([remotePath hasPrefix:@"/"])
	remotePath = [remotePath substringFromIndex:1];
	headerList = curl_slist_append(headerList, [[NSString stringWithFormat:@"RMD %@", remotePath] cStringUsingEncoding:_stringEncoding]);
	
	return [self _performQuote:headerList url:[self fullAbsoluteURLForRemotePath:@"/"]];
}

@end

@implementation FTPSTransferController

+ (NSString*) urlScheme;
{
	return @"ftps";
}

/* Override */
- (void) _reset
{
	[super _reset];
	
	curl_easy_setopt([self handle], CURLOPT_FTP_SSL, CURLFTPSSL_ALL);
	curl_easy_setopt([self handle], CURLOPT_SSL_VERIFYPEER, (long)0);
	curl_easy_setopt([self handle], CURLOPT_SSL_VERIFYHOST, (long)0);
}

/* Override completely */
- (const char*) _convertURL:(NSURL*)url
{
	//We do implicit SSL if the port is explicitely set to 990, otherwise we do explicit SSL
	if([[url port] integerValue] == 990)
	return [[[url absoluteString] stringByReplacingOccurrencesOfString:@":990" withString:@""] cStringUsingEncoding:[self stringEncoding]]; //HACK: Return an "ftps://" URL
	
	return [[[url absoluteString] stringByReplacingOccurrencesOfString:@"ftps://" withString:@"ftp://"] cStringUsingEncoding:[self stringEncoding]]; //HACK: Return an "ftp://" URL
}

@end
