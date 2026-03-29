// SpringBoardTweak.m - 完整修复版
@import UIKit;
@import UniformTypeIdentifiers;
#import "SpringBoardTweak.h"
#include <objc/runtime.h>
#include <objc/message.h>
#include <sys/stat.h>
#include <sys/fcntl.h>
#include <unistd.h>
#include <spawn.h>
#include <dlfcn.h>
#include <sys/wait.h>

#pragma mark - Status Bar Clock Tweak

static NSString *g_timeFormat = nil;
static NSString *g_dateFormat = nil;

static NSString *getTimeFormat(void) {
    return g_timeFormat ?: @"HH:mm";
}

static NSString *getDateFormat(void) {
    return g_dateFormat ?: @"E dd/MM/yyyy";
}

static void (*orig_applyStyleAttributes)(id self, SEL _cmd, id arg1);
static void (*orig_setText)(id self, SEL _cmd, NSString *text);

static void hook_applyStyleAttributes(id self, SEL _cmd, id arg1) {
    UILabel *label = (UILabel *)self;
    if (!(label.text != nil && [label.text containsString:@":"])) {
        orig_applyStyleAttributes(self, _cmd, arg1);
    }
}

static void hook_setText(id self, SEL _cmd, NSString *text) {
    if ([text containsString:@":"]) {
        UILabel *label = (UILabel *)self;
        @autoreleasepool {
            NSMutableAttributedString *finalString = [[NSMutableAttributedString alloc] init];

            NSString *timeFmt = getTimeFormat();
            NSString *dateFmt = getDateFormat();

            NSDateFormatter *formatter1 = [[NSDateFormatter alloc] init];
            [formatter1 setDateFormat:timeFmt];
            UIFont *font1 = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
            NSAttributedString *attrString1 = [[NSAttributedString alloc] initWithString:[formatter1 stringFromDate:[NSDate date]]
                                                                              attributes:@{NSFontAttributeName: font1}];

            [finalString appendAttributedString:attrString1];

            if (dateFmt.length > 0) {
                NSLocale *currentLocale = [NSLocale autoupdatingCurrentLocale];
                NSDateFormatter *formatter2 = [[NSDateFormatter alloc] init];
                [formatter2 setDateFormat:dateFmt];
                [formatter2 setLocale:currentLocale];
                UIFont *font2 = [UIFont systemFontOfSize:8.0 weight:UIFontWeightRegular];
                NSAttributedString *attrString2 = [[NSAttributedString alloc] initWithString:[formatter2 stringFromDate:[NSDate date]]
                                                                                  attributes:@{NSFontAttributeName: font2}];

                [finalString appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];
                [finalString appendAttributedString:attrString2];
                label.numberOfLines = 2;
            } else {
                label.numberOfLines = 1;
            }

            label.textAlignment = NSTextAlignmentCenter;
            label.attributedText = finalString;
        }
    } else {
        orig_setText(self, _cmd, text);
    }
}

static void hookStatusBarClass(Class cls) {
    if (!cls) return;

    Method m1 = class_getInstanceMethod(cls, @selector(applyStyleAttributes:));
    if (m1) {
        orig_applyStyleAttributes = (void *)method_getImplementation(m1);
        method_setImplementation(m1, (IMP)hook_applyStyleAttributes);
    }

    Method m2 = class_getInstanceMethod(cls, @selector(setText:));
    if (m2) {
        orig_setText = (void *)method_getImplementation(m2);
        method_setImplementation(m2, (IMP)hook_setText);
    }
}

static void initStatusBarTweak(void) {
    Class cls17 = objc_getClass("STUIStatusBarStringView");
    Class cls16 = objc_getClass("_UIStatusBarStringView");

    if (cls17) hookStatusBarClass(cls17);
    if (cls16) hookStatusBarClass(cls16);
}

#pragma mark - Dock Transparency

static void (*orig_setBackgroundAlpha)(id self, SEL _cmd, double alpha);
static void hook_setBackgroundAlpha(id self, SEL _cmd, double alpha) {
    orig_setBackgroundAlpha(self, _cmd, 0.0);
}

static void (*orig_setBackgroundView)(id self, SEL _cmd, id view);
static void hook_setBackgroundView(id self, SEL _cmd, id view) {
    orig_setBackgroundView(self, _cmd, view);
    ((void (*)(id, SEL, BOOL))objc_msgSend)(view, sel_registerName("setHidden:"), YES);
}

