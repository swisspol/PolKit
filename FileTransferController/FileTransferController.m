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

#import <TargetConditionals.h>
#if TARGET_OS_IPHONE
#import <unistd.h>
#else
#import <openssl/evp.h>
#endif
#import <libkern/OSAtomic.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <arpa/inet.h>

#import "FileTransferController_Internal.h"
#import "NSURL+Parameters.h"
#import "DataStream.h"

#define kFileTransferRunLoopActiveMode	CFSTR("FileTransferActiveMode")
#define kStreamBufferSize				(256 * 1024)
#define kRunLoopInterval				1.0
#if !TARGET_OS_IPHONE
#define kEncryptionCipher				EVP_aes_256_cbc()
#define kEncryptionCipherBlockSize		16
#define kDigestType						EVP_md5()
#endif

typedef struct {
	unsigned char*						buffer;
	NSUInteger							size;
} DataInfo;

static NSUInteger						_maximumDownloadSpeed = 0,
										_maximumUploadSpeed = 0;
static OSSpinLock						_downloadLock = 0,
										_uploadLock = 0;
static CFTimeInterval					_downloadTime = 0.0,
										_uploadTime = 0.0;

#define MAKE_IPV4(A, B, C, D) ((((UInt32)A) << 24) | (((UInt32)B) << 16) | (((UInt32)C) << 8) | ((UInt32)D))

#define IS_REACHABLE(__FLAGS__) (((__FLAGS__) & kSCNetworkFlagsReachable) && !((__FLAGS__) & kSCNetworkFlagsConnectionRequired))

@implementation FileTransferController

@synthesize baseURL=_baseURL, delegate=_delegate, localHost=_localHost, maxLength=_maxLength, currentLength=_currentLength, timeOut=_timeOut, maximumDownloadSpeed=_maxDownloadSpeed, maximumUploadSpeed=_maxUploadSpeed;
#if !TARGET_OS_IPHONE
@synthesize digestComputation=_digestComputation, encryptionPassword=_encryptionPassword;
#endif

+ (id) allocWithZone:(NSZone*)zone
{
	if(self == [FileTransferController class])
	[[NSException exceptionWithName:NSInternalInconsistencyException reason:@"FileTransferController is an abstract class" userInfo:nil] raise];
	
	return [super allocWithZone:zone];
}

+ (NSString*) urlScheme;
{
	return nil;
}

+ (BOOL) useAsyncStreams
{
	return YES;
}

+ (BOOL) hasAtomicUploads
{
	return NO;
}

+ (NSUInteger) globalMaximumDownloadSpeed
{
	return _maximumDownloadSpeed;
}

+ (void) setGlobalMaximumDownloadSpeed:(NSUInteger)speed
{
	_maximumDownloadSpeed = speed;
}

+ (NSUInteger) globalMaximumUploadSpeed
{
	return _maximumUploadSpeed;
}

+ (void) setGlobalMaximumUploadSpeed:(NSUInteger)speed
{
	_maximumUploadSpeed = speed;
}

+ (FileTransferController*) fileTransferControllerWithURL:(NSURL*)url
{
	NSString*					user = [url user];
	NSString*					password = [url passwordByReplacingPercentEscapes];
	
	if([[url scheme] isEqualToString:@"file"])
	return [[(LocalTransferController*)[NSClassFromString(@"LocalTransferController") alloc] initWithBaseURL:url] autorelease];
	
#if !TARGET_OS_IPHONE
	if([[url scheme] isEqualToString:@"afp"])
	return [[(AFPTransferController*)[NSClassFromString(@"AFPTransferController") alloc] initWithBaseURL:url] autorelease];
	
	if([[url scheme] isEqualToString:@"smb"])
	return [[(SMBTransferController*)[NSClassFromString(@"SMBTransferController") alloc] initWithBaseURL:url] autorelease];
#endif
	
	if([[url scheme] isEqualToString:@"http"]) {
		if([[url host] isEqualToString:kFileTransferHost_iDisk]) {
			if(user && password)
			return [[(WebDAVTransferController*)[NSClassFromString(@"WebDAVTransferController") alloc] initWithIDiskForUser:user password:password basePath:[url path]] autorelease];
			else if(user)
			return [[(WebDAVTransferController*)[NSClassFromString(@"WebDAVTransferController") alloc] initWithIDiskForUser:user basePath:[url path]] autorelease];
			else
			return [[(WebDAVTransferController*)[NSClassFromString(@"WebDAVTransferController") alloc] initWithIDiskForLocalUser:[url path]] autorelease];
		}
		else {
			if([[url host] hasSuffix:kFileTransferHost_AmazonS3])
			return [[(AmazonS3TransferController*)[NSClassFromString(@"AmazonS3TransferController") alloc] initWithBaseURL:url] autorelease];
			else
			return [[(WebDAVTransferController*)[NSClassFromString(@"WebDAVTransferController") alloc] initWithBaseURL:url] autorelease];
		}
	}
	
	if([[url scheme] isEqualToString:@"https"]) {
		if([[url host] hasSuffix:kFileTransferHost_AmazonS3])
		return [[(SecureAmazonS3TransferController*)[NSClassFromString(@"SecureAmazonS3TransferController") alloc] initWithBaseURL:url] autorelease];
		else
		return [[(SecureWebDAVTransferController*)[NSClassFromString(@"SecureWebDAVTransferController") alloc] initWithBaseURL:url] autorelease];
	}
	
#if !TARGET_OS_IPHONE
	if([[url scheme] isEqualToString:@"ftp"])
	return [[(FTPTransferController*)[NSClassFromString(@"FTPTransferController") alloc] initWithBaseURL:url] autorelease];
	if([[url scheme] isEqualToString:@"ftps"])
	return [[(FTPSTransferController*)[NSClassFromString(@"FTPSTransferController") alloc] initWithBaseURL:url] autorelease];
	
	if([[url scheme] isEqualToString:@"ssh"])
	return [[(SFTPTransferController*)[NSClassFromString(@"SFTPTransferController") alloc] initWithBaseURL:url] autorelease];
#endif
	
	return nil;
}

