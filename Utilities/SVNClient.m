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

//FIXME: Disable SVN_DEPRECATED warnings when building on 10.6
#if defined(MAC_OS_X_VERSION_10_6) && (MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_6)
#define SVN_DEPRECATED
#endif

#import <svn_client.h>
#import <svn_config.h>
#import <svn_time.h>

#import "SVNClient.h"

#define REPORT_SVN_ERROR(e) if((e) && _errorReporting) _ReportError(__FUNCTION__, e)

/* Defined in svn_auth.h */
extern void svn_auth_get_keychain_simple_provider(svn_auth_provider_object_t **provider, apr_pool_t *pool);

static const char _svnStatus[] = {'_', ' ', '?', ' ', 'A', '!', 'D', 'R', 'M', 'U', 'C', 'I', '~', 'X', '!'};
static BOOL _errorReporting = YES;

static void _ReportError(const char* function, svn_error_t* error)
{
	char					buffer[1024];
	
	printf("SVN error in %s: \"%s\"\n", function, (error->message ? error->message : svn_strerror(error->apr_err, buffer, 1024)));
}

static svn_client_ctx_t* _CreateSVNClientContext(apr_pool_t* pool)
{
	svn_client_ctx_t*			context;
	svn_auth_baton_t*			auth_baton;
	svn_auth_provider_object_t*	provider;
	apr_array_header_t*			providers;
	
	svn_client_create_context(&context, pool);
	
	svn_config_ensure(NULL, pool);
	svn_config_get_config(&context->config, NULL, pool);
	
	providers = apr_array_make(pool, 10, sizeof(svn_auth_provider_object_t*));
	svn_auth_get_username_provider(&provider, pool);
	*(svn_auth_provider_object_t**)apr_array_push (providers) = provider;
	svn_auth_get_keychain_simple_provider(&provider, pool);
	*(svn_auth_provider_object_t**)apr_array_push (providers) = provider;
	svn_auth_get_ssl_server_trust_file_provider(&provider, pool);
	*(svn_auth_provider_object_t**)apr_array_push (providers) = provider;
	svn_auth_get_ssl_client_cert_file_provider(&provider, pool);
	*(svn_auth_provider_object_t**)apr_array_push (providers) = provider;
	svn_auth_get_ssl_client_cert_pw_file_provider(&provider, pool);
	*(svn_auth_provider_object_t**)apr_array_push (providers) = provider;
	svn_auth_open(&auth_baton, providers, pool);
	//svn_auth_set_parameter(auth_baton, SVN_AUTH_PARAM_DEFAULT_USERNAME, ?);
	//svn_auth_set_parameter(auth_baton, SVN_AUTH_PARAM_DEFAULT_PASSWORD, ?);
	context->auth_baton = auth_baton;
	
	return context;
}

static svn_error_t* _svnInfoReceiver(void* baton, const char* path, const svn_info_t* info, apr_pool_t* pool)
{
	NSMutableDictionary*	dictionary = baton;
	
	[dictionary setValue:[NSString stringWithUTF8String:path] forKey:@"Path"];
	[dictionary setValue:[NSString stringWithUTF8String:info->URL] forKey:@"URL"];
	[dictionary setValue:[NSString stringWithUTF8String:info->repos_root_URL] forKey:@"Repository Root"];
	[dictionary setValue:[NSString stringWithUTF8String:info->repos_UUID] forKey:@"Repository UUID"];
	[dictionary setValue:[NSNumber numberWithInt:info->rev] forKey:@"Revision"];
	[dictionary setValue:[NSNumber numberWithInt:info->last_changed_rev] forKey:@"Last Changed Rev"];
	[dictionary setValue:[NSString stringWithUTF8String:info->last_changed_author] forKey:@"Last Changed Author"];
	[dictionary setValue:[NSString stringWithUTF8String:svn_time_to_human_cstring(info->last_changed_date, pool)] forKey:@"Last Changed Date"];
	
	return NULL;
}