static void initDockTransparency(void) {
    Class dockView = objc_getClass("SBDockView");
    if (dockView) {
        Method m = class_getInstanceMethod(dockView, @selector(setBackgroundAlpha:));
        if (m) {
            orig_setBackgroundAlpha = (void *)method_getImplementation(m);
            method_setImplementation(m, (IMP)hook_setBackgroundAlpha);
        }
    }
    Class platterView = objc_getClass("SBFloatingDockPlatterView");
    if (platterView) {
        Method m = class_getInstanceMethod(platterView, @selector(setBackgroundView:));
        if (m) {
            orig_setBackgroundView = (void *)method_getImplementation(m);
            method_setImplementation(m, (IMP)hook_setBackgroundView);
        }
    }
}

#pragma mark - Hide Icon Labels

static void (*orig_applyIconLabelAlpha)(id self, SEL _cmd, double alpha);
static void hook_applyIconLabelAlpha(id self, SEL _cmd, double alpha) {
    orig_applyIconLabelAlpha(self, _cmd, 0.0);
}

static void initHideIconLabels(void) {
    Class iconView = objc_getClass("SBIconView");
    if (!iconView) return;
    Method m = class_getInstanceMethod(iconView, @selector(_applyIconLabelAlpha:));
    if (m) {
        orig_applyIconLabelAlpha = (void *)method_getImplementation(m);
        method_setImplementation(m, (IMP)hook_applyIconLabelAlpha);
    }
}

#pragma mark - Helper Functions

// 执行shell命令（替代system）
static int run_shell_command(const char *cmd) {
    pid_t pid;
    const char *args[] = {"sh", "-c", cmd, NULL};
    int status = posix_spawn(&pid, "/bin/sh", NULL, NULL, (char **)args, NULL);
    if (status == 0) {
        waitpid(pid, &status, 0);
        return WEXITSTATUS(status);
    }
    return status;
}

// 获取keyWindow（兼容iOS 13+）
static UIWindow *getKeyWindow(void) {
    UIWindow *keyWindow = nil;
    
    // 尝试使用新的API (iOS 13+)
    if (@available(iOS 13.0, *)) {
        NSArray *scenes = UIApplication.sharedApplication.connectedScenes.allObjects;
        for (UIScene *scene in scenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive && 
                [scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                for (UIWindow *window in windowScene.windows) {
                    if (window.isKeyWindow) {
                        keyWindow = window;
                        break;
                    }
                }
                if (keyWindow) break;
            }
        }
    }
    
    // 如果新API没找到，使用旧API
    if (!keyWindow) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        keyWindow = UIApplication.sharedApplication.keyWindow;
#pragma clang diagnostic pop
    }
    
    return keyWindow;
}

#pragma mark - TrollStore Helper Integration

@interface LSApplicationProxy : NSObject
@property (nonatomic, readonly) NSString *bundleIdentifier;
@property (nonatomic, readonly) NSString *localizedName;
@property (nonatomic, readonly) NSString *bundleVersion;
@property (nonatomic, readonly) NSURL *bundleURL;
@end

typedef enum {
    PERSISTENCE_HELPER_TYPE_NONE = 0,
    PERSISTENCE_HELPER_TYPE_REGISTERED,
    PERSISTENCE_HELPER_TYPE_ALL
} PersistenceHelperType;

static NSString *trollStoreAppPath(void) {
    NSString *path = @"/Applications/TrollStore.app";
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        return path;
    }
    NSArray *possiblePaths = @[
        @"/var/containers/Bundle/Application/TrollStore.app",
        @"/private/var/containers/Bundle/Application/TrollStore.app"
    ];
    for (NSString *p in possiblePaths) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:p]) {
            return p;
        }
    }
    return nil;
}

static NSString *getTrollStoreVersion(void) {
    NSString *tsPath = trollStoreAppPath();
    if (!tsPath) return nil;
    
    NSString *infoPlist = [tsPath stringByAppendingPathComponent:@"Info.plist"];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPlist];
    return info[@"CFBundleShortVersionString"];
}

static BOOL isTrollStoreInstalled(void) {
    return trollStoreAppPath() != nil;
}