- (id) init
{
	return [self initWithBaseURL:nil];
}

- (id) initWithBaseURL:(NSURL*)url
{
	NSString*				host = [url host];
	struct in_addr			ipv4Address;
	UInt32					address;
	
	if(![[url scheme] isEqualToString:[[self class] urlScheme]]) {
		[self release];
		return nil;
	}
	
	if((self = [super init])) {
		_baseURL = [url copy];
#if !TARGET_OS_IPHONE
		if([[[NSHost currentHost] names] containsObject:host] || [[[NSHost currentHost] addresses] containsObject:host] || [host hasSuffix:@".local"])
		_localHost = YES;
		else
#endif
		if(inet_pton(AF_INET, [host UTF8String], &ipv4Address) == 1) { //FIXME: Also handle local IPv6 addresses
			address = ntohl(ipv4Address.s_addr);
			if((address >= MAKE_IPV4(10, 0, 0, 0)) && (address <= MAKE_IPV4(10, 255, 255, 255)))
			_localHost = YES;
			else if((address >= MAKE_IPV4(172, 16, 0, 0)) && (address <= MAKE_IPV4(172, 31, 255, 255)))
			_localHost = YES;
			else if((address >= MAKE_IPV4(192, 168, 0, 0)) && (address <= MAKE_IPV4(192, 168, 255, 255)))
			_localHost = YES;
		}
	}
	
	return self;
}

- (id) initWithHost:(NSString*)host port:(UInt16)port username:(NSString*)username password:(NSString*)password basePath:(NSString*)basePath
{
	return [self initWithBaseURL:[NSURL URLWithScheme:[[self class] urlScheme] user:username password:password host:host port:port path:basePath]];
}

- (void) _cleanUp_FileTransferController
{
	if(_reachability)
	CFRelease(_reachability);
}

- (void) finalize
{
	[self _cleanUp_FileTransferController];
	
	[super finalize];
}

- (void) dealloc
{
	[self _cleanUp_FileTransferController];
	
#if !TARGET_OS_IPHONE
	[_encryptionPassword release];
#endif
	[_baseURL release];
	
	[super dealloc];
}

- (void) setMaxLength:(NSUInteger)length
{
	_maxLength = length;
	_currentLength = 0;
}

- (void) setCurrentLength:(NSUInteger)length
{
	if((_maxLength > 0) && (length != _currentLength)) {
		_currentLength = length;
		if([_delegate respondsToSelector:@selector(fileTransferControllerDidUpdateProgress:)])
		[_delegate fileTransferControllerDidUpdateProgress:self];
	}
}

- (NSUInteger) transferSize
{
	return _maxLength;
}

- (float) transferProgress
{
	return (_maxLength > 0 ? MIN((float)_currentLength / (float)_maxLength, 1.0) : NAN);
}

- (NSUInteger) lastTransferSize
{
	return _totalSize;
}

#if !TARGET_OS_IPHONE

- (NSData*) lastTransferDigestData
{
	unsigned int*			ptr = (unsigned int*)_digestBuffer;
	NSData*					data = nil;
	
	if(ptr[0] && ptr[1] && ptr[2] && ptr[3])
	data = [NSData dataWithBytes:_digestBuffer length:16];
	
	return data;
}

#endif

- (NSString*) absolutePathForRemotePath:(NSString*)path
{
	NSString*					basePath = [_baseURL path];
	
	if([basePath length]) {
		if([path length]) {
			if([basePath hasSuffix:@"/"] || [path hasPrefix:@"/"])
			path = [basePath stringByAppendingString:path];
			else
			path = [basePath stringByAppendingFormat:@"/%@", path];
		}
		else
		path = basePath;
	}
	
	if([path length]) {
		if([path characterAtIndex:0] != '/')
		path = [@"/" stringByAppendingString:path];
	}
	else
	path = @"/";
	
	return path;
}

- (NSURL*) absoluteURLForRemotePath:(NSString*)path
{
	return [NSURL URLWithScheme:[_baseURL scheme] user:nil password:nil host:[_baseURL host] port:[[_baseURL port] unsignedShortValue] path:[self absolutePathForRemotePath:path] query:[_baseURL queryByReplacingPercentEscapes]];
}

- (NSURL*) fullAbsoluteURLForRemotePath:(NSString*)path
{
	return [NSURL URLWithScheme:[_baseURL scheme] user:[_baseURL user] password:[_baseURL passwordByReplacingPercentEscapes] host:[_baseURL host] port:[[_baseURL port] unsignedShortValue] path:[self absolutePathForRemotePath:path] query:[_baseURL queryByReplacingPercentEscapes]];
}

- (BOOL) checkReachability
{
	SCNetworkConnectionFlags	flags;
	
	if(_reachability == NULL) {
		_reachability = (void*)SCNetworkReachabilityCreateWithName(kCFAllocatorDefault, [[_baseURL host] UTF8String]);
		if(_reachability == NULL)
		return NO;
	}
	
	return (SCNetworkReachabilityGetFlags(_reachability, &flags) && IS_REACHABLE(flags) ? YES : NO);
}

- (BOOL) _downloadFileFromPath:(NSString*)remotePath toStream:(NSOutputStream*)stream
{
	[self doesNotRecognizeSelector:_cmd];
	return NO;
}

