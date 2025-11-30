#import <AppKit/AppKit.h>

// --- Globals and Delegate ---
static id<NSUserNotificationCenterDelegate> notificationDelegate = nil;
static NSString *const URLActionKey = @"actionURL";

@interface NotificationDelegate : NSObject <NSUserNotificationCenterDelegate>
@end

@implementation NotificationDelegate

- (void)userNotificationCenter:(NSUserNotificationCenter *)center
       didActivateNotification:(NSUserNotification *)notification {
  NSString *urlString = notification.userInfo[URLActionKey];
  if (!urlString) {
    return;
  }

  NSURL *url = [NSURL URLWithString:urlString];
  if (url) {
    [[NSWorkspace sharedWorkspace] openURL:url];
  }
}

- (BOOL)userNotificationCenter:(NSUserNotificationCenter *)center
     shouldPresentNotification:(NSUserNotification *)notification {
  return YES;
}

@end

void dispatch_notification(const char *title, const char *body, const char *urlString) {
  @autoreleasepool {
    NSUserNotificationCenter *center = [NSUserNotificationCenter defaultUserNotificationCenter];

    if (notificationDelegate == nil) {
      NSApplication *app = [NSApplication sharedApplication];
      app.activationPolicy = NSApplicationActivationPolicyProhibited;
      notificationDelegate = [[NotificationDelegate alloc] init];
      center.delegate = notificationDelegate;
    }

    NSUserNotification *notification = [[NSUserNotification alloc] init];
    notification.title = @(title);
    notification.informativeText = @(body);
    notification.hasActionButton = (urlString != NULL);
    if (notification.hasActionButton) {
      notification.actionButtonTitle = @"Show me!";
      notification.userInfo = @{URLActionKey : @(urlString)};
    }

    [center deliverNotification:notification];
  }
}

void handle_events(void) {
  @autoreleasepool {
    NSApplication *app = [NSApplication sharedApplication];

    NSEvent *event = [app nextEventMatchingMask:NSEventMaskAny
                                      untilDate:[NSDate distantPast]
                                         inMode:NSDefaultRunLoopMode
                                        dequeue:YES];

    if (event) {
      [app sendEvent:event];
    }
  }
}