static NSArray<NSString *> *trollStoreInstalledAppContainerPaths(void) {
    NSMutableArray *paths = [NSMutableArray array];
    NSString *trollAppsPath = @"/var/containers/Bundle/Application";
    NSFileManager *fm = [NSFileManager defaultManager];
    
    NSError *error = nil;
    NSArray *contents = [fm contentsOfDirectoryAtPath:trollAppsPath error:&error];
    if (!error) {
        for (NSString *item in contents) {
            NSString *fullPath = [trollAppsPath stringByAppendingPathComponent:item];
            NSArray *subContents = [fm contentsOfDirectoryAtPath:fullPath error:nil];
            for (NSString *subItem in subContents) {
                if ([subItem hasSuffix:@".app"]) {
                    NSString *appPath = [fullPath stringByAppendingPathComponent:subItem];
                    NSString *infoPlist = [appPath stringByAppendingPathComponent:@"Info.plist"];
                    if ([fm fileExistsAtPath:infoPlist]) {
                        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPlist];
                        if (info[@"TrollStore"]) {
                            [paths addObject:appPath];
                        }
                    }
                }
            }
        }
    }
    return paths;
}

static LSApplicationProxy *findPersistenceHelperApp(PersistenceHelperType type) {
    Class LSApplicationWorkspace = objc_getClass("LSApplicationWorkspace");
    if (!LSApplicationWorkspace) return nil;
    
    SEL defaultWorkspace = NSSelectorFromString(@"defaultWorkspace");
    id workspace = ((id (*)(id, SEL))objc_msgSend)((id)LSApplicationWorkspace, defaultWorkspace);
    if (!workspace) return nil;
    
    SEL allApps = NSSelectorFromString(@"allApplications");
    NSArray *apps = ((id (*)(id, SEL))objc_msgSend)(workspace, allApps);
    
    for (id app in apps) {
        NSString *bundleID = [app valueForKey:@"_applicationIdentifier"];
        if ([bundleID isEqualToString:@"com.opa334.trollstorepersistencehelper"] ||
            [bundleID containsString:@"trollstore"] ||
            [bundleID containsString:@"persistence"]) {
            return (LSApplicationProxy *)app;
        }
    }
    return nil;
}

static NSString *rootHelperPath(void) {
    NSString *embeddedPath = [[NSBundle mainBundle] pathForAuxiliaryExecutable:@"trollstorehelper"];
    if (!embeddedPath) {
        embeddedPath = @"/usr/local/bin/trollstorehelper";
    }
    if ([[NSFileManager defaultManager] fileExistsAtPath:embeddedPath]) {
        return embeddedPath;
    }
    return nil;
}

static int spawnRoot(NSString *path, NSArray *args, void *stdoutPipe, void *stderrPipe) {
    if (!path) return -1;
    
    NSMutableArray *argStrings = [NSMutableArray arrayWithObject:path];
    [argStrings addObjectsFromArray:args];
    
    char **argv = (char **)malloc((argStrings.count + 1) * sizeof(char *));
    for (int i = 0; i < argStrings.count; i++) {
        argv[i] = (char *)[argStrings[i] UTF8String];
    }
    argv[argStrings.count] = NULL;
    
    pid_t pid;
    int status = posix_spawn(&pid, [path UTF8String], NULL, NULL, argv, NULL);
    free(argv);
    
    if (status == 0) {
        waitpid(pid, &status, 0);
        return WEXITSTATUS(status);
    }
    return status;
}

static NSData *downloadFile(NSString *urlString) {
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:urlString]
                                             cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                         timeoutInterval:60];
    __block NSData *downloadedData = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            downloadedData = data;
            dispatch_semaphore_signal(sem);
        }];
    [task resume];
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    return downloadedData;
}

static void fetchLatestTrollStoreVersion(void (^completion)(NSString *)) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *apiURL = @"https://api.github.com/repos/opa334/TrollStore/releases/latest";
        NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:apiURL]
                                                 cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                             timeoutInterval:30];
        
        NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            NSString *version = nil;
            if (data && !error) {
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                NSString *tagName = json[@"tag_name"];
                if (tagName) {
                    version = [tagName stringByReplacingOccurrencesOfString:@"v" withString:@""];
                }
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(version);
            });
        }];
        [task resume];
    });
}

#pragma mark - Status Bar gesture

@implementation SpringBoard(Hook)
+ (SpringBoard *)sharedApplication {
    return (id)UIApplication.sharedApplication;
}
- (void)initStatusBarGesture {
    [self.statusBarForEmbeddedDisplay addGestureRecognizer:[[UILongPressGestureRecognizer alloc]
                                                            initWithTarget:self action:@selector(statusBarLongPressed:)
    ]];
}