- (BOOL) downloadFileFromPath:(NSString*)remotePath toStream:(NSOutputStream*)stream
{
	BOOL						result = [self _downloadFileFromPath:remotePath toStream:stream];
	
	[self setMaxLength:0];
	
	return result;
}

- (BOOL) _uploadFileToPath:(NSString*)remotePath fromStream:(NSInputStream*)stream
{
	[self doesNotRecognizeSelector:_cmd];
	return NO;
}

- (BOOL) uploadFileToPath:(NSString*)remotePath fromStream:(NSInputStream*)stream
{
	BOOL						result = [self _uploadFileToPath:remotePath fromStream:stream];
	
	[self setMaxLength:0];
	
	return result;
}

#if !TARGET_OS_IPHONE

- (BOOL) _createDigestContext
{
	bzero(_digestBuffer, 16);
	
	if(_digestComputation) {
		_digestContext = malloc(sizeof(EVP_MD_CTX));
		EVP_DigestInit(_digestContext, kDigestType);
	}
	
	return YES;
}

- (void) _destroyDigestContext
{
	if(_digestContext) {
		free(_digestContext);
		_digestContext = NULL;
	}
}

- (BOOL) _createCypherContext:(BOOL)decrypt
{
	unsigned char				keyBuffer[EVP_MAX_KEY_LENGTH];
	unsigned char				ivBuffer[EVP_MAX_IV_LENGTH];
	NSData*						passwordData;
	
	if(_encryptionPassword) {
		passwordData = [_encryptionPassword dataUsingEncoding:NSUTF8StringEncoding];
		if(![passwordData length])
		return NO;
		
		if(EVP_BytesToKey(kEncryptionCipher, EVP_md5(), NULL, [passwordData bytes], [passwordData length], 1, keyBuffer, ivBuffer) == 0)
		return NO;
		
		_encryptionContext = malloc(sizeof(EVP_CIPHER_CTX));
		EVP_CIPHER_CTX_init(_encryptionContext);
		if((decrypt ? EVP_DecryptInit(_encryptionContext, kEncryptionCipher, keyBuffer, ivBuffer) : EVP_EncryptInit(_encryptionContext, kEncryptionCipher, keyBuffer, ivBuffer)) != 1) {
			EVP_CIPHER_CTX_cleanup(_encryptionContext);
			free(_encryptionContext);
			_encryptionContext = NULL;
			return NO;
		}
		
		_encryptionBufferBytes = malloc(0);
		_encryptionBufferSize = 0;
	}
	
	return YES;
}

- (void) _destroyCypherContext
{
	if(_encryptionContext) {
		free(_encryptionBufferBytes);
		EVP_CIPHER_CTX_cleanup(_encryptionContext);
		free(_encryptionContext);
		_encryptionContext = NULL;
	}
}

#endif

- (BOOL) openOutputStream:(NSOutputStream*)stream isFileTransfer:(BOOL)isFileTransfer
{
	_totalSize = 0;
	_fileTransfer = isFileTransfer;
	if(_fileTransfer) {
#if !TARGET_OS_IPHONE
		if(![self _createDigestContext] || ![self _createCypherContext:YES])
		return NO;
#endif
		_maxSpeed = ([self isLocalHost] ? 0.0 : _maxDownloadSpeed);
	}
	else
	_maxSpeed = 0.0;
	
	[stream open];
	if([stream streamStatus] != NSStreamStatusOpen) {
#if !TARGET_OS_IPHONE
		[self _destroyCypherContext];
		[self _destroyDigestContext];
#endif
		return NO;
	}
	
	return YES;
}

- (BOOL) writeToOutputStream:(NSOutputStream*)stream bytes:(const void*)bytes maxLength:(NSUInteger)length
{
	double						maxSpeed = (_fileTransfer && ![self isLocalHost] ? _maximumDownloadSpeed : 0.0);
	CFAbsoluteTime				time = 0.0;
	BOOL						success = YES;
	int							offset = 0,
								realLength,
								numBytes;
	void*						realBytes;
	CFTimeInterval				dTime;
	
#if !TARGET_OS_IPHONE
	if(_encryptionContext) {
		if(length + EVP_MAX_BLOCK_LENGTH != _encryptionBufferSize) {
			_encryptionBufferSize = length + EVP_MAX_BLOCK_LENGTH;
			free(_encryptionBufferBytes);
			_encryptionBufferBytes = malloc(_encryptionBufferSize);
		}
		
		realBytes = _encryptionBufferBytes;
		if(EVP_DecryptUpdate(_encryptionContext, realBytes, &realLength, bytes, length) != 1)
		success = NO;
	}
	else
#endif
	{
		realBytes = (void*)bytes;
		realLength = length;
	}
	
#if !TARGET_OS_IPHONE
	if(success && _digestContext) {
		if(EVP_DigestUpdate(_digestContext, realBytes, realLength) != 1)
		success = NO;
	}
#endif
	
	if(success && (realLength > 0)) {
		if(_maxSpeed)
		time = CFAbsoluteTimeGetCurrent();
		else if(maxSpeed) {
			while(1) {
				time = CFAbsoluteTimeGetCurrent();
				OSSpinLockLock(&_downloadLock);
				dTime = _downloadTime - time;
				OSSpinLockUnlock(&_downloadLock);
				if(dTime <= 0.0)
				break;
				usleep(dTime * 1000000.0);
			}
		}
		
		if(success) {
			success = NO;
			while(1) {
				numBytes = [stream write:((const uint8_t*)realBytes + offset) maxLength:(realLength - offset)]; //NOTE: Writing 0 bytes will close the stream
				if(numBytes < 0)
				break;
				offset += numBytes;
				if(offset == realLength) {
					success = YES;
					break;
				}
#ifdef __DEBUG__
				NSLog(@"%s wrote only %i bytes out of %i", __FUNCTION__, numBytes, realLength - offset);
#endif
			}
		}
		
		if(success) {
			if(_maxSpeed) {
				dTime = (double)realLength / _maxSpeed - (CFAbsoluteTimeGetCurrent() - time);
				if(dTime > 0.0)
				usleep(dTime * 1000000.0);
			}
			else if(maxSpeed) {
				dTime = (double)realLength / maxSpeed;
				OSSpinLockLock(&_downloadLock);
				_downloadTime = MAX(_downloadTime, time) + dTime;
				OSSpinLockUnlock(&_downloadLock);
			}
		}
	}
	
	if(success)
	_totalSize += length;
	
	return success;
}

