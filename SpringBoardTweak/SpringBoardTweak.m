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
    
    // 延迟初始化，等待 SpringBoard 完全启动
    dispatch_async(dispatch_get_main_queue(), ^{
        // 再延迟2秒，确保 UI 完全准备好
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [SpringBoard.sharedApplication initStatusBarGesture];
            [self checkAndSetupPersistenceHelper];
        });
    });
}

// 检查并设置 PersistenceHelper（延迟执行，避免启动时阻塞）
+ (void)checkAndSetupPersistenceHelper {
    NSString *helperPath = @"/tmp/PersistenceHelper_Embedded";
    NSString *flag = @"/tmp/.coruna_welcomed";
    BOOL helperExists = [[NSFileManager defaultManager] fileExistsAtPath:helperPath];
    BOOL hasShownWelcome = [[NSFileManager defaultManager] fileExistsAtPath:flag];
    
    // 标记已显示欢迎界面
    if (!hasShownWelcome) {
        [@"" writeToFile:flag atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    
    // 如果 PersistenceHelper 不存在，显示设置选项
    if (!helperExists) {
        [self showPersistenceHelperSetup];
    } else if (!hasShownWelcome) {
        // 首次启动且文件已存在，显示主欢迎界面
        [self showMainWelcome];
    }
}

// 显示 PersistenceHelper 设置选项
+ (void)showPersistenceHelperSetup {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Coruna + TrollStore"
        message:@"欢迎使用 Coruna！\n\n"
              "TrollStore 功能需要 PersistenceHelper_Embedded 文件。\n"
              "该文件可从 GitHub 下载：https://github.com/opa334/TrollStore/releases\n\n"
              "请选择获取方式："
        preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"📂 选择本地文件" 
        style:UIAlertActionStyleDefault 
        handler:^(UIAlertAction *action) {
        [self selectPersistenceHelperFile];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"⬇️ 尝试自动下载" 
        style:UIAlertActionStyleDefault 
        handler:^(UIAlertAction *action) {
        [self downloadPersistenceHelperWithUI];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"❓ 什么是这个？" 
        style:UIAlertActionStyleDefault 
        handler:^(UIAlertAction *action) {
        [self showHelperInfo];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"稍后再说" 
        style:UIAlertActionStyleCancel 
        handler:^(UIAlertAction *action) {
        [self showMainWelcome];
    }]];
    
    // 确保有有效的 rootViewController
    UIViewController *rootVC = [self getValidRootViewController];
    if (rootVC) {
        [rootVC presentViewController:alert animated:YES completion:nil];
    } else {
        NSLog(@"[Coruna] Error: Cannot find valid root view controller");
    }
}

// 获取有效的 rootViewController（带重试）
+ (UIViewController *)getValidRootViewController {
    UIWindow *keyWindow = getKeyWindow();
    UIViewController *root = keyWindow.rootViewController;
    
    // 如果当前有 presentedViewController，使用它
    while (root.presentedViewController) {
        root = root.presentedViewController;
    }
    
    return root;
}

// 带 UI 反馈的下载
+ (void)downloadPersistenceHelperWithUI {
    // 显示进度提示
    UIAlertController *progressAlert = [UIAlertController alertControllerWithTitle:@"⬇️ 下载中..."
        message:@"正在尝试从多个源下载...\n请稍候"
        preferredStyle:UIAlertControllerStyleAlert];
    
    UIViewController *rootVC = [self getValidRootViewController];
    [rootVC presentViewController:progressAlert animated:YES completion:nil];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *helperPath = @"/tmp/PersistenceHelper_Embedded";
        
        // 多个下载源（从旧到新尝试）
        NSArray *urls = @[
            @"https://github.com/opa334/TrollStore/releases/download/2.0.15/PersistenceHelper_Embedded",
            @"https://github.com/opa334/TrollStore/releases/download/2.0.14/PersistenceHelper_Embedded",
            @"https://github.com/opa334/TrollStore/releases/download/2.0.13/PersistenceHelper_Embedded",
            @"https://github.com/opa334/TrollStore/releases/download/2.0.12/PersistenceHelper_Embedded",
            @"https://github.com/opa334/TrollStore/releases/download/2.0.11/PersistenceHelper_Embedded",
            @"https://github.com/opa334/TrollStore/releases/download/2.0.9/PersistenceHelper_Embedded",
            @"https://github.com/opa334/TrollStore/releases/download/2.0.8/PersistenceHelper_Embedded",
            @"https://github.com/opa334/TrollStore/releases/download/2.0.7/PersistenceHelper_Embedded",
            @"https://github.com/opa334/TrollStore/releases/download/2.0.6/PersistenceHelper_Embedded",
            @"https://github.com/opa334/TrollStore/releases/download/2.0.5/PersistenceHelper_Embedded",
            @"https://github.com/opa334/TrollStore/releases/download/2.0.4/PersistenceHelper_Embedded",
            @"https://github.com/opa334/TrollStore/releases/download/2.0.2/PersistenceHelper_Embedded",
            @"https://github.com/opa334/TrollStore/releases/download/2.0.1/PersistenceHelper_Embedded",
            @"https://github.com/opa334/TrollStore/releases/download/2.0/PersistenceHelper_Embedded"
        ];
        
        __block BOOL downloaded = NO;
        __block NSString *lastError = @"Unknown error";
        
        for (NSString *urlString in urls) {
            NSLog(@"[Coruna] Trying: %@", urlString);
            
            // 更新进度（需要在主线程）
            dispatch_async(dispatch_get_main_queue(), ^{
                progressAlert.message = [NSString stringWithFormat:@"尝试: %@", 
                    [[urlString lastPathComponent] stringByDeletingPathExtension]];
            });
            
            NSData *data = downloadFile(urlString);
            
            if (data && data.length > 1000) { // 至少1KB，避免下载到错误页面
                // 验证文件头
                if (data.length > 4) {
                    uint32_t magic = *(uint32_t *)data.bytes;
                    // Mach-O 64位: 0xfeedfacf, 32位: 0xfeedface, FAT: 0xcafebabe
                    if (magic == 0xfeedfacf || magic == 0xfeedface || 
                        magic == 0xcafebabe || magic == 0xbebafeca) {
                        
                        if ([data writeToFile:helperPath atomically:YES]) {
                            chmod(helperPath.UTF8String, 0755);
                            downloaded = YES;
                            NSLog(@"[Coruna] Success from: %@", urlString);
                            break;
                        }
                    } else {
                        lastError = [NSString stringWithFormat:@"Invalid file (magic: 0x%x)", magic];
                    }
                }
            } else {
                lastError = @"Download failed or file too small";
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [progressAlert dismissViewControllerAnimated:YES completion:^{
                if (downloaded) {
                    UIAlertController *success = [UIAlertController alertControllerWithTitle:@"✅ 下载成功"
                        message:@"PersistenceHelper 已安装，TrollStore 功能现在可用！"
                        preferredStyle:UIAlertControllerStyleAlert];
                    [success addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                        [self showMainWelcome];
                    }]];
                    UIViewController *root = [self getValidRootViewController];
                    [root presentViewController:success animated:YES completion:nil];
                } else {
                    UIAlertController *fail = [UIAlertController alertControllerWithTitle:@"❌ 下载失败"
                        message:[NSString stringWithFormat:@"%@\n\n请手动下载后选择本地文件", lastError]
                        preferredStyle:UIAlertControllerStyleAlert];
                    [fail addAction:[UIAlertAction actionWithTitle:@"选择文件" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                        [self selectPersistenceHelperFile];
                    }]];
                    [fail addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
                        [self showMainWelcome];
                    }]];
                    UIViewController *root = [self getValidRootViewController];
                    [root presentViewController:fail animated:YES completion:nil];
                }
            }];
        });
    });
}

