#import <Foundation/Foundation.h>
#import <Sparkle/Sparkle.h>

static SPUStandardUpdaterController *hwCalendarUpdaterController;

bool hw_calendar_updater_initialize(void) {
    if (hwCalendarUpdaterController != nil) {
        return true;
    }

    [NSUserDefaults.standardUserDefaults registerDefaults:@{
        @"SUEnableAutomaticChecks": @YES,
        @"SUScheduledCheckInterval": @86400,
        @"SUAutomaticallyUpdate": @NO,
        @"SUAllowsAutomaticUpdates": @NO,
    }];

    hwCalendarUpdaterController = [[SPUStandardUpdaterController alloc]
        initWithStartingUpdater:YES
        updaterDelegate:nil
        userDriverDelegate:nil];
    return hwCalendarUpdaterController != nil;
}

bool hw_calendar_updater_check(void) {
    if (hwCalendarUpdaterController == nil &&
        !hw_calendar_updater_initialize()) {
        return false;
    }
    [hwCalendarUpdaterController checkForUpdates:nil];
    return true;
}

void hw_calendar_updater_shutdown(void) {
    hwCalendarUpdaterController = nil;
}

const char *hw_calendar_updater_version(void) {
    NSString *version = [NSBundle.mainBundle
        objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    return version != nil ? version.UTF8String : NULL;
}

const char *hw_calendar_updater_build(void) {
    NSString *build = [NSBundle.mainBundle
        objectForInfoDictionaryKey:@"CFBundleVersion"];
    return build != nil ? build.UTF8String : NULL;
}