- (BOOL) flushOutputStream:(NSOutputStream*)stream
{
	BOOL						success = YES;
#if !TARGET_OS_IPHONE
	int							offset = 0,
								outLength,
								numBytes;
	unsigned char				buffer[EVP_MAX_BLOCK_LENGTH];
#endif
	
#if !TARGET_OS_IPHONE
	if(_encryptionContext) {
		if(EVP_DecryptFinal(_encryptionContext, buffer, &outLength) != 1)
		success = NO;
		
		[self _destroyCypherContext];
		
		if(success) {
			success = NO;
			while(1) {
				numBytes = [stream write:((const uint8_t*)buffer + offset) maxLength:(outLength - offset)];
				if(numBytes < 0)
				break;
				offset += numBytes;
				if(offset == outLength) {
					success = YES;
					break;
				}
#ifdef __DEBUG__
				NSLog(@"%s wrote only %i bytes out of %i", __FUNCTION__, numBytes, outLength - offset);
#endif
			}
		}
		
		if(success && _digestContext) {
			if(EVP_DigestUpdate(_digestContext, buffer, outLength) != 1)
			success = NO;
		}
	}
	
	if(_digestContext) {
		if(success) {
			if(EVP_DigestFinal(_digestContext, _digestBuffer, (unsigned int*)&outLength) != 1)
			success = NO;
		}
		
		[self _destroyDigestContext];
	}
#endif
	
	return success;
}

- (void) closeOutputStream:(NSOutputStream*)stream
{
#if !TARGET_OS_IPHONE
	[self _destroyCypherContext];
	[self _destroyDigestContext];
#endif
	
	[stream close];
}

- (BOOL) openInputStream:(NSInputStream*)stream isFileTransfer:(BOOL)isFileTransfer
{
	_totalSize = 0;
	_fileTransfer = isFileTransfer;
	if(_fileTransfer) {
#if !TARGET_OS_IPHONE
		if(![self _createDigestContext] || ![self _createCypherContext:NO])
		return NO;
#endif
		_maxSpeed = ([self isLocalHost] ? 0.0 : _maxUploadSpeed);
	}
	else
	_maxSpeed = 0.0;
	
	[stream open];
	if([stream streamStatus] != NSStreamStatusOpen) {
#if !TARGET_OS_IPHONE
		[self _destroyCypherContext];
		[self _destroyDigestContext];
#endif
		return NO;
	}
	
	return YES;
}

- (NSInteger) readFromInputStream:(NSInputStream*)stream bytes:(void*)bytes maxLength:(NSUInteger)length
{
	double						maxSpeed = (_fileTransfer && ![self isLocalHost] ? _maximumUploadSpeed : 0.0);
	CFAbsoluteTime				time = 0.0;
	NSInteger					result;
	CFTimeInterval				dTime;
#if !TARGET_OS_IPHONE
	void*						newBytes;
	int							newLength;
#endif
	
#if !TARGET_OS_IPHONE
	if(_encryptionContext) {
		if(length <= EVP_MAX_BLOCK_LENGTH)
		return -1;
		
		if(length != _encryptionBufferSize) {
			_encryptionBufferSize = length;
			free(_encryptionBufferBytes);
			_encryptionBufferBytes = malloc(_encryptionBufferSize);
		}
		
		if(_maxSpeed)
		time = CFAbsoluteTimeGetCurrent();
		else if(maxSpeed) {
			while(1) {
				time = CFAbsoluteTimeGetCurrent();
				OSSpinLockLock(&_uploadLock);
				dTime = _uploadTime - time;
				OSSpinLockUnlock(&_uploadLock);
				if(dTime <= 0.0)
				break;
				usleep(dTime * 1000000.0);
			}
		}
		
		newBytes = _encryptionBufferBytes;
		result = [stream read:newBytes maxLength:(length - EVP_MAX_BLOCK_LENGTH)];
		
		if(result > 0) {
			if(_maxSpeed) {
				dTime = (double)result / _maxSpeed - (CFAbsoluteTimeGetCurrent() - time);
				if(dTime > 0.0)
				usleep(dTime * 1000000.0);
			}
			else if(maxSpeed) {
				dTime = (double)result / maxSpeed;
				OSSpinLockLock(&_uploadLock);
				_uploadTime = MAX(_uploadTime, time) + dTime;
				OSSpinLockUnlock(&_uploadLock);
			}
		}
		
		if(result > 0) {
			if(_digestContext) {
				if(EVP_DigestUpdate(_digestContext, newBytes, result) != 1)
				result = -1;
			}
			
			if(result > 0) {
				if(EVP_EncryptUpdate(_encryptionContext, bytes, &newLength, newBytes, result) == 1) //FIXME: We should encrypt directly into "bytes" if there's enough room
				result = newLength;
				else
				result = -1;
			}
		}
		if(result == 0) { //HACK: CFReadStreamCreateForStreamedHTTPRequest() will stop reading when reaching Content-Length, so NSInputStream may never have an opportunity to return 0
			if(_digestContext) {
				if(EVP_DigestFinal(_digestContext, _digestBuffer, (unsigned int*)&newLength) != 1)
				result = -1;
			}
			
			if(result == 0) {
				if(EVP_EncryptFinal(_encryptionContext, bytes, &newLength) == 1)
				result = newLength;
				else
				result = -1;
			}
			
			[self _destroyCypherContext];
			[self _destroyDigestContext];
		}
	}
	else
#endif
	{
		if(_maxSpeed)
		time = CFAbsoluteTimeGetCurrent();
		else if(maxSpeed) {
			while(1) {
				time = CFAbsoluteTimeGetCurrent();
				OSSpinLockLock(&_uploadLock);
				dTime = _uploadTime - time;
				OSSpinLockUnlock(&_uploadLock);
				if(dTime <= 0.0)
				break;
				usleep(dTime * 1000000.0);
			}
		}
		
		result = [stream read:bytes maxLength:length];
		
		if(result > 0) {
			if(_maxSpeed) {
				dTime = (double)result / _maxSpeed - (CFAbsoluteTimeGetCurrent() - time);
				if(dTime > 0.0)
				usleep(dTime * 1000000.0);
			}
			else if(maxSpeed) {
				dTime = (double)result / maxSpeed;
				OSSpinLockLock(&_uploadLock);
				_uploadTime = MAX(_uploadTime, time) + dTime;
				OSSpinLockUnlock(&_uploadLock);
			}
		}
		
#if !TARGET_OS_IPHONE
		if(_digestContext) {
			if(result > 0) {
				if(EVP_DigestUpdate(_digestContext, bytes, result) != 1)
				result = -1;
			}
			if((result == 0) || (_currentLength + result == _maxLength)) { //HACK: CFReadStreamCreateForStreamedHTTPRequest() will stop reading when reaching Content-Length, so NSInputStream may never have an opportunity to return 0
				if(EVP_DigestFinal(_digestContext, _digestBuffer, (unsigned int*)&newLength) != 1)
				result = -1;
				
				[self _destroyDigestContext];
			}
		}
#endif
	}
	
	if(result > 0)
	_totalSize += result;
		
	return result;
}

