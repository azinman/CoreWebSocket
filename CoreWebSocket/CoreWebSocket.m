//
//  CoreWebSocket.c
//  CoreWebSocketCore
//
//  Created by Mirek Rusin on 07/03/2011.
//  Copyright 2011 Inteliv Ltd. All rights reserved.
//

#include "CoreWebSocketLib.h"

#pragma mark Lifecycle

CoreWebSocketRef CoreWebSocketCreate(CFAllocatorRef allocator, CFStringRef host, UInt16 port, void *userInfo) {
  CoreWebSocketRef webSocket = CFAllocatorAllocate(allocator, sizeof(CoreWebSocket), 0);
  if (webSocket) {
    webSocket->allocator = allocator ? CFRetain(allocator) : NULL;
    webSocket->retainCount = 1;
    webSocket->userInfo = userInfo;

    webSocket->clientsLength = 1024;
    webSocket->clientsUsedLength = 0;
    if (NULL == (webSocket->clients = CFAllocatorAllocate(allocator, webSocket->clientsLength, 0))) {
      webSocket = CoreWebSocketRelease(webSocket);
      goto fin;
    }

    // Callbacks
    webSocket->callbacks.didAddClientCallback     = NULL;
    webSocket->callbacks.willRemoveClientCallback = NULL;
    webSocket->callbacks.didClientReadCallback    = NULL;

    // Setup the context;
    webSocket->context.copyDescription = NULL;
    webSocket->context.retain = NULL;
    webSocket->context.release = NULL;
    webSocket->context.version = 0;
    webSocket->context.info = webSocket;

    if (NULL == (webSocket->socket = CFSocketCreate(webSocket->allocator, PF_INET, SOCK_STREAM, IPPROTO_TCP, kCFSocketAcceptCallBack, __CoreWebSocketAcceptCallBack, &webSocket->context))) {
      webSocket = CoreWebSocketRelease(webSocket);
      goto fin;
    }

    // Re-use local addresses, if they're still in TIME_WAIT
    int yes = 1;
    setsockopt(CFSocketGetNative(webSocket->socket), SOL_SOCKET, SO_REUSEADDR, (void *)&yes, sizeof(yes));

    /* Set the port and address we want to listen on */
    memset(&webSocket->addr, 0, sizeof(webSocket->addr));
    webSocket->addr.sin_len = sizeof(webSocket->addr);
    webSocket->addr.sin_family = AF_INET;

    if (CFEqual(kCoreWebSocketHostAny, host)) {

      // Host is set to "0.0.0.0", set it to INADDR_ANY
      webSocket->addr.sin_addr.s_addr = htonl(INADDR_ANY);
    } else {

      // Set the host based on provided string. TODO: hostname resolution?
      CFIndex hostCStringLength = CFStringGetMaximumSizeForEncoding(CFStringGetLength(host), kCFStringEncodingASCII) + 1;
      char *hostCString = CFAllocatorAllocate(webSocket->allocator, hostCStringLength, 0);
      if (hostCString) {
        if (CFStringGetCString(host, hostCString, hostCStringLength, kCFStringEncodingASCII)) {
          inet_aton(hostCString, &webSocket->addr.sin_addr);
        } else {
          // TODO: Couldn't get CString
        }
        CFAllocatorDeallocate(webSocket->allocator, hostCString);
      } else {
        // TODO: Couldn't allocate buffer
      }
    }

    webSocket->addr.sin_port = htons(port);

    CFDataRef address = CFDataCreate(webSocket->allocator, (const void *)&webSocket->addr, sizeof(webSocket->addr));
    if (address) {
      if (CFSocketSetAddress(webSocket->socket, (CFDataRef)address) != kCFSocketSuccess) {
        webSocket = CoreWebSocketRelease(webSocket);
//        CFRelease(address); // TODO: is it retained by the function?
        goto fin;
      } else {
//        CFRelease(address); // TODO: is it retained bby the function
      }
    }

    // Create run loop source and add it to the current run loop
    CFRunLoopSourceRef source = CFSocketCreateRunLoopSource(webSocket->allocator, webSocket->socket, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopCommonModes);
    CFRelease(source);
  }
fin:
  return webSocket;
}

CoreWebSocketRef CoreWebSocketCreateWithUserInfo(CFAllocatorRef allocator, void *userInfo) {
  return CoreWebSocketCreate(allocator, kCoreWebSocketHostLoopBack, kCoreWebSocketPortAny, userInfo);
}

