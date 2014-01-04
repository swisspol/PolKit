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

#import <openssl/hmac.h>
#import <openssl/evp.h>
#import <openssl/rand.h>
#import <pthread.h>

#define kBufferSize				1024

static pthread_mutex_t*			_opensslLocks = NULL;
static const char				_magic[]="Salted__";

static unsigned long _opensslThreadID()
{
	return (unsigned long)pthread_self();
}

static void _opensslLocking(int mode, int type, const char* file, int line)
{
	if(mode & CRYPTO_LOCK)
	pthread_mutex_lock(&_opensslLocks[type]);
	else
	pthread_mutex_unlock(&_opensslLocks[type]);
}

static void EnableOpenSSLMultiThreading()
{
	int							i;
	
	if(_opensslLocks == NULL) {
		_opensslLocks = malloc(CRYPTO_num_locks() * sizeof(pthread_mutex_t));
		for(i = 0; i < CRYPTO_num_locks(); ++i)
		pthread_mutex_init(&_opensslLocks[i], NULL);
		
		CRYPTO_set_id_callback(_opensslThreadID);
		CRYPTO_set_locking_callback(_opensslLocking);
	}
}

/*
static void DisableOpenSSLMultiThreading()
{
	int							i;

	if(_opensslLocks) {
		CRYPTO_set_id_callback(NULL);
		CRYPTO_set_locking_callback(NULL);
		
		for(i = 0; i < CRYPTO_num_locks(); ++i)
		pthread_mutex_destroy(&_opensslLocks[i]);
		free(_opensslLocks);
		_opensslLocks = NULL;
	}
}
*/

static NSData* _ComputeDigest(const EVP_MD* type, const void* bytes, NSUInteger length)
{
	EVP_MD_CTX					context;
	unsigned char				value[EVP_MAX_MD_SIZE];
	unsigned int				size;
	
	if(EVP_DigestInit(&context, type) != 1)
	return nil;
	if(EVP_DigestUpdate(&context, bytes, length) != 1)
	return nil;
	if(EVP_DigestFinal(&context, value, &size) != 1)
	return nil;
	
	return [NSData dataWithBytes:value length:size];
}

@implementation NSData (Encryption)

+ (void) load
{
	EnableOpenSSLMultiThreading();
}

+ (NSData*) md5DigestWithBytes:(const void*)bytes length:(NSUInteger)length
{
	return _ComputeDigest(EVP_md5(), bytes, length);
}

+ (NSData*) sha1DigestWithBytes:(const void*)bytes length:(NSUInteger)length
{
	return _ComputeDigest(EVP_sha1(), bytes, length);
}

- (NSData*) md5Digest
{
	return _ComputeDigest(EVP_md5(), [self bytes], [self length]);
}

- (NSData*) sha1Digest
{
	return _ComputeDigest(EVP_sha1(), [self bytes], [self length]);
}

- (NSData*) sha1HMacWithKey:(NSString*)key
{
	const char*					keyString = [key UTF8String];
	HMAC_CTX					context;
	unsigned char				value[EVP_MAX_MD_SIZE];
	unsigned int				length;
	
	HMAC_CTX_init(&context);
	HMAC_Init(&context, keyString, strlen(keyString), EVP_sha1());
	HMAC_Update(&context, [self bytes], [self length]);
	HMAC_Final(&context, value, &length);
	HMAC_CTX_cleanup(&context);
	
	return [NSData dataWithBytes:value length:length];
}
	
- (NSString*) encodeBase64
{
	NSString*					string;
	char*						base64Pointer;
	long						base64Length;
	BIO*						mem;
	BIO*						b64;
	
	mem = BIO_new(BIO_s_mem());
	b64 = BIO_new(BIO_f_base64());
	BIO_set_flags(b64, BIO_FLAGS_BASE64_NO_NL);
	mem = BIO_push(b64, mem);
	BIO_write(mem, [self bytes], [self length]);
	(void)BIO_flush(mem);
	base64Length = BIO_get_mem_data(mem, &base64Pointer);
	string = [[NSString alloc] initWithBytes:base64Pointer length:base64Length encoding:NSASCIIStringEncoding];
	BIO_free_all(mem);
	
	return [string autorelease];
}

/* See apps/enc.c from OpenSSL source */
- (NSData*) _copyEncryptedDataUsingCipher:(const EVP_CIPHER*)cipher passwordData:(NSData*)passwordData salted:(BOOL)salted
{
	int							inLength = [self length],
								outLength;
	unsigned char				buffer[kBufferSize + EVP_MAX_BLOCK_LENGTH];
	EVP_CIPHER_CTX				context;
	unsigned char				keyBuffer[EVP_MAX_KEY_LENGTH];
	unsigned char				ivBuffer[EVP_MAX_IV_LENGTH];
	NSMutableData*				data;
	unsigned char				salt[PKCS5_SALT_LEN];
	
	if(salted && !RAND_pseudo_bytes(salt, PKCS5_SALT_LEN))
	return nil;
	
	if(EVP_BytesToKey(cipher, EVP_md5(), salted ? salt : NULL, [passwordData bytes], [passwordData length], 1, keyBuffer, ivBuffer) == 0)
	return nil;
	
	EVP_CIPHER_CTX_init(&context);
	
	if(EVP_EncryptInit(&context, cipher, keyBuffer, ivBuffer) == 1) {
		data = [[NSMutableData alloc] initWithCapacity:((salted ? sizeof(_magic) - 1 + PKCS5_SALT_LEN : 0) + [self length] + EVP_MAX_BLOCK_LENGTH)];
		if(salted) {
			[data appendBytes:_magic length:(sizeof(_magic) - 1)];
			[data appendBytes:salt length:PKCS5_SALT_LEN];
		}
		while(inLength > 0) {
			if(EVP_EncryptUpdate(&context, buffer, &outLength, (unsigned char*)[self bytes] + [self length] - inLength, MIN(inLength, kBufferSize)) != 1) {
				[data release];
				data = nil;
				break;
			}
			[data appendBytes:buffer length:outLength];
			inLength -= MIN(inLength, kBufferSize);
		}
		if(EVP_EncryptFinal(&context, buffer, &outLength) == 1)
		[data appendBytes:buffer length:outLength];
		else {
			[data release];
			data = nil;
		}
	}
	else
	data = nil;
	
	EVP_CIPHER_CTX_cleanup(&context);
	
	return data;
}