#pragma mark - TrollStore Management

- (void)installTrollStorePressed {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *tarURL = @"https://github.com/opa334/TrollStore/releases/latest/download/TrollStore.tar";
        NSData *tarData = downloadFile(tarURL);
        
        if (!tarData || tarData.length == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                showAlert(@"错误", @"下载TrollStore失败，请检查网络连接");
            });
            return;
        }
        
        NSString *tarPath = @"/tmp/TrollStore.tar";
        [tarData writeToFile:tarPath atomically:YES];
        
        NSString *helper = rootHelperPath();
        if (helper) {
            int ret = spawnRoot(helper, @[@"install-trollstore", tarPath], nil, nil);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (ret == 0) {
                    showAlert(@"成功", @"TrollStore已安装，请重启设备");
                } else {
                    showAlert(@"错误", [NSString stringWithFormat:@"安装失败，错误码: %d", ret]);
                }
            });
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                showAlert(@"提示", @"需要Root权限才能安装，请确保已通过其他方式获取root权限");
            });
        }
    });
}

- (void)uninstallTrollStorePressed {
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"确认卸载"
        message:@"这将卸载TrollStore及其所有安装的应用，是否继续？"
        preferredStyle:UIAlertControllerStyleAlert];
    
    [confirm addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"卸载" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSString *helper = rootHelperPath();
            int ret = -1;
            if (helper) {
                ret = spawnRoot(helper, @[@"uninstall-trollstore"], nil, nil);
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (ret == 0) {
                    showAlert(@"成功", @"TrollStore已卸载");
                } else {
                    showAlert(@"错误", [NSString stringWithFormat:@"卸载失败，错误码: %d", ret]);
                }
            });
        });
    }]];
    
    UIWindow *keyWindow = getKeyWindow();
    [keyWindow.rootViewController presentViewController:confirm animated:YES completion:nil];
}

- (void)refreshAppRegistrationsPressed {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *helper = rootHelperPath();
        int ret = -1;
        if (helper) {
            ret = spawnRoot(helper, @[@"refresh-apps"], nil, nil);
        } else {
            // 使用posix_spawn替代system
            ret = run_shell_command("uicache -a 2>/dev/null; ldrestart 2>/dev/null");
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (ret == 0) {
                showAlert(@"成功", @"应用注册已刷新");
            } else {
                showAlert(@"提示", @"刷新完成，如果应用仍显示不可用，请尝试重启设备");
            }
        });
    });
}

- (void)registerPersistenceHelperPressed {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *helper = rootHelperPath();
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        int ret = -1;
        if (helper) {
            ret = spawnRoot(helper, @[@"register-user-persistence-helper", bundleID], nil, nil);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (ret == 0) {
                showAlert(@"成功", @"已注册为TrollStore持久化助手");
            } else {
                showAlert(@"错误", @"注册失败，请确保有root权限");
            }
        });
    });
}

- (void)unregisterPersistenceHelperPressed {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *helper = rootHelperPath();
        int ret = -1;
        if (helper) {
            ret = spawnRoot(helper, @[@"uninstall-persistence-helper"], nil, nil);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (ret == 0) {
                showAlert(@"成功", @"已注销持久化助手");
            } else {
                showAlert(@"错误", @"注销失败");
            }
        });
    });
}

- (void)updateTrollStorePressed:(NSString *)newVersion {
    [self installTrollStorePressed];
}

#pragma mark - Main Menu