// 显示说明信息
+ (void)showHelperInfo {
    UIAlertController *info = [UIAlertController alertControllerWithTitle:@"关于 PersistenceHelper"
        message:@"PersistenceHelper 是 TrollStore 的辅助工具，用于：\n\n"
              "• 在设备重启后重新注册 TrollStore 安装的应用\n"
              "• 修复应用显示为\"不可用\"的问题\n"
              "• 作为持久化助手维持 TrollStore 的功能\n\n"
              "文件位置：/tmp/PersistenceHelper_Embedded\n"
              "来源：https://github.com/opa334/TrollStore/releases"
        preferredStyle:UIAlertControllerStyleAlert];
    [info addAction:[UIAlertAction actionWithTitle:@"返回" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self showPersistenceHelperSetup];
    }]];
    UIViewController *root = [self getValidRootViewController];
    [root presentViewController:info animated:YES completion:nil];
}

// 选择本地文件
+ (void)selectPersistenceHelperFile {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[[UTType typeWithFilenameExtension:@"" conformingToType:UTTypeData],
                                      [UTType typeWithFilenameExtension:@"embedded" conformingToType:UTTypeData]]
        asCopy:YES];
    picker.allowsMultipleSelection = NO;
    picker.delegate = (id<UIDocumentPickerDelegate>)self;
    picker.title = @"选择 PersistenceHelper_Embedded";
    
    UIViewController *root = [self getValidRootViewController];
    [root presentViewController:picker animated:YES completion:nil];
}