static void _svnStatusFunction(void* baton, const char* path, svn_wc_status2_t* status)
{
	NSString*				basePath = ((void**)baton)[0];
	NSMutableDictionary*	dictionary = ((void**)baton)[1];
	
	basePath = [[NSString stringWithUTF8String:path] substringFromIndex:[basePath length]];
	if(![basePath length])
	basePath = @".";
	
	[dictionary setValue:[NSString stringWithFormat:@"%c%c   ", _svnStatus[status->text_status], _svnStatus[status->prop_status]] forKey:basePath];
}

static svn_error_t* _svnGetLogMessage(const char** log_msg, const char** tmp_file, const apr_array_header_t* commit_items, void* baton, apr_pool_t* pool)
{
	*log_msg = baton;
	*tmp_file = NULL;
	
	return NULL;
}

static void _svnAddFunction(void* baton, const char* path, svn_wc_status2_t* status)
{
	if(status->text_status != svn_wc_status_unversioned)
	*((const char**)baton) = NULL;
}

@implementation SVNClient

+ (void) initialize
{
	if(self == [SVNClient class])
	apr_initialize();
}

+ (void) setErrorReportingEnabled:(BOOL)flag
{
	_errorReporting = flag;
}

+ (BOOL) importPath:(NSString*)path toURL:(NSString*)url withMessage:(NSString*)message
{
	svn_error_t*			error;
	apr_pool_t*				pool;
	svn_client_ctx_t*		context;
	svn_commit_info_t*		result;
	
	if(![url length] || ![url length] || ![path length])
	return 0;
	
	apr_pool_create(&pool, NULL);
	context = _CreateSVNClientContext(pool);
	context->log_msg_func2 = _svnGetLogMessage;
	context->log_msg_baton2 = (void*)[message UTF8String];
	error = svn_client_import2(&result, [path UTF8String], [url UTF8String], FALSE, FALSE, context, pool);
	context->log_msg_func2 = NULL;
	context->log_msg_baton2 = NULL;
	REPORT_SVN_ERROR(error);
	apr_pool_destroy(pool);
	
	return (error ? NO : YES);
}

+ (NSUInteger) checkOutURL:(NSString*)url toPath:(NSString*)path revision:(NSUInteger)revision recursive:(BOOL)recursive ignoreExternals:(BOOL)ignore
{
	svn_opt_revision_t		pegRevision = {svn_opt_revision_unspecified};
	svn_opt_revision_t		checkOutRevision;
	svn_error_t*			error;
	svn_revnum_t			revisionNum;
	apr_pool_t*				pool;
	svn_client_ctx_t*		context;
	
	if(![url length] || ![path length])
	return 0;
	
	if(revision) {
		checkOutRevision.kind = svn_opt_revision_number;
		checkOutRevision.value.number = revision;
	}
	else
	checkOutRevision.kind = svn_opt_revision_head;
	
	apr_pool_create(&pool, NULL);
	context = _CreateSVNClientContext(pool);
	error = svn_client_checkout2(&revisionNum, [url UTF8String], [path UTF8String], &pegRevision, &checkOutRevision, recursive, ignore, context, pool);
	REPORT_SVN_ERROR(error);
	apr_pool_destroy(pool);
	
	return (error ? 0 : revisionNum);
}

+ (NSUInteger) exportURL:(NSString*)url toPath:(NSString*)path revision:(NSUInteger)revision recursive:(BOOL)recursive ignoreExternals:(BOOL)ignore
{
	svn_opt_revision_t		pegRevision = {svn_opt_revision_unspecified};
	svn_opt_revision_t		exportRevision;
	svn_error_t*			error;
	svn_revnum_t			revisionNum;
	apr_pool_t*				pool;
	svn_client_ctx_t*		context;
	
	if(![url length] || ![path length])
	return 0;
	
	if(revision) {
		exportRevision.kind = svn_opt_revision_number;
		exportRevision.value.number = revision;
	}
	else
	exportRevision.kind = svn_opt_revision_head;
	
	apr_pool_create(&pool, NULL);
	context = _CreateSVNClientContext(pool);
	error = svn_client_export3(&revisionNum, [url UTF8String], [path UTF8String], &pegRevision, &exportRevision, TRUE, ignore, recursive, NULL, context, pool);
	REPORT_SVN_ERROR(error);
	apr_pool_destroy(pool);
	
	return (error ? 0 : revisionNum);
}