- (void)showInjectedAlert {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Coruna + TrollStore"
        message:@"已向SpringBoard注入插件，在主屏幕长按左上角显示菜单喵~\no(=•ω＜=)ρ⌒☆\n\nTrollStore状态: 检测中..."
        preferredStyle:UIAlertControllerStyleAlert];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *currentVersion = getTrollStoreVersion();
        NSString *statusMsg;
        if (currentVersion) {
            statusMsg = [NSString stringWithFormat:@"已安装 v%@", currentVersion];
        } else {
            statusMsg = @"未安装";
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            alert.message = [NSString stringWithFormat:@"已向SpringBoard注入插件，在主屏幕长按左上角显示菜单喵~\no(=•ω＜=)ρ⌒☆\n\nTrollStore状态: %@", statusMsg];
        });
    });

    if (!isTrollStoreInstalled()) {
        [alert addAction:[UIAlertAction actionWithTitle:@"📲 安装 TrollStore"
            style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self installTrollStorePressed];
        }]];
    } else {
        [alert addAction:[UIAlertAction actionWithTitle:@"🔄 更新 TrollStore"
            style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            fetchLatestTrollStoreVersion(^(NSString *latestVersion) {
                NSString *currentVersion = getTrollStoreVersion();
                if (latestVersion && [currentVersion compare:latestVersion options:NSNumericSearch] == NSOrderedAscending) {
                    UIAlertController *updateConfirm = [UIAlertController alertControllerWithTitle:@"发现新版本"
                        message:[NSString stringWithFormat:@"当前: %@\n最新: %@\n是否更新？", currentVersion, latestVersion]
                        preferredStyle:UIAlertControllerStyleAlert];
                    [updateConfirm addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
                    [updateConfirm addAction:[UIAlertAction actionWithTitle:@"更新" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                        [self updateTrollStorePressed:latestVersion];
                    }]];
                    UIWindow *keyWindow = getKeyWindow();
                    [keyWindow.rootViewController presentViewController:updateConfirm animated:YES completion:nil];
                } else {
                    showAlert(@"提示", @"当前已是最新版本");
                }
            });
        }]];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"❌ 卸载 TrollStore"
            style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            [self uninstallTrollStorePressed];
        }]];
    }

    if (isTrollStoreInstalled() || trollStoreInstalledAppContainerPaths().count > 0) {
        [alert addAction:[UIAlertAction actionWithTitle:@"🔄 刷新应用注册"
            style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self refreshAppRegistrationsPressed];
        }]];
    }

    LSApplicationProxy *persistenceHelper = findPersistenceHelperApp(PERSISTENCE_HELPER_TYPE_ALL);
    BOOL isRegistered = [persistenceHelper.bundleIdentifier isEqualToString:[[NSBundle mainBundle] bundleIdentifier]];
    
    if (isRegistered) {
        [alert addAction:[UIAlertAction actionWithTitle:@"🔓 注销持久化助手"
            style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self unregisterPersistenceHelperPressed];
        }]];
    } else if (!persistenceHelper) {
        [alert addAction:[UIAlertAction actionWithTitle:@"🔐 注册为持久化助手"
            style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self registerPersistenceHelperPressed];
        }]];
    }

    [alert addAction:[UIAlertAction actionWithTitle:@"🔍 搜索 Tips 目录"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self searchTipsDirectoryLegacy];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"⏰ 状态栏显示设置"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self showStatusBarSettings];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"🔦 通过行动按键开启闪光灯"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        showAlert(@"Action Button", @"单击: 开关闪光灯\n双击: Magic ✨\n长按: 触发原有的功能\n\n仅支持iPhone 15 Pro+(iOS 17)");
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"📦 加载.dylib插件"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UIDocumentPickerViewController *documentPickerVC = [[UIDocumentPickerViewController alloc]
                initForOpeningContentTypes:@[[UTType typeWithFilenameExtension:@"dylib" conformingToType:UTTypeData]]
                asCopy:NO];
        documentPickerVC.allowsMultipleSelection = YES;
        documentPickerVC.delegate = (id<UIDocumentPickerDelegate>)self;
        UIWindow *keyWindow = getKeyWindow();
        [keyWindow.rootViewController presentViewController:documentPickerVC animated:YES completion:nil];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"🐛 激活FLEX调试"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        Class flexManagerClass = NSClassFromString(@"FLEXManager");
        if (flexManagerClass) {
            id sharedManager = [flexManagerClass valueForKey:@"sharedManager"];
            [sharedManager performSelector:@selector(showExplorer)];
        } else {
            showAlert(@"Error", @"未找到FLEXManager, 请先加载libFLEX.dylib");
        }
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"🔄 Respring (移除所有功能)"
        style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        exit(0);
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"取消"
        style:UIAlertActionStyleCancel handler:nil]];

    UIWindow *keyWindow = getKeyWindow();
    [keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
}