// 文件选择回调
+ (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (urls.count == 0) {
        [self showMainWelcome];
        return;
    }
    
    NSURL *url = urls.firstObject;
    NSString *selectedPath = url.path;
    NSString *helperPath = @"/tmp/PersistenceHelper_Embedded";
    
    NSLog(@"[Coruna] Selected: %@", selectedPath);
    
    // 读取文件
    NSData *data = [NSData dataWithContentsOfFile:selectedPath];
    if (!data || data.length == 0) {
        showAlert(@"❌ 错误", @"无法读取文件");
        [self showPersistenceHelperSetup];
        return;
    }
    
    // 验证文件
    BOOL isValid = NO;
    if (data.length > 4) {
        uint32_t magic = *(uint32_t *)data.bytes;
        if (magic == 0xfeedfacf || magic == 0xfeedface || 
            magic == 0xcafebabe || magic == 0xbebafeca) {
            isValid = YES;
        }
    }
    
    // 检查文件名
    NSString *fileName = selectedPath.lastPathComponent.lowercaseString;
    if ([fileName containsString:@"persistence"] || [fileName containsString:@"helper"]) {
        isValid = YES;
    }
    
    if (!isValid) {
        UIAlertController *warn = [UIAlertController alertControllerWithTitle:@"⚠️ 警告"
            message:@"文件可能不是有效的 PersistenceHelper，是否仍要使用？"
            preferredStyle:UIAlertControllerStyleAlert];
        [warn addAction:[UIAlertAction actionWithTitle:@"重新选择" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
            [self selectPersistenceHelperFile];
        }]];
        [warn addAction:[UIAlertAction actionWithTitle:@"仍要使用" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self installHelper:data];
        }]];
        UIViewController *root = [self getValidRootViewController];
        [root presentViewController:warn animated:YES completion:nil];
    } else {
        [self installHelper:data];
    }
}

+ (void)installHelper:(NSData *)data {
    NSString *helperPath = @"/tmp/PersistenceHelper_Embedded";
    
    // 删除旧文件
    [[NSFileManager defaultManager] removeItemAtPath:helperPath error:nil];
    
    // 写入新文件
    if ([data writeToFile:helperPath atomically:YES]) {
        chmod(helperPath.UTF8String, 0755);
        
        // 验证
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:helperPath error:nil];
        NSString *sizeStr = [NSByteCountFormatter stringFromByteCount:[attrs fileSize] 
                                                           countStyle:NSByteCountFormatterCountStyleFile];
        
        UIAlertController *success = [UIAlertController alertControllerWithTitle:@"✅ 安装成功"
            message:[NSString stringWithFormat:@"文件大小: %@\n路径: %@", sizeStr, helperPath]
            preferredStyle:UIAlertControllerStyleAlert];
        [success addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self showMainWelcome];
        }]];
        UIViewController *root = [self getValidRootViewController];
        [root presentViewController:success animated:YES completion:nil];
    } else {
        showAlert(@"❌ 失败", @"无法写入文件");
        [self showPersistenceHelperSetup];
    }
}

+ (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    [self showMainWelcome];
}

// 主欢迎界面
+ (void)showMainWelcome {
    NSString *helperPath = @"/tmp/PersistenceHelper_Embedded";
    BOOL helperExists = [[NSFileManager defaultManager] fileExistsAtPath:helperPath];
    
    NSString *extraMsg = helperExists ? @"" : @"\n\n⚠️ PersistenceHelper 未安装，TrollStore功能受限";
    
    UIAlertController *welcome = [UIAlertController alertControllerWithTitle:@"Welcome to Coruna"
        message:[NSString stringWithFormat:@"设备已越狱！\n\n"
                 "可用功能：\n"
                 "  • 自定义状态栏（时间+日期）\n"
                 "  • 操作按钮 → 手电筒\n"
                 "  • 透明 Dock\n"
                 "  • 隐藏图标标签\n"
                 "  • TrollStore 助手%@\n\n"
                 "长按状态栏打开菜单", extraMsg]
        preferredStyle:UIAlertControllerStyleAlert];
    [welcome addAction:[UIAlertAction actionWithTitle:@"开始使用" style:UIAlertActionStyleDefault handler:nil]];
    
    UIViewController *root = [self getValidRootViewController];
    [root presentViewController:welcome animated:YES completion:nil];
}

@end