- (NSData*) encryptBlowfishWithPassword:(NSString*)password useSalt:(BOOL)flag
{
	return [[self _copyEncryptedDataUsingCipher:EVP_bf_cbc() passwordData:[password dataUsingEncoding:NSUTF8StringEncoding] salted:flag] autorelease];
}

- (NSData*) encryptAES128WithPassword:(NSString*)password useSalt:(BOOL)flag
{
	return [[self _copyEncryptedDataUsingCipher:EVP_aes_128_cbc() passwordData:[password dataUsingEncoding:NSUTF8StringEncoding] salted:flag] autorelease];
}

- (NSData*) encryptAES256WithPassword:(NSString*)password useSalt:(BOOL)flag
{
	return [[self _copyEncryptedDataUsingCipher:EVP_aes_256_cbc() passwordData:[password dataUsingEncoding:NSUTF8StringEncoding] salted:flag] autorelease];
}

/* See apps/enc.c from OpenSSL source */
- (NSData*) _copyDecryptedDataUsingCipher:(const EVP_CIPHER*)cipher passwordData:(NSData*)passwordData salted:(BOOL)salted
{
	int							inLength = [self length],
								outLength;
	unsigned char				buffer[kBufferSize + EVP_MAX_BLOCK_LENGTH];
	EVP_CIPHER_CTX				context;
	unsigned char				keyBuffer[EVP_MAX_KEY_LENGTH];
	unsigned char				ivBuffer[EVP_MAX_IV_LENGTH];
	NSMutableData*				data;
	unsigned char				salt[PKCS5_SALT_LEN];
	
	if(salted) {
		if(inLength < sizeof(_magic) - 1 + PKCS5_SALT_LEN)
		return nil;
		if(memcmp([self bytes], _magic, sizeof(_magic) - 1))
		return nil;
		bcopy((char*)[self bytes] + sizeof(_magic) - 1, salt, PKCS5_SALT_LEN);
		inLength -= sizeof(_magic) - 1 + PKCS5_SALT_LEN;
	}
	
	if(EVP_BytesToKey(cipher, EVP_md5(), salted ? salt : NULL, [passwordData bytes], [passwordData length], 1, keyBuffer, ivBuffer) == 0)
	return nil;
	
	EVP_CIPHER_CTX_init(&context);
	
	if(EVP_DecryptInit(&context, cipher, keyBuffer, ivBuffer) == 1) {
		data = [[NSMutableData alloc] initWithCapacity:([self length] + EVP_MAX_BLOCK_LENGTH)];
		while(inLength > 0) {
			if(EVP_DecryptUpdate(&context, buffer, &outLength, (unsigned char*)[self bytes] + [self length] - inLength, MIN(inLength, kBufferSize)) != 1) {
				[data release];
				data = nil;
				break;
			}
			[data appendBytes:buffer length:outLength];
			inLength -= MIN(inLength, kBufferSize);
		}
		if(EVP_DecryptFinal(&context, buffer, &outLength) == 1)
		[data appendBytes:buffer length:outLength];
		else {
			[data release];
			data = nil;
		}
	}
	else
	data = nil;
	
	EVP_CIPHER_CTX_cleanup(&context);
	
	return data;
}

- (NSData*) decryptBlowfishWithPassword:(NSString*)password useSalt:(BOOL)flag
{
	return [[self _copyDecryptedDataUsingCipher:EVP_bf_cbc() passwordData:[password dataUsingEncoding:NSUTF8StringEncoding] salted:flag] autorelease];
}

- (NSData*) decryptAES128WithPassword:(NSString*)password useSalt:(BOOL)flag
{
	return [[self _copyDecryptedDataUsingCipher:EVP_aes_128_cbc() passwordData:[password dataUsingEncoding:NSUTF8StringEncoding] salted:flag] autorelease];
}

- (NSData*) decryptAES256WithPassword:(NSString*)password useSalt:(BOOL)flag
{
	return [[self _copyDecryptedDataUsingCipher:EVP_aes_256_cbc() passwordData:[password dataUsingEncoding:NSUTF8StringEncoding] salted:flag] autorelease];
}

@end

@implementation NSString (Encryption)

- (NSData*) decodeBase64
{
	NSMutableData*				outData = [NSMutableData data];
	NSData*						inData;
	BIO*						mem;
	BIO*						b64;
	char						buffer[kBufferSize];
	int							length;
	
	inData = [self dataUsingEncoding:NSASCIIStringEncoding];
	if(inData == nil) {
		[self release];
		return nil;
	}
	
	mem = BIO_new_mem_buf((void*)[inData bytes], [inData length]);
	b64 = BIO_new(BIO_f_base64());
	BIO_set_flags(b64, BIO_FLAGS_BASE64_NO_NL);
	mem = BIO_push(b64, mem);
	while(1) {
		length = BIO_read(mem, buffer, kBufferSize);
		if(length <= 0)
		break;
		[outData appendBytes:buffer length:length];
	}
	BIO_free_all(mem);
	
	return outData; 
}

@end