- (void)searchTipsDirectoryLegacy {
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSMutableString *logContent = [NSMutableString string];
        [logContent appendString:@"=== Tips 目录搜索日志 ===\n"];
        
        Class LSApplicationWorkspace = objc_getClass("LSApplicationWorkspace");
        if (LSApplicationWorkspace) {
            SEL defaultWorkspace = NSSelectorFromString(@"defaultWorkspace");
            id workspace = ((id (*)(id, SEL))objc_msgSend)((id)LSApplicationWorkspace, defaultWorkspace);
            SEL allApps = NSSelectorFromString(@"allApplications");
            NSArray *apps = ((id (*)(id, SEL))objc_msgSend)(workspace, allApps);
            
            for (id app in apps) {
                NSString *bundleID = [app valueForKey:@"_applicationIdentifier"];
                if ([bundleID isEqualToString:@"com.apple.tips"]) {
                    NSString *path = [app valueForKey:@"_path"];
                    [logContent appendFormat:@"找到 Tips: %@\n", path];
                    break;
                }
            }
        }
        
        NSString *logPath = @"/tmp/tips_search_log.txt";
        [logContent writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            UIAlertController *result = [UIAlertController alertControllerWithTitle:@"Tips搜索完成"
                message:[logContent substringToIndex:MIN(500, logContent.length)]
                preferredStyle:UIAlertControllerStyleAlert];
            [result addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
            UIWindow *keyWindow = getKeyWindow();
            [keyWindow.rootViewController presentViewController:result animated:YES completion:nil];
        });
    });
}

- (void)showStatusBarSettings {
    UIAlertController *settings = [UIAlertController alertControllerWithTitle:@"状态栏设置"
        message:@"设置日期与时间的格式\n例如:\n  时间: HH:mm  HH:mm:ss  h:mm a\n  日期: E dd/MM/yyyy  EE d/M/yy\n\n如果日期留空那么仅显示时间"
        preferredStyle:UIAlertControllerStyleAlert];

    [settings addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"时间格式 (例如 HH:mm)";
        tf.text = getTimeFormat();
        tf.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];

    [settings addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"日期格式 (例如 E dd/MM/yyyy)";
        tf.text = getDateFormat();
        tf.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];

    [settings addAction:[UIAlertAction actionWithTitle:@"应用" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *timeFmt = settings.textFields[0].text;
        NSString *dateFmt = settings.textFields[1].text;

        if (timeFmt.length == 0) timeFmt = @"HH:mm";

        NSDateFormatter *testFmt = [[NSDateFormatter alloc] init];
        [testFmt setDateFormat:timeFmt];
        NSString *testResult = [testFmt stringFromDate:[NSDate date]];
        if (!testResult || testResult.length == 0) {
            showAlert(@"Error", [NSString stringWithFormat:@"时间格式错误: %@", timeFmt]);
            return;
        }
        if (dateFmt.length > 0) {
            [testFmt setDateFormat:dateFmt];
            testResult = [testFmt stringFromDate:[NSDate date]];
            if (!testResult || testResult.length == 0) {
                showAlert(@"Error", [NSString stringWithFormat:@"日期格式错误: %@", dateFmt]);
                return;
            }
        }

        g_timeFormat = [timeFmt copy];
        g_dateFormat = [dateFmt copy];

        initStatusBarTweak();
        showAlert(@"已应用", [NSString stringWithFormat:@"时间格式: %@\n日期格式: %@\n锁屏并重新解锁让更改生效",
            g_timeFormat, g_dateFormat.length > 0 ? g_dateFormat : @"(none)"]);
    }]];

    [settings addAction:[UIAlertAction actionWithTitle:@"恢复默认" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        g_timeFormat = nil;
        g_dateFormat = nil;  // 修复：原拼写错误 g_dateDateFormat
        initStatusBarTweak();
        showAlert(@"Reset", @"已恢复默认 (HH:mm / E dd/MM/yyyy).\n锁屏并重新解锁让更改生效");
    }]];

    [settings addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    UIWindow *keyWindow = getKeyWindow();
    [keyWindow.rootViewController presentViewController:settings animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (urls.count <= 0) return;
    NSString *log = @"";
    for (NSURL *url in urls) {
        NSString *path = url.path;
        log = [log stringByAppendingFormat:@"加载%@:", path.lastPathComponent];
        void *handle = dlopen(path.UTF8String, RTLD_NOW);
        if (handle) {
            log = [log stringByAppendingString:@"成功\n"];
        } else {
            log = [log stringByAppendingFormat:@" 失败: %s\n", dlerror()];
        }
    }
    showAlert(@"结果", log);
}

- (void)statusBarLongPressed:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [self showInjectedAlert];
    }
}