- (void) closeInputStream:(NSInputStream*)stream
{
#if !TARGET_OS_IPHONE
	[self _destroyCypherContext];
	[self _destroyDigestContext];
#endif
	
	[stream close];
}

@end

@implementation FileTransferController (Extensions)

- (BOOL) uploadFileToPath:(NSString*)remotePath fromStream:(NSInputStream*)stream length:(NSUInteger)length
{
	BOOL					success;
	
#if !TARGET_OS_IPHONE
	if([self encryptionPassword])
	length = (length / kEncryptionCipherBlockSize + 1) * kEncryptionCipherBlockSize;
#endif
	[self setMaxLength:length];
	
	success = [self uploadFileToPath:remotePath fromStream:stream];
	
	return success;
}

- (BOOL) downloadFileFromPathToNull:(NSString*)remotePath
{
	return [self downloadFileFromPath:remotePath toStream:[NSOutputStream outputStreamToFileAtPath:@"/dev/null" append:NO]];
}

- (BOOL) downloadFileFromPath:(NSString*)remotePath toPath:(NSString*)localPath
{
	NSOutputStream*			stream;
	BOOL					success;
	NSError*				error;
	
	localPath = [localPath stringByStandardizingPath];
	stream = [NSOutputStream outputStreamToFileAtPath:localPath append:NO];
	if(stream == nil)
	return NO;
	
	success = [self downloadFileFromPath:remotePath toStream:stream];
	
	if(!success && ([stream streamStatus] > NSStreamStatusNotOpen)) {
		if(![[NSFileManager defaultManager] removeItemAtPath:localPath error:&error])
		NSLog(@"%@: %@", __FUNCTION__, error);
	}
	
	return success;
}

- (BOOL) uploadFileFromPath:(NSString*)localPath toPath:(NSString*)remotePath
{
	NSDictionary*			info;
	BOOL					success;
	NSUInteger				maxLength;
	
	localPath = [localPath stringByStandardizingPath];
	while(1) {
		info = [[NSFileManager defaultManager] attributesOfItemAtPath:localPath error:NULL];
		if(info == nil)
		return NO;
		if([[info objectForKey:NSFileType] isEqualToString:NSFileTypeSymbolicLink])
		localPath = [[NSFileManager defaultManager] destinationOfSymbolicLinkAtPath:localPath error:NULL];
		else
		break;
	}
	
	maxLength = [[info objectForKey:NSFileSize] unsignedIntegerValue];
#if !TARGET_OS_IPHONE
	if([self encryptionPassword])
	maxLength = (maxLength / kEncryptionCipherBlockSize + 1) * kEncryptionCipherBlockSize;
#endif
	[self setMaxLength:maxLength];
	
	success = [self uploadFileToPath:remotePath fromStream:[NSInputStream inputStreamWithFileAtPath:localPath]];
	
	return success;
}

- (NSData*) downloadFileFromPathToData:(NSString*)remotePath
{
	NSOutputStream*			stream;
	
	stream = [NSOutputStream outputStreamToMemory];
	if(stream == nil)
	return nil;
	
	return ([self downloadFileFromPath:remotePath toStream:stream] ? [stream propertyForKey:NSStreamDataWrittenToMemoryStreamKey] : nil);
}

