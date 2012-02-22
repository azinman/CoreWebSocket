//
//  CoreWebSocketClient.h
//  CoreWebSocketCore
//
//  Created by Mirek Rusin on 07/03/2011.
//  Copyright 2011 Inteliv Ltd. All rights reserved.
//

#ifndef __CORE_WEB_SOCKET_CLIENT__
#define __CORE_WEB_SOCKET_CLIENT__ 1

#include "CoreWebSocket.h"
#include "cuEnc64.h"
#include <CommonCrypto/CommonDigest.h>

#pragma mark Lifecycle

CoreWebSocketClientRef CoreWebSocketClientCreate  (CoreWebSocketRef webSocket, CFSocketNativeHandle handle);
CoreWebSocketClientRef CoreWebSocketClientRetain  (CoreWebSocketClientRef client);
CoreWebSocketClientRef CoreWebSocketClientRelease (CoreWebSocketClientRef client);

#pragma mark Write

CFIndex CoreWebSocketClientWriteWithData   (CoreWebSocketClientRef client, CFDataRef value);
CFIndex CoreWebSocketClientWriteWithString (CoreWebSocketClientRef client, CFStringRef value);

#pragma mark Handshake (internal)

uint32_t  __CoreWebSocketGetMagicNumberWithKeyValueString         (CFStringRef string);
bool      __CoreWebSocketDataAppendMagickNumberWithKeyValueString (CFMutableDataRef data, CFStringRef string);
CFDataRef __CoreWebSocketCreateMD5Data                            (CFAllocatorRef allocator, CFDataRef value) CF_RETURNS_RETAINED;
CFDataRef __CoreWebSocketCreateSHA1DataWithData                   (CFAllocatorRef allocator, CFDataRef value) CF_RETURNS_RETAINED;
CFDataRef __CoreWebSocketCreateSHA1DataWithString                 (CFAllocatorRef allocator, CFStringRef value, CFStringEncoding encoding) CF_RETURNS_RETAINED;
bool      __CoreWebSocketClientReadHandShake                      (CoreWebSocketClientRef client);
bool      __CoreWebSocketClientWriteWithHTTPMessage               (CoreWebSocketClientRef client, CFHTTPMessageRef message);

#endif