+ (BOOL) copyURL:(NSString*)sourceURL revision:(NSUInteger)revision toURL:(NSString*)destinationURL withMessage:(NSString*)message
{
	svn_opt_revision_t		copyRevision;
	svn_error_t*			error;
	svn_commit_info_t*		result;
	apr_pool_t*				pool;
	svn_client_ctx_t*		context;
	
	if(![sourceURL length] || ![destinationURL length] || ![message length])
	return NO;
	
	if(revision) {
		copyRevision.kind = svn_opt_revision_number;
		copyRevision.value.number = revision;
	}
	else
	copyRevision.kind = svn_opt_revision_head;
	
	apr_pool_create(&pool, NULL);
	context = _CreateSVNClientContext(pool);
	((svn_client_ctx_t*)context)->log_msg_func2 = _svnGetLogMessage;
	((svn_client_ctx_t*)context)->log_msg_baton2 = (void*)[message UTF8String];
	error = svn_client_copy3(&result, [sourceURL UTF8String], &copyRevision, [destinationURL UTF8String], context, pool);
	((svn_client_ctx_t*)context)->log_msg_func2 = NULL;
	((svn_client_ctx_t*)context)->log_msg_baton2 = NULL;
	REPORT_SVN_ERROR(error);
	apr_pool_destroy(pool);
	
	return (error ? NO : YES);
}

+ (BOOL) removeURL:(NSString*)url withMessage:(NSString*)message
{
	apr_array_header_t*		targets;
	svn_error_t*			error;
	svn_commit_info_t*		result;
	apr_pool_t*				pool;
	svn_client_ctx_t*		context;
	
	if(![url length] || ![message length])
	return NO;
	
	apr_pool_create(&pool, NULL);
	context = _CreateSVNClientContext(pool);
	
	targets = apr_array_make(pool, 1, sizeof(const char*));
	(*((const char**)apr_array_push(targets))) = [url UTF8String];
	((svn_client_ctx_t*)context)->log_msg_func2 = _svnGetLogMessage;
	((svn_client_ctx_t*)context)->log_msg_baton2 = (void*)[message UTF8String];
	error = svn_client_delete2(&result, targets, TRUE, context, pool);
	((svn_client_ctx_t*)context)->log_msg_func2 = NULL;
	((svn_client_ctx_t*)context)->log_msg_baton2 = NULL;
	REPORT_SVN_ERROR(error);
	apr_pool_destroy(pool);
	
	return (error ? NO : YES);
}

+ (BOOL) createDirectoryAtURL:(NSString*)url withMessage:(NSString*)message
{
	apr_array_header_t*		targets;
	svn_error_t*			error;
	svn_commit_info_t*		result;
	apr_pool_t*				pool;
	svn_client_ctx_t*		context;
	
	if(![url length] || ![message length])
	return NO;
	
	apr_pool_create(&pool, NULL);
	context = _CreateSVNClientContext(pool);
	
	targets = apr_array_make(pool, 1, sizeof(const char*));
	(*((const char**)apr_array_push(targets))) = [url UTF8String];
	((svn_client_ctx_t*)context)->log_msg_func2 = _svnGetLogMessage;
	((svn_client_ctx_t*)context)->log_msg_baton2 = (void*)[message UTF8String];
	error = svn_client_mkdir2(&result, targets, context, pool);
	((svn_client_ctx_t*)context)->log_msg_func2 = NULL;
	((svn_client_ctx_t*)context)->log_msg_baton2 = NULL;
	REPORT_SVN_ERROR(error);
	apr_pool_destroy(pool);
	
	return (error ? NO : YES);
}

