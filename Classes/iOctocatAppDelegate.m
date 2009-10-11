#import "iOctocatAppDelegate.h"
#import "MyFeedsController.h"


@interface iOctocatAppDelegate ()
- (void)postLaunch;
- (void)presentLogin;
- (void)dismissLogin;
- (void)showAuthenticationSheet;
- (void)dismissAuthenticationSheet;
- (void)authenticate;
- (void)proceedAfterAuthentication;
- (void)clearAvatarCache;
- (void)displayLaunchMessage;
@end


@implementation iOctocatAppDelegate

@synthesize users, lastLaunchDate;

- (void)applicationDidFinishLaunching:(UIApplication *)application {
	self.users = [NSMutableDictionary dictionary];
	[window addSubview:tabBarController.view];
	launchDefault = YES;
	[self performSelector:@selector(postLaunch) withObject:nil afterDelay:0.0];
}

- (void)postLaunch {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	// Launch date
	NSDate *lastLaunch = (NSDate *)[defaults valueForKey:kLaunchDateDefaultsKey];
	NSDate *nowDate = [NSDate date];
	if (!lastLaunch) lastLaunch = nowDate;
	self.lastLaunchDate = lastLaunch;
	[defaults setValue:nowDate forKey:kLaunchDateDefaultsKey];
	// Avatar cache
	if ([defaults boolForKey:kClearAvatarCacheDefaultsKey]) {
		[self clearAvatarCache];
		[defaults setValue:NO forKey:kClearAvatarCacheDefaultsKey];
	}
	[defaults synchronize];
	if (launchDefault) {
		[self displayLaunchMessage];
		[self authenticate];
	}
}

- (void)dealloc {
	[tabBarController release];
	[feedController release];
	[authView release];
	[authSheet release];
	[window release];
	[users release];
	[super dealloc];
}

- (UIView *)currentView {
    return tabBarController.modalViewController ? tabBarController.modalViewController.view : tabBarController.view;
}

- (GHUser *)currentUser {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSString *login = [defaults valueForKey:kUsernameDefaultsKey];
	return (!login || [login isEqualToString:@""]) ? nil : [self userWithLogin:login];
}

- (GHUser *)userWithLogin:(NSString *)theUsername {
	GHUser *user = [users objectForKey:theUsername];
	if (user == nil) {
		user = [[[GHUser alloc] initWithLogin:theUsername] autorelease];
		[users setObject:user forKey:theUsername];
	}
	return user;
}

- (void)clearAvatarCache {
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	NSString *documentsPath = [paths objectAtIndex:0];
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSArray *documents = [fileManager contentsOfDirectoryAtPath:documentsPath error:NULL];
	for (NSString *path in documents) {
		if ([path hasSuffix:@".png"]) {
			NSString *imagePath = [documentsPath stringByAppendingPathComponent:path];
			[fileManager removeItemAtPath:imagePath error:NULL];
		}
	}
}

- (void)displayLaunchMessage {
	NSURL *launchMessageURL = [NSURL URLWithString:kLaunchMessageFileURL];
	NSString *launchMessage = [NSString stringWithContentsOfURL:launchMessageURL];
	if (launchMessage && ![launchMessage isEqualToString:@""]) {
		NSArray *launchMessageComponents = [launchMessage componentsSeparatedByString:@"|"];
		NSInteger number = [[launchMessageComponents objectAtIndex:0] integerValue];
		NSString *title = [launchMessageComponents objectAtIndex:1];
		NSString *message = [launchMessageComponents objectAtIndex:2];
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		NSInteger oldNumber = (NSInteger)[defaults integerForKey:kLaunchMessageNumberDefaultsKey];
		if (number > oldNumber) {
			[defaults setValue:[NSString stringWithFormat:@"%d", number] forKey:kLaunchMessageNumberDefaultsKey];
			[defaults synchronize];
			UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title message:message delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
			[alert show];
			[alert release];
		}
	}
}

#pragma mark -
#pragma mark Authentication

// Use this to add credentials (for instance via email) by opening a link:
// <githubauth://LOGIN:TOKEN@github.com>
- (BOOL)application:(UIApplication *)application handleOpenURL:(NSURL *)url {
	if (!url || [[url user] isEqualToString:@""] || [[url password] isEqualToString:@""]) return NO;
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setValue:[url user] forKey:kUsernameDefaultsKey];
	[defaults setValue:[url password] forKey:kTokenDefaultsKey];
	[defaults synchronize];
	// Inform the user
	NSString *message = [NSString stringWithFormat:@"Username: %@\nAPI Token: %@", [defaults valueForKey:kUsernameDefaultsKey], [defaults valueForKey:kTokenDefaultsKey]];
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"New credentials" message:message delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
	[alert show];
	[alert release];
	return YES;
}

- (void)authenticate {
	if (self.currentUser.isAuthenticated) return;
	if (!self.currentUser) {
		[self presentLogin];
	} else {
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		NSString *token = [defaults valueForKey:kTokenDefaultsKey];
		[self.currentUser addObserver:self forKeyPath:kResourceLoadingStatusKeyPath options:NSKeyValueObservingOptionNew context:nil];
		[self.currentUser authenticateWithToken:token];
	}
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
	if (self.currentUser.isLoading) {
		[self showAuthenticationSheet];
	} else if (self.currentUser.isLoaded) {
		[self dismissAuthenticationSheet];
		[self.currentUser removeObserver:self forKeyPath:kResourceLoadingStatusKeyPath];
		if (self.currentUser.isAuthenticated) {
			[self proceedAfterAuthentication];
		} else {
			[self presentLogin];
			[self.loginController failWithMessage:@"Please ensure that you are connected to the internet and that your login and API token are correct"];
		}
	}
}

- (LoginController *)loginController {
	return (LoginController *)tabBarController.modalViewController ;
}

- (void)presentLogin {
	if (self.loginController) return;
	LoginController *loginController = [[LoginController alloc] initWithTarget:self andSelector:@selector(authenticate)];
	[tabBarController presentModalViewController:loginController animated:YES];
	[loginController release];
}

- (void)dismissLogin {
	if (self.loginController) [tabBarController dismissModalViewControllerAnimated:YES];
}

- (void)showAuthenticationSheet {
	authSheet = [[UIActionSheet alloc] initWithTitle:@"\n\n" delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
	UIView *currentView = tabBarController.modalViewController ? tabBarController.modalViewController.view : tabBarController.view;
	[authSheet addSubview:authView];
	[authSheet showInView:currentView];
	[authSheet release];
}

- (void)dismissAuthenticationSheet {
	[authSheet dismissWithClickedButtonIndex:0 animated:YES];
}

- (void)proceedAfterAuthentication {
	[self dismissLogin];
	[feedController setupFeeds];
}

@end