+ (UIViewController *)viewControllerToPresent {
    UIWindow *keyWindow = getKeyWindow();
    UIViewController *root = keyWindow.rootViewController;
    while (root.presentedViewController) root = root.presentedViewController;
    return root;
}
@end

#pragma mark - Action Button Tweak

static BOOL g_actionLongPressActive = NO;
static id g_lastDownEvent = nil;
static NSInteger g_clickCount = 0;
static NSTimeInterval g_firstClickTime = 0;
static dispatch_source_t g_clickTimer = nil;

static const NSTimeInterval kDoubleClickInterval = 0.22;
static const NSTimeInterval kSingleClickTimeout = 0.52;

static IMP orig_configureButtonArbiter = NULL;
static IMP orig_actionButtonDown = NULL;
static IMP orig_actionButtonUp = NULL;
static IMP orig_actionButtonLongPress = NULL;

static void toggleFlashlight(void) {
    Class cls = objc_getClass("SBUIFlashlightController");
    if (!cls) return;
    id controller = ((id (*)(id, SEL))objc_msgSend)((id)cls, sel_registerName("sharedInstance"));
    if (!controller) return;
    NSUInteger level = ((NSUInteger (*)(id, SEL))objc_msgSend)(controller, sel_registerName("level"));
    ((void (*)(id, SEL, NSUInteger))objc_msgSend)(controller, sel_registerName("setLevel:"), level > 0 ? 0 : 1);
}

static void openDoubleClickURL(void) {
    NSURL *url = [NSURL URLWithString:@"https://www.youtube.com/watch?v=dQw4w9WgXcQ"];
    ((void (*)(id, SEL, id, id, id))objc_msgSend)(
        [UIApplication sharedApplication],
        sel_registerName("openURL:options:completionHandler:"),
        url, @{}, nil);
}

static void cancelClickTimer(void) {
    if (g_clickTimer) {
        dispatch_source_cancel(g_clickTimer);
        g_clickTimer = nil;
    }
}

static void hook_configureButtonArbiter(id self, SEL _cmd) {
    ((void (*)(id, SEL))orig_configureButtonArbiter)(self, _cmd);
    Ivar arbiterIvar = class_getInstanceVariable(object_getClass(self), "_buttonArbiter");
    if (!arbiterIvar) return;
    id arbiter = object_getIvar(self, arbiterIvar);
    if (!arbiter) return;
    SEL setMaxSel = sel_registerName("setMaximumRepeatedPressCount:");
    if ([arbiter respondsToSelector:setMaxSel]) {
        ((void (*)(id, SEL, unsigned long long))objc_msgSend)(arbiter, setMaxSel, 0);
    }
}

static void hook_actionButtonDown(id self, SEL _cmd, id event) {
    g_lastDownEvent = event;
}

static void hook_actionButtonUp(id self, SEL _cmd, id event) {
    if (g_actionLongPressActive) {
        g_actionLongPressActive = NO;
        ((void (*)(id, SEL, id))orig_actionButtonUp)(self, _cmd, event);
        return;
    }

    NSTimeInterval now = [[NSProcessInfo processInfo] systemUptime];
    g_clickCount++;

    if (g_clickCount == 1) {
        g_firstClickTime = now;
        cancelClickTimer();
        g_clickTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(g_clickTimer,
            dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSingleClickTimeout * NSEC_PER_SEC)), DISPATCH_TIME_FOREVER, 0);
        dispatch_source_set_event_handler(g_clickTimer, ^{
            cancelClickTimer();
            g_clickCount = 0;
            toggleFlashlight();
        });
        dispatch_resume(g_clickTimer);
    } else if (g_clickCount >= 2) {
        NSTimeInterval interval = now - g_firstClickTime;
        cancelClickTimer();
        g_clickCount = 0;
        if (interval <= kDoubleClickInterval) {
            openDoubleClickURL();
        } else {
            toggleFlashlight();
        }
    }
}

static void hook_actionButtonLongPress(id self, SEL _cmd, id event) {
    g_actionLongPressActive = YES;
    cancelClickTimer();
    g_clickCount = 0;
    ((void (*)(id, SEL, id))orig_actionButtonDown)(self, _cmd, g_lastDownEvent);
    ((void (*)(id, SEL, id))orig_actionButtonLongPress)(self, _cmd, event);
}

