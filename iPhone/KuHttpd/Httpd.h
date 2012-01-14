
#import <Foundation/Foundation.h>


@interface Httpd : NSObject  {
	int server_socket;
}
-(id)initWithPort:(int)n ;
-(int)_init_socket:(int)n ;
-(void)observe:(NSNotification*)notification ;

@end

