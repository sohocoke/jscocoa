
#import "Httpd.h"
//#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

#include "JavascriptCore-dlsym.h"
#include "JSCocoaController.h"


@implementation Httpd
-(id)initWithPort:(int)n {
	if (self = [super init]) {
		int socketInitResult = [self _init_socket:n];
		if (socketInitResult != 0)
			[NSException raise:@"ServerStartupError" format:nil, nil];
	}

	return self;
}

-(void)dealloc {
	close(server_socket);
	[super dealloc];
}

-(int)_init_socket:(int)n {
    struct sockaddr_in addr;
		
	int sock = socket(AF_INET, SOCK_STREAM, 0) ;
	server_socket = sock;
	
	int namelen = sizeof(addr);
	
	if(sock  <= 0 ) {
		return 1;
	}
				memset(&addr, 0, sizeof(addr));
	addr.sin_len = namelen;
	addr.sin_family = AF_INET;
				addr.sin_addr.s_addr = htonl(INADDR_ANY);
				addr.sin_port = htons(n);
				
				// Allow the kernel to choose a random port number by passing in 0 for the port.
				if (bind(sock, (struct sockaddr *)&addr, namelen) < 0) {
					close (sock);
					return 1;
				}
				/*
				// Find out what port number was chosen.
				if (getsockname(sock, (struct sockaddr *)&serverAddress, &namelen) < 0) {
					close(sock);
					return 2;
				}
				*/
				// Once we're here, we know bind must have returned, so we can start the listen
				if( listen(sock, 1) ) {
					close(sock);
					return 3;
				}

	
	NSFileHandle* fh = [[NSFileHandle alloc] initWithFileDescriptor:sock
													 closeOnDealloc:YES
	];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(observe:)
												 name:NSFileHandleConnectionAcceptedNotification
											   object:fh];
	[fh acceptConnectionInBackgroundAndNotify];

	return 0;
}


-(void)observe:(NSNotification*)notification {
	NSLog(@"%@", notification);

		NSDictionary* info = [notification userInfo];
	NSFileHandle* fh = (NSFileHandle*)[info objectForKey:NSFileHandleNotificationFileHandleItem];
	
	NSData* data = [fh availableData];
	
	const char* p = (const char*)[data bytes];

	BOOL found = NO;

	if ( memcmp(p, "GET", 3) == 0) {
		p += 3;
		const char* start = ++p;
		while ( *p != ' ' )
			p++;
		int n = p - start;
		NSString* uri = [[NSString alloc] initWithBytes:start
			length:n encoding:NSASCIIStringEncoding];

		
		NSArray* path = [uri componentsSeparatedByString:@"/"];
		NSLog(@"get %@", path);

		if ( [[path objectAtIndex:1] isEqualToString:@"png"] ) {
			const char* addr = [[path objectAtIndex:2] cStringUsingEncoding:NSASCIIStringEncoding];
			void* p;
			sscanf(addr, "%08x", &p);

		
			id image = (id)p;
			if ( [image isKindOfClass:[UIImage class]]  ) {
				const char* header = "HTTP/1.0 200 OK\r\nContent-Type:image/png\r\n\r\n";
				NSMutableData* d = [NSMutableData dataWithBytes:header length:strlen(header)];
				[d appendData:UIImagePNGRepresentation(image)];
				[fh writeData:d];

				found = YES;
			}
		} else {

			const char* header = "HTTP/1.0 200 OK\r\n\r\n";

			const char* nl = "\n";
			NSMutableData* d = [NSMutableData dataWithBytes:header length:strlen(header)];

			NSString* htmlfile = [NSString stringWithFormat:@"%@/console.html",
				[[NSBundle mainBundle] bundlePath]];

			NSData* htmldata = [NSData dataWithContentsOfFile:htmlfile];

			[d appendBytes:[htmldata bytes] length:[htmldata length]];
			[d appendBytes:nl length:strlen(nl)];

			[fh writeData:d];

			found = YES;
		}

	} else 	if ( memcmp(p, "POST", 4) == 0) {
		//NSString* s = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
		const char* eoh = strstr(p, "\r\n\r\n");
		if ( eoh ) {
			eoh += 4;
			int n = [data length] - ( eoh - p);
			NSString *jscode = [[NSString alloc] initWithBytes:eoh
			length: n 
			encoding:NSASCIIStringEncoding];

			NSLog(@"jscode: %@", jscode);

			id c = [JSCocoaController sharedController];
			JSValueRef vcref = [c evalJSString:jscode];
			
			NSString* resultString;
			if (vcref) {
				JSStringRef resultStringJS = JSValueToStringCopy([c ctx], vcref, NULL);
				resultString = (NSString*)JSStringCopyCFString(kCFAllocatorDefault, resultStringJS);
				JSStringRelease(resultStringJS);
			} else {
				resultString = @"Error from evalJSString: nil vcref.";
			}
			
			const char* response = [resultString cStringUsingEncoding:NSASCIIStringEncoding];

			const char* header = "HTTP/1.0 200 OK\r\n\r\n";
			const char* nl = "\n";
			NSMutableData* d = [NSMutableData dataWithBytes:header length:strlen(header)];
			
			[d appendBytes:response length:strlen(response)];
			[d appendBytes:nl length:strlen(nl)];
			[fh writeData:d];

			[resultString autorelease];
			
			found = YES;
		}
	}

	if ( !found ) {
		const char* res = "HTTP/1.0 404 Not Found\r\n\r\n";
		NSData* response = [NSData dataWithBytes:res length:strlen(res)];
		[fh writeData:response];
//		[fh synchronizeFile];
//		[fh closeFile];
	}	

	[[notification object] acceptConnectionInBackgroundAndNotify];


}

@end
/*
cat ../console.html | perl -nle '/^\s*$/ or  s/\\/\\\\/g, s/"/\\"/g, print qq{"$_\\n"\\} ' >! html.h; echo  >> html.h
 */