CoreWebSocketRef CoreWebSocketRetain(CoreWebSocketRef webSocket) {
  webSocket->retainCount++;
  return webSocket;
}

CoreWebSocketRef CoreWebSocketRelease(CoreWebSocketRef webSocket) {
  if (webSocket) {
    if (--webSocket->retainCount == 0) {
      CFAllocatorRef allocator = webSocket->allocator;

      if (webSocket->clients) {
        while (--webSocket->clientsUsedLength >= 0)
          CoreWebSocketClientRelease(webSocket->clients[webSocket->clientsUsedLength]);
        CFAllocatorDeallocate(allocator, webSocket->clients);
        webSocket->clients = NULL;
      }

      if (webSocket->socket) {
        CFSocketInvalidate(webSocket->socket);
        CFRelease(webSocket->socket);
        webSocket->socket = NULL;
      }

      CFAllocatorDeallocate(allocator, webSocket);
      webSocket = NULL;

      if (allocator)
        CFRelease(allocator);
    }
  }
  return webSocket;
}

UInt16 CoreWebSocketGetPort(CoreWebSocketRef webSocket) {
  UInt16 port = UINT16_MAX;
  if (webSocket && webSocket->socket) {
    struct sockaddr_in sockname;
    socklen_t sockname_len = sizeof(sockname);
    if (getsockname(CFSocketGetNative(webSocket->socket), (struct sockaddr *)&sockname, &sockname_len) < 0) {
      // Error
    } else {
      port = ntohs(sockname.sin_port);
      // host = inet_ntoa(sockname.sin_addr)
    }
  }
  return port;
}

void CoreWebSocketWriteWithString(CoreWebSocketRef webSocket, CFStringRef value) {
  if (webSocket) {
    for (CFIndex i = 0; i < webSocket->clientsUsedLength; i++) {
      CoreWebSocketWriteWithStringAndClientIndex(webSocket, value, i);
    }
  }
}

CFIndex CoreWebSocketWriteWithStringAndClientIndex(CoreWebSocketRef webSocket, CFStringRef value, CFIndex index) {
  CFIndex bytes = -1;
  if (webSocket) {
    if (value) {
      if (index < webSocket->clientsUsedLength) {
        bytes = CoreWebSocketClientWriteWithString(webSocket->clients[index], value);
      }
    }
  }
  return bytes;
}

#pragma mark Callbacks

void CoreWebSocketSetClientReadCallback(CoreWebSocketRef webSocket, CoreWebSocketDidClientReadCallback callback) {
  if (webSocket) {
    webSocket->callbacks.didClientReadCallback = callback;
  }
}

#pragma mark Internal, client management

CFIndex __CoreWebSocketAppendClient(CoreWebSocketRef webSocket, CoreWebSocketClientRef client) {
  CFIndex count = -1;
  if (webSocket && client) {
    webSocket->clients[webSocket->clientsUsedLength++] = CoreWebSocketClientRetain(client);
    count = webSocket->clientsUsedLength;
    if (webSocket->callbacks.didAddClientCallback)
      webSocket->callbacks.didAddClientCallback(webSocket, client);
  }
  return count;
}

CFIndex __CoreWebSocketRemoveClient(CoreWebSocketRef webSocket, CoreWebSocketClientRef client) {
  CFIndex count = -1;
  if (webSocket && client) {
    for (CFIndex i = 0; i < webSocket->clientsUsedLength; i++) {
      if (webSocket->clients[i] == client) {
        if (webSocket->callbacks.willRemoveClientCallback)
          webSocket->callbacks.willRemoveClientCallback(webSocket, client);
        webSocket->clients[i] = webSocket->clients[count = --webSocket->clientsUsedLength];
        CoreWebSocketClientRelease(client);
      }
    }
  }
  return count;
}

#pragma mark Callbacks

void __CoreWebSocketAcceptCallBack(CFSocketRef socket, CFSocketCallBackType type, CFDataRef address, const void *sock, void *info) {
  CoreWebSocketRef webSocket = (CoreWebSocketRef)info;
  CoreWebSocketClientRef client = CoreWebSocketClientCreate(webSocket, *(CFSocketNativeHandle *)sock);
  printf("adding %p client\n", client);
}