+ (NSDictionary*) infoForURL:(NSString*)url
{
	NSMutableDictionary*	dictionary = [NSMutableDictionary dictionary];
	svn_opt_revision_t		pegRevision = {svn_opt_revision_unspecified};
	svn_opt_revision_t		revision = {svn_opt_revision_head};
	svn_error_t*			error;
	apr_pool_t*				pool;
	svn_client_ctx_t*		context;
	
	if(![url length])
	return nil;
	
	apr_pool_create(&pool, NULL);
	context = _CreateSVNClientContext(pool);
	error = svn_client_info([url UTF8String], &pegRevision, &revision, &_svnInfoReceiver, dictionary, FALSE, context, pool);
	REPORT_SVN_ERROR(error);
	apr_pool_destroy(pool);
	
	return (error ? nil : dictionary);
}

+ (NSDictionary*) infoForPath:(NSString*)path
{
	NSMutableDictionary*	dictionary = [NSMutableDictionary dictionary];
	svn_opt_revision_t		pegRevision = {svn_opt_revision_unspecified};
	svn_opt_revision_t		revision = {svn_opt_revision_unspecified};
	svn_error_t*			error;
	apr_pool_t*				pool;
	svn_client_ctx_t*		context;
	
	if(![path length])
	return nil;
	
	apr_pool_create(&pool, NULL);
	context = _CreateSVNClientContext(pool);
	error = svn_client_info([path UTF8String], &pegRevision, &revision, &_svnInfoReceiver, dictionary, FALSE, context, pool);
	REPORT_SVN_ERROR(error);
	apr_pool_destroy(pool);
	
	return (error ? nil : dictionary);
}

- (id) initWithRepositoryPath:(NSString*)directoryPath
{
	if([directoryPath hasSuffix:@"/"])
	directoryPath = [directoryPath substringToIndex:([directoryPath length] - 1)];
	
	if((self = [super init])) {
		_path = [directoryPath copy];
		apr_pool_create((apr_pool_t**)&_masterPool, NULL);
		_svnContext = _CreateSVNClientContext(_masterPool);
		apr_pool_create((apr_pool_t**)&_localPool, _masterPool);
	}
	
	return self;
}

- (void) _cleanUp_SVNClient
{
	if(_localPool)
	apr_pool_destroy(_localPool);
	if(_masterPool)
	apr_pool_destroy(_masterPool);
}

- (void) finalize
{
	[self _cleanUp_SVNClient];
	
	[super finalize];
}

- (void) dealloc
{
	[self _cleanUp_SVNClient];
	
	[_path release];
	
	[super dealloc];
}

- (const char*) _makeSVNPath:(NSString*)path
{
	if([path isEqualToString:@"."])
	return [_path UTF8String];
	
	if([path hasSuffix:@"/"])
	path = [path substringToIndex:([path length] - 1)];
	
	return [[_path stringByAppendingPathComponent:path] UTF8String];
}

- (NSDictionary*) infoForPath:(NSString*)path
{
	NSMutableDictionary*	dictionary = [NSMutableDictionary dictionary];
	svn_opt_revision_t		pegRevision = {svn_opt_revision_unspecified};
	svn_opt_revision_t		revision = {svn_opt_revision_unspecified};
	svn_error_t*			error;
	
	if(![path length])
	return nil;
	
	error = svn_client_info([self _makeSVNPath:path], &pegRevision, &revision, &_svnInfoReceiver, dictionary, FALSE, _svnContext, _localPool);
	REPORT_SVN_ERROR(error);
	apr_pool_clear(_localPool);
	
	[dictionary setValue:path forKey:@"Path"]; //HACK: Fix path
	
	return (error ? nil : dictionary);
}