static void initActionButtonTweak(void) {
    Class cls = objc_getClass("SBRingerHardwareButton");
    if (!cls) return;

    Method m;

    m = class_getInstanceMethod(cls, @selector(_configureButtonArbiter));
    if (m) {
        orig_configureButtonArbiter = method_getImplementation(m);
        method_setImplementation(m, (IMP)hook_configureButtonArbiter);
    }

    m = class_getInstanceMethod(cls, @selector(performActionsForButtonDown:));
    if (m) {
        orig_actionButtonDown = method_getImplementation(m);
        method_setImplementation(m, (IMP)hook_actionButtonDown);
    }

    m = class_getInstanceMethod(cls, @selector(performActionsForButtonUp:));
    if (m) {
        orig_actionButtonUp = method_getImplementation(m);
        method_setImplementation(m, (IMP)hook_actionButtonUp);
    }

    m = class_getInstanceMethod(cls, @selector(performActionsForButtonLongPress:));
    if (m) {
        orig_actionButtonLongPress = method_getImplementation(m);
        method_setImplementation(m, (IMP)hook_actionButtonLongPress);
    }
}

#pragma mark - FrontBoard Trust Bypass

static IMP orig_trustStateForApplication = NULL;
static NSUInteger hook_trustStateForApplication(id self, SEL _cmd, id application) {
    return 8;
}

static void initFrontBoardBypass(void) {
    Class cls = objc_getClass("FBSSignatureValidationService");
    if (cls) {
        Method m = class_getInstanceMethod(cls, @selector(trustStateForApplication:));
        if (m) {
            orig_trustStateForApplication = method_getImplementation(m);
            method_setImplementation(m, (IMP)hook_trustStateForApplication);
        }
    }
}

#pragma mark - RBSLaunchContext Hook

@interface RBSLaunchContext : NSObject
@property (nonatomic, copy, readonly) NSString *bundleIdentifier;
@end
@implementation RBSLaunchContext(Hook)
- (NSString *)_overrideExecutablePath {
    if([self.bundleIdentifier isEqualToString:@"com.apple.tips"]) {
        return @"/tmp/PersistenceHelper_Embedded";
    }
    return nil;
}
@end

#pragma mark - Helpers

void showAlert(NSString *title, NSString *message) {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    UIWindow *keyWindow = getKeyWindow();
    [keyWindow.rootViewController presentViewController:a animated:YES completion:nil];
}

#pragma mark - Constructor

__attribute__((constructor)) static void init() {
    initFrontBoardBypass();
    initStatusBarTweak();
    initActionButtonTweak();
    initDockTransparency();
    initHideIconLabels();
    [SpringBoard.sharedApplication initStatusBarGesture];

    // Auto-download PersistenceHelper to /tmp if not present
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *helperPath = @"/tmp/PersistenceHelper_Embedded";
        if (![[NSFileManager defaultManager] fileExistsAtPath:helperPath]) {
            NSString *url = @"https://github.com/opa334/TrollStore/releases/download/2.1/PersistenceHelper_Embedded";
            NSData *data = downloadFile(url);
            if (data && data.length > 0) {
                [data writeToFile:helperPath atomically:YES];
                chmod(helperPath.UTF8String, 0755);
            }
        }
    });

    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *flag = @"/tmp/.coruna_welcomed";
        if (![[NSFileManager defaultManager] fileExistsAtPath:flag]) {
            [@"" writeToFile:flag atomically:YES encoding:NSUTF8StringEncoding error:nil];
            UIAlertController *welcome = [UIAlertController alertControllerWithTitle:@"Welcome to Coruna + TrollStore"
                message:@"Your device has been jailbroken!\n\n"
                         "Features enabled:\n"
                         "  • Custom status bar (time + date)\n"
                         "  • Action button → Flashlight\n"
                         "  • Transparent dock\n"
                         "  • Hidden icon labels\n"
                         "  • TrollStore Helper integrated\n\n"
                         "Long-press the status bar for settings."
                preferredStyle:UIAlertControllerStyleAlert];
            [welcome addAction:[UIAlertAction actionWithTitle:@"Let's go!" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                [SpringBoard.sharedApplication showInjectedAlert];
            }]];
            UIWindow *keyWindow = getKeyWindow();
            [keyWindow.rootViewController presentViewController:welcome animated:YES completion:nil];
        }
    });
}