- (BOOL) uploadFileFromData:(NSData*)data toPath:(NSString*)remotePath
{
	BOOL					success;
	NSUInteger				maxLength;
	
	if(data == nil)
	return NO;
	
	maxLength = [data length];
#if !TARGET_OS_IPHONE
	if([self encryptionPassword])
	maxLength = (maxLength / kEncryptionCipherBlockSize + 1) * kEncryptionCipherBlockSize;
#endif
	[self setMaxLength:maxLength];
	
	success = [self uploadFileToPath:remotePath fromStream:[NSInputStream inputStreamWithData:data]];
	
	return success;
}

- (BOOL) openDataStream:(id)userInfo
{
	return YES;
}

- (NSInteger) readDataFromStream:(id)userInfo buffer:(void*)buffer maxLength:(NSUInteger)length
{
	DataInfo*				info = (DataInfo*)[userInfo pointerValue];
	
	length = MIN(length, info->size);
	bcopy(info->buffer, buffer, length);
	info->buffer += length;
	info->size -= length;
	
	return length;
}

- (NSInteger) writeDataToStream:(id)userInfo buffer:(const void*)buffer maxLength:(NSUInteger)length
{
	DataInfo*				info = (DataInfo*)[userInfo pointerValue];
	
	length = MIN(length, info->size);
	bcopy(buffer, info->buffer, length);
	info->buffer += length;
	info->size -= length;
	
	return length;
}

- (void) closeDataStream:(id)userInfo
{
	;
}

- (NSInteger) downloadFileFromPath:(NSString*)remotePath toBuffer:(void*)buffer capacity:(NSUInteger)capacity
{
	BOOL					success;
	DataWriteStream*		writeStream;
	DataInfo				info;
	
	if(buffer == NULL)
	return -1;
	
	info.buffer = (void*)buffer;
	info.size = capacity;
	writeStream = [[DataWriteStream alloc] initWithDataDestination:(id<DataStreamDestination>)self userInfo:[NSValue valueWithPointer:&info]];
	success = [self downloadFileFromPath:remotePath toStream:writeStream];
	[writeStream release];
	
	return (success ? capacity - info.size : -1);
}

- (BOOL) uploadFileFromBytes:(const void*)bytes length:(NSUInteger)length toPath:(NSString*)remotePath
{
	BOOL					success;
	NSUInteger				maxLength;
	DataReadStream*			readStream;
	DataInfo				info;
	
	if(bytes == NULL)
	return NO;
	
	maxLength = length;
#if !TARGET_OS_IPHONE
	if([self encryptionPassword])
	maxLength = (maxLength / kEncryptionCipherBlockSize + 1) * kEncryptionCipherBlockSize;
#endif
	[self setMaxLength:maxLength];
	
	info.buffer = (void*)bytes;
	info.size = length;
	readStream = [[DataReadStream alloc] initWithDataSource:(id<DataStreamSource>)self userInfo:[NSValue valueWithPointer:&info]];
	success = [self uploadFileToPath:remotePath fromStream:readStream];
	[readStream release];
	
	return success;
}

@end

@implementation StreamTransferController

@synthesize activeStream=_activeStream;

+ (id) allocWithZone:(NSZone*)zone
{
	if(self == [StreamTransferController class])
	[[NSException exceptionWithName:NSInternalInconsistencyException reason:@"StreamTransferController is an abstract class" userInfo:nil] raise];
	
	return [super allocWithZone:zone];
}

- (id) initWithBaseURL:(NSURL*)url
{
	if((self = [super initWithBaseURL:url]))
	_streamBuffer = malloc(kStreamBufferSize);
	
	return self;
}

- (void) _cleanUp_StreamTransferController
{
	[self invalidate];
	
	if(_streamBuffer)
	free(_streamBuffer);
}

- (void) finalize
{
	[self _cleanUp_StreamTransferController];
	
	[super finalize];
}

- (void) dealloc
{
	[self _cleanUp_StreamTransferController];
	
	[super dealloc];
}

- (void) invalidate
{
	[_userInfo release];
	_userInfo = nil;
	
	if([_dataStream isKindOfClass:[NSInputStream class]])
	[self closeInputStream:_dataStream];
	else if([_dataStream isKindOfClass:[NSOutputStream class]])
	[self closeOutputStream:_dataStream];
	[_dataStream release];
	_dataStream = nil;
	
	if(_activeStream) {
		if(CFGetTypeID(_activeStream) == CFReadStreamGetTypeID()) {
			if([[self class] useAsyncStreams]) {
				CFReadStreamUnscheduleFromRunLoop((CFReadStreamRef)_activeStream, CFRunLoopGetCurrent(), kFileTransferRunLoopActiveMode);
				CFReadStreamSetClient((CFReadStreamRef)_activeStream, kCFStreamEventNone, NULL, NULL);
			}
			CFReadStreamClose((CFReadStreamRef)_activeStream);
		}
		else if(CFGetTypeID(_activeStream) == CFWriteStreamGetTypeID()) {
			if([[self class] useAsyncStreams]) {
				CFWriteStreamUnscheduleFromRunLoop((CFWriteStreamRef)_activeStream, CFRunLoopGetCurrent(), kFileTransferRunLoopActiveMode);
				CFWriteStreamSetClient((CFWriteStreamRef)_activeStream, kCFStreamEventNone, NULL, NULL);
			}
			CFWriteStreamClose((CFWriteStreamRef)_activeStream);
		}
		CFRelease(_activeStream);
		_activeStream = NULL;
	}
}

static void _ReadStreamClientCallBack(CFReadStreamRef stream, CFStreamEventType type, void* clientCallBackInfo)
{
	NSAutoreleasePool*		pool = [NSAutoreleasePool new];
	
	[(StreamTransferController*)clientCallBackInfo readStreamClientCallBack:stream type:type];
	
	[pool drain];
}