- (NSDictionary*) statusForPath:(NSString*)path
{
	NSMutableDictionary*	dictionary = [NSMutableDictionary dictionary];
	svn_opt_revision_t		revision = {svn_opt_revision_unspecified};
	void*					baton[2];
	svn_error_t*			error;
	const char*				statusPath;
	
	if(![path length])
	return nil;
	
	statusPath = [self _makeSVNPath:path];
	baton[0] = [NSString stringWithUTF8String:statusPath];
	baton[1] = dictionary;
	error = svn_client_status2(NULL, statusPath, &revision, _svnStatusFunction, baton, TRUE, FALSE, FALSE, FALSE, FALSE, _svnContext, _localPool);
	REPORT_SVN_ERROR(error);
	apr_pool_clear(_localPool);
	
	return (error ? nil : dictionary);
}

- (BOOL) cleanupPath:(NSString*)path
{
	svn_error_t*			error;
	
	if(![path length])
	return NO;
	
	error = svn_client_cleanup([self _makeSVNPath:path], _svnContext, _localPool);
	REPORT_SVN_ERROR(error);
	apr_pool_clear(_localPool);
	
	return (error ? NO : YES);
}

- (NSUInteger) updatePath:(NSString*)path revision:(NSUInteger)revision
{
	svn_opt_revision_t		updateRevision;
	svn_error_t*			error;
	apr_array_header_t*		paths;
	apr_array_header_t*		result;
	
	if(![path length])
	return 0;
	
	paths = apr_array_make(_localPool, 1, sizeof(const char*));
	(*((const char**)apr_array_push(paths))) = [self _makeSVNPath:path];
	
	if(revision) {
		updateRevision.kind = svn_opt_revision_number;
		updateRevision.value.number = revision;
	}
	else
	updateRevision.kind = svn_opt_revision_head;
	
	error = svn_client_update2(&result, paths, &updateRevision, TRUE, FALSE, _svnContext, _localPool);
	REPORT_SVN_ERROR(error);
	
	if((error == NULL) && (result->nelts > 0))
	revision = ((svn_revnum_t*)result->elts)[0];
	else
	revision = 0;
	
	apr_pool_clear(_localPool);
	
	return revision;
}

- (BOOL) createDirectory:(NSString*)name atPath:(NSString*)path
{
	NSFileManager*			manager = [NSFileManager defaultManager];
	NSString*				directoryPath = [[_path stringByAppendingPathComponent:path] stringByAppendingPathComponent:name];
	svn_error_t*			error;
	
	if(![name length] || ![path length])
	return NO;
	
	if(![manager createDirectoryAtPath:directoryPath withIntermediateDirectories:NO attributes:nil error:NULL]) {
		printf("SVNClient: Failed creating directory at \"%s\"\n", [directoryPath UTF8String]);
		return NO;
	}
	
	error = svn_client_add3([self _makeSVNPath:[path stringByAppendingPathComponent:name]], FALSE, FALSE, FALSE, _svnContext, _localPool);
	REPORT_SVN_ERROR(error);
	apr_pool_clear(_localPool);
	
	if(error)
	[manager removeItemAtPath:directoryPath error:NULL];
	
	return (error ? NO : YES);
}

- (BOOL) movePath:(NSString*)sourcePath toPath:(NSString*)destinationPath
{
	svn_error_t*			error;
	svn_commit_info_t*		result;
	
	if(![sourcePath length] || ![destinationPath length])
	return NO;
	
	error = svn_client_move4(&result, [self _makeSVNPath:sourcePath], [self _makeSVNPath:destinationPath], TRUE, _svnContext, _localPool);
	REPORT_SVN_ERROR(error);
	apr_pool_clear(_localPool);
	
	return (error ? NO : YES);
}