- (void) _doneWithResult:(id)result
{
	[self invalidate];
	
	if(result) {
		if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidSucceed:)])
		[[self delegate] fileTransferControllerDidSucceed:self];
	}
	
	_result = [result retain];
	CFRunLoopStop(CFRunLoopGetCurrent());
}

- (void) readStreamClientCallBack:(CFReadStreamRef)stream type:(CFStreamEventType)type
{
	id							result;
	NSError*					error;
	BOOL						success;
	
	switch(type) {
		
		case kCFStreamEventOpenCompleted:
		break;
		
		case kCFStreamEventHasBytesAvailable:
		_transferLength = CFReadStreamRead(stream, _streamBuffer, kStreamBufferSize);
		if(_transferLength > 0) {
			if(_dataStream && ![self writeToOutputStream:_dataStream bytes:_streamBuffer maxLength:_transferLength]) {
				if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)]) {
					error = [_dataStream streamError];
					[[self delegate] fileTransferControllerDidFail:self withError:([error code] ? error : MAKE_FILETRANSFERCONTROLLER_ERROR(@"Failed writing to output stream (status = %i)", [_dataStream streamStatus]))];
				}
				[self _doneWithResult:nil];
			}
			[self setCurrentLength:([self currentLength] + _transferLength)];
		}
		break;
		
		case kCFStreamEventErrorOccurred:
		if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
		[[self delegate] fileTransferControllerDidFail:self withError:[NSMakeCollectable(CFReadStreamCopyError(stream)) autorelease]];
		[self _doneWithResult:nil];
		break;
		
		case kCFStreamEventEndEncountered:
		if(_dataStream) {
			success = [self flushOutputStream:_dataStream];
			[self closeOutputStream:_dataStream];
			if(success == NO) {
				if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)]) {
					error = [_dataStream streamError];
					[[self delegate] fileTransferControllerDidFail:self withError:([error code] ? error : MAKE_FILETRANSFERCONTROLLER_ERROR(@"Failed flushing output stream (status = %i)", [_dataStream streamStatus]))];
				}
				[self _doneWithResult:nil];
				break;
			}
		}
		result = [self processReadResultStream:_dataStream userInfo:_userInfo error:&error];
		if(result == nil) {
			if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
			[[self delegate] fileTransferControllerDidFail:self withError:error];
		}
		[self _doneWithResult:result];
		break;
		
	}
}

/* This method takes ownership of the output stream */
- (id) runReadStream:(CFReadStreamRef)readStream dataStream:(NSOutputStream*)dataStream userInfo:(id)info isFileTransfer:(BOOL)allowEncryption
{
	BOOL					delegateHasShouldAbort = [[self delegate] respondsToSelector:@selector(fileTransferControllerShouldAbort:)];
	CFStreamClientContext	context = {0, self, NULL, NULL, NULL};
	BOOL					opened = NO;
	CFAbsoluteTime			timeout = [self timeOut],
							lastTime = 0.0,
							time;
	id						result;
	SInt32					value;
	
	if(dataStream && ![self openOutputStream:dataStream isFileTransfer:allowEncryption]) {
		CFRelease(readStream);
		return nil;
	}
	
	if([[self class] useAsyncStreams]) {
		CFReadStreamSetClient(readStream, kCFStreamEventOpenCompleted | kCFStreamEventHasBytesAvailable | kCFStreamEventErrorOccurred | kCFStreamEventEndEncountered, _ReadStreamClientCallBack, &context);
		CFReadStreamScheduleWithRunLoop(readStream, CFRunLoopGetCurrent(), kFileTransferRunLoopActiveMode);
	}
	CFReadStreamOpen(readStream);
	
	_activeStream = readStream;
	_dataStream = [dataStream retain];
	_userInfo = [info retain];
	
	if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidStart:)])
	[[self delegate] fileTransferControllerDidStart:self];
	
	_result = nil;
	if([[self class] useAsyncStreams]) {
		do {
			value = CFRunLoopRunInMode(kFileTransferRunLoopActiveMode, kRunLoopInterval, true);
			time = CFAbsoluteTimeGetCurrent();
			if(value != kCFRunLoopRunTimedOut)
			lastTime = time;
			else if((timeout > 0.0) && (time - lastTime >= timeout)) {
				if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
				[[self delegate] fileTransferControllerDidFail:self withError:MAKE_FILETRANSFERCONTROLLER_ERROR(@"Timeout while reading from stream")];
				break;
			}
			if(delegateHasShouldAbort && [[self delegate] fileTransferControllerShouldAbort:self])
			break;
		} while(_activeStream && (value != kCFRunLoopRunStopped) && (value != kCFRunLoopRunFinished));
	}
	else {
		do {
			switch(CFReadStreamGetStatus(readStream)) {
				
				case kCFStreamStatusOpen:
				if(opened)
				[self readStreamClientCallBack:readStream type:kCFStreamEventHasBytesAvailable];
				else {
					[self readStreamClientCallBack:readStream type:kCFStreamEventOpenCompleted];
					opened = YES;
				}
				break;
				
				case kCFStreamStatusAtEnd:
				[self readStreamClientCallBack:readStream type:kCFStreamEventEndEncountered];
				readStream = NULL;
				break;
				
				case kCFStreamStatusError:
				[self readStreamClientCallBack:readStream type:kCFStreamEventErrorOccurred];
				readStream = NULL;
				break;
				
				case kCFStreamStatusClosed:
				readStream = NULL;
				break;
				
			}
		} while(readStream && (!delegateHasShouldAbort || ![[self delegate] fileTransferControllerShouldAbort:self]));
	}
	result = [_result autorelease];
	_result = nil;
	[self invalidate];
	
	return result;
}

- (id) processReadResultStream:(NSOutputStream*)stream userInfo:(id)info error:(NSError**)error
{
	[self doesNotRecognizeSelector:_cmd];
	return nil;
}

static void _WriteStreamClientCallBack(CFWriteStreamRef stream, CFStreamEventType type, void* clientCallBackInfo)
{
	NSAutoreleasePool*		pool = [NSAutoreleasePool new];
	
	[(StreamTransferController*)clientCallBackInfo writeStreamClientCallBack:stream type:type];
	
	[pool drain];
}

- (void) writeStreamClientCallBack:(CFWriteStreamRef)stream type:(CFStreamEventType)type
{
	CFIndex						count;
	
	switch(type) {
		
		case kCFStreamEventOpenCompleted:
		break;
		
		case kCFStreamEventCanAcceptBytes:
		if(_transferOffset == 0) {
			_transferLength = (_dataStream ? [self readFromInputStream:_dataStream bytes:_streamBuffer maxLength:kStreamBufferSize] : 0);
			if(_transferLength < 0) {
				if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
				[[self delegate] fileTransferControllerDidFail:self withError:MAKE_FILETRANSFERCONTROLLER_ERROR(@"Failed reading from data stream")];
				[self _doneWithResult:nil];
			}
		}
		if(_transferLength >= 0) {
			count = CFWriteStreamWrite(stream, _streamBuffer + _transferOffset, _transferLength - _transferOffset); //Writing zero bytes will end the stream
			if(count > 0) {
				_transferOffset += count;
				if(_transferOffset == _transferLength)
				_transferOffset = 0;
				[self setCurrentLength:([self currentLength] + count)];
			}
		}
		break;
		
		case kCFStreamEventErrorOccurred:
		if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
		[[self delegate] fileTransferControllerDidFail:self withError:[NSMakeCollectable(CFWriteStreamCopyError(stream)) autorelease]];
		[self _doneWithResult:nil];
		break;
		
		case kCFStreamEventEndEncountered:
		if(_dataStream)
		[self closeInputStream:_dataStream];
		[self _doneWithResult:[NSNumber numberWithBool:YES]];
		break;
		
	}
}

/* This method takes ownership of the output stream */
- (id) runWriteStream:(CFWriteStreamRef)writeStream dataStream:(NSInputStream*)dataStream userInfo:(id)info isFileTransfer:(BOOL)allowEncryption
{
	BOOL					delegateHasShouldAbort = [[self delegate] respondsToSelector:@selector(fileTransferControllerShouldAbort:)];
	CFStreamClientContext	context = {0, self, NULL, NULL, NULL};
	BOOL					opened = NO;
	CFAbsoluteTime			timeout = [self timeOut],
							lastTime = 0.0,
							time;
	id						result;
	SInt32					value;
	
	if(dataStream && ![self openInputStream:dataStream  isFileTransfer:allowEncryption]) {
		CFRelease(writeStream);
		return nil;
	}
	
	if([[self class] useAsyncStreams]) {
		CFWriteStreamSetClient(writeStream, kCFStreamEventOpenCompleted | kCFStreamEventCanAcceptBytes | kCFStreamEventErrorOccurred | kCFStreamEventEndEncountered, _WriteStreamClientCallBack, &context);
		CFWriteStreamScheduleWithRunLoop(writeStream, CFRunLoopGetCurrent(), kFileTransferRunLoopActiveMode);
	}
	CFWriteStreamOpen(writeStream);
	
	_activeStream = writeStream;
	_dataStream = [dataStream retain];
	_userInfo = [info retain];
	_transferOffset = 0;
	
	if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidStart:)])
	[[self delegate] fileTransferControllerDidStart:self];
	
	_result = nil;
	if([[self class] useAsyncStreams]) {
		do {
			value = CFRunLoopRunInMode(kFileTransferRunLoopActiveMode, kRunLoopInterval, true);
			time = CFAbsoluteTimeGetCurrent();
			if(value != kCFRunLoopRunTimedOut)
			lastTime = time;
			else if((timeout > 0.0) && (time - lastTime >= timeout)) {
				if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
				[[self delegate] fileTransferControllerDidFail:self withError:MAKE_FILETRANSFERCONTROLLER_ERROR(@"Timeout while writing to stream")];
				break;
			}
			if(delegateHasShouldAbort && [[self delegate] fileTransferControllerShouldAbort:self])
			break;
		} while(_activeStream && (value != kCFRunLoopRunStopped) && (value != kCFRunLoopRunFinished));
	}
	else {
		do {
			switch(CFWriteStreamGetStatus(writeStream)) {
				
				case kCFStreamStatusOpen:
				if(opened)
				[self writeStreamClientCallBack:writeStream type:kCFStreamEventCanAcceptBytes];
				else {
					[self writeStreamClientCallBack:writeStream type:kCFStreamEventOpenCompleted];
					opened = YES;
				}
				break;
				
				case kCFStreamStatusAtEnd:
				[self writeStreamClientCallBack:writeStream type:kCFStreamEventEndEncountered];
				writeStream = NULL;
				break;
				
				case kCFStreamStatusError:
				[self writeStreamClientCallBack:writeStream type:kCFStreamEventErrorOccurred];
				writeStream = NULL;
				break;
				
				case kCFStreamStatusClosed:
				writeStream = NULL;
				break;
				
			}
		} while(writeStream && (!delegateHasShouldAbort || ![[self delegate] fileTransferControllerShouldAbort:self]));
	}	
	result = [_result autorelease];
	_result = nil;
	[self invalidate];
	
	return result;
}

@end