- (BOOL) copyPath:(NSString*)sourcePath toPath:(NSString*)destinationPath
{
	svn_opt_revision_t		revision = {svn_opt_revision_working};
	svn_error_t*			error;
	svn_commit_info_t*		result;
	
	if(![sourcePath length] || ![destinationPath length])
	return NO;
	
	error = svn_client_copy3(&result, [self _makeSVNPath:sourcePath], &revision, [self _makeSVNPath:destinationPath], _svnContext, _localPool);
	REPORT_SVN_ERROR(error);
	apr_pool_clear(_localPool);
	
	return (error ? NO : YES);
}

- (BOOL) addPath:(NSString*)path
{
	const char*				svnPath = [self _makeSVNPath:path];
	svn_opt_revision_t		revision = {svn_opt_revision_unspecified};
	svn_error_t*			error;
	
	if(![path length])
	return NO;
	
	error = svn_client_status2(NULL, svnPath, &revision, _svnAddFunction, &svnPath, FALSE, TRUE, FALSE, FALSE, TRUE, _svnContext, _localPool);
	REPORT_SVN_ERROR(error);
	if((error == NULL) && svnPath) {
		error = svn_client_add3(svnPath, TRUE, FALSE, FALSE, _svnContext, _localPool);
		REPORT_SVN_ERROR(error);
	}
	apr_pool_clear(_localPool);
	
	return (error ? NO : YES);
}

- (BOOL) removePath:(NSString*)path
{
	apr_array_header_t*		paths;
	svn_error_t*			error;
	svn_commit_info_t*		result;
	
	if(![path length])
	return NO;
	
	paths = apr_array_make(_localPool, 1, sizeof(const char*));
	(*((const char**)apr_array_push(paths))) = [self _makeSVNPath:path];
	
	error = svn_client_delete2(&result, paths, TRUE, _svnContext, _localPool);
	REPORT_SVN_ERROR(error);
	apr_pool_clear(_localPool);
	
	return (error ? NO : YES);
}

- (BOOL) commitPaths:(NSArray*)paths withMessage:(NSString*)message
{
	NSUInteger				count,
							i;
	apr_array_header_t*		targets;
	svn_error_t*			error;
	svn_commit_info_t*		result;
	
	if(![paths count] || ![message length])
	return NO;
	
	targets = apr_array_make(_localPool, [paths count], sizeof(const char*));
	for(i = 0, count = [paths count]; i < count; ++i)
	(*((const char**)apr_array_push(targets))) = [self _makeSVNPath:[paths objectAtIndex:i]];
	
	((svn_client_ctx_t*)_svnContext)->log_msg_func2 = _svnGetLogMessage;
	((svn_client_ctx_t*)_svnContext)->log_msg_baton2 = (void*)[message UTF8String];
	error = svn_client_commit3(&result, targets, TRUE, TRUE, _svnContext, _localPool);
	((svn_client_ctx_t*)_svnContext)->log_msg_func2 = NULL;
	((svn_client_ctx_t*)_svnContext)->log_msg_baton2 = NULL;
	REPORT_SVN_ERROR(error);
	apr_pool_clear(_localPool);
	
	return (error ? NO : YES);
}

- (BOOL) revertPath:(NSString*)path
{
	apr_array_header_t*		paths;
	svn_error_t*			error;
	
	if(![path length])
	return NO;
	
	paths = apr_array_make(_localPool, 1, sizeof(const char*));
	(*((const char**)apr_array_push(paths))) = [self _makeSVNPath:path];
	
	error = svn_client_revert(paths, TRUE, _svnContext, _localPool);
	REPORT_SVN_ERROR(error);
	apr_pool_clear(_localPool);
	
	return (error ? NO : YES);
}

- (BOOL) setProperty:(NSString*)property forPath:(NSString*)path key:(NSString*)key
{
	svn_error_t*			error;
	
	if(![path length] || ![property length] || ![key length])
	return NO;
	
	error = svn_client_propset2([key UTF8String], svn_string_create([property UTF8String], _localPool), [self _makeSVNPath:path], FALSE, FALSE, _svnContext, _localPool);
	REPORT_SVN_ERROR(error);
	apr_pool_clear(_localPool);
	
	return (error ? NO : YES);
}

- (BOOL) removePropertyForPath:(NSString*)path key:(NSString*)key
{
	svn_error_t*			error;
	
	if(![path length] || ![key length])
	return NO;
	
	error = svn_client_propset2([key UTF8String], NULL, [self _makeSVNPath:path], FALSE, FALSE, _svnContext, _localPool);
	REPORT_SVN_ERROR(error);
	apr_pool_clear(_localPool);
	
	return (error ? NO : YES);
}

- (NSString*) propertyForPath:(NSString*)path key:(NSString*)key
{
	svn_opt_revision_t		pegRevision = {svn_opt_revision_unspecified};
	svn_opt_revision_t		revision = {svn_opt_revision_unspecified};
	svn_error_t*			error;
	apr_hash_t*				result;
	const char*				target;
	svn_string_t*			value;
	NSString*				string;
	
	if(![path length] || ![key length])
	return nil;
	
	target = [self _makeSVNPath:path];
	error = svn_client_propget2(&result, [key UTF8String], target, &pegRevision, &revision, FALSE, _svnContext, _localPool);
	REPORT_SVN_ERROR(error);
	
	if((error == NULL) && (value = apr_hash_get(result, target, APR_HASH_KEY_STRING)))
	string = [[[NSString alloc] initWithBytes:value->data length:value->len encoding:NSUTF8StringEncoding] autorelease];
	else
	string = nil;
	
	apr_pool_clear(_localPool);
	
	return string;
}

- (NSDictionary*) propertiesForPath:(NSString*)path
{
	NSMutableDictionary*			dictionary = [NSMutableDictionary dictionary];
	svn_opt_revision_t				pegRevision = {svn_opt_revision_unspecified};
	svn_opt_revision_t				revision = {svn_opt_revision_unspecified};
	svn_error_t*					error;
	apr_array_header_t*				result;
	svn_client_proplist_item_t*		item;
	apr_hash_index_t*				index;
	
	const char*						name;
	svn_string_t*					value;
	NSString*						string;
	
	if(![path length])
	return nil;
	
	error = svn_client_proplist2(&result, [self _makeSVNPath:path], &pegRevision, &revision, FALSE, _svnContext, _localPool);
	REPORT_SVN_ERROR(error);
	
	if((error == NULL) && (result->nelts > 0)) {
		item = ((svn_client_proplist_item_t**)result->elts)[0];
		for(index = apr_hash_first(_localPool, item->prop_hash); index; index = apr_hash_next(index)) {
			apr_hash_this(index, (const void**)&name, NULL, (void**)&value);
			string = [[NSString alloc] initWithBytes:value->data length:value->len encoding:NSUTF8StringEncoding];
			[dictionary setValue:string forKey:[NSString stringWithUTF8String:name]];
			[string release];
		}
	}
	
	apr_pool_clear(_localPool);
	
	return (error ? nil : dictionary);
}

+ (NSUInteger) checkOutURL:(NSString*)url toPath:(NSString*)path
{
	return [self checkOutURL:url toPath:path revision:0 recursive:YES ignoreExternals:NO];
}

+ (NSUInteger) exportURL:(NSString*)url toPath:(NSString*)path
{
	return [self exportURL:url toPath:path revision:0 recursive:YES ignoreExternals:NO];
}

+ (BOOL) copyURL:(NSString*)sourceURL toURL:(NSString*)destinationURL withMessage:(NSString*)message
{
	return [self copyURL:sourceURL revision:0 toURL:destinationURL withMessage:message];
}

- (NSUInteger) updatePath:(NSString*)path
{
	return [self updatePath:path revision:0];
}

- (BOOL) commitPath:(NSString*)path withMessage:(NSString*)message
{
	if(![path length])
	return NO;
	
	return [self commitPaths:[NSArray arrayWithObject:path] withMessage:message];
}

@end
