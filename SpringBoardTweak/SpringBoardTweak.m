// SpringBoardTweak.m - 本地文件选择版
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

#pragma mark - File Selection Helpers

// 显示文件选择器选择指定类型文件
- (void)showFilePickerForType:(NSString *)fileExtension 
                    message:(NSString *)message 
               completion:(void (^)(NSString *filePath))completion {
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"需要文件"
        message:message
        preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"选择文件" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        // 创建文档选择器
        UTType *contentType = [UTType typeWithFilenameExtension:fileExtension conformingToType:UTTypeData];
        UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] 
            initForOpeningContentTypes:@[contentType] 
            asCopy:YES]; // 复制到沙盒，避免权限问题
        
        picker.allowsMultipleSelection = NO;
        
        // 使用关联对象存储回调
        objc_setAssociatedObject(picker, "completionBlock", completion, OBJC_ASSOCIATION_COPY_NONATOMIC);
        objc_setAssociatedObject(picker, "fileExtension", fileExtension, OBJC_ASSOCIATION_COPY_NONATOMIC);
        
        picker.delegate = (id<UIDocumentPickerDelegate>)self;
        
        UIWindow *keyWindow = getKeyWindow();
        [keyWindow.rootViewController presentViewController:picker animated:YES completion:nil];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    
    UIWindow *keyWindow = getKeyWindow();
    [keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
}

#pragma mark - TrollStore Installation with File Selection

// 安装 TrollStore - 改为本地文件选择
- (void)installTrollStorePressed {
    [self showFilePickerForType:@"tar"
        message:@"请选择 TrollStore.tar 文件\n\n请先从 GitHub 下载 TrollStore.tar 到文件 App，然后在此处选择"
        completion:^(NSString *tarPath) {
        if (!tarPath) {
            showAlert(@"取消", @"未选择文件，安装已取消");
            return;
        }
        
        // 验证文件
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:tarPath]) {
            showAlert(@"错误", @"选择的文件不存在");
            return;
        }
        
        // 检查文件大小（至少 1MB）
        NSDictionary *attrs = [fm attributesOfItemAtPath:tarPath error:nil];
        unsigned long long size = [attrs fileSize];
        if (size < 1024 * 1024) {
            showAlert(@"错误", @"文件太小，可能不是有效的 TrollStore.tar");
            return;
        }
        
        // 复制到 /tmp 目录（确保有权限访问）
        NSString *destPath = @"/tmp/TrollStore.tar";
        NSError *error = nil;
        [fm removeItemAtPath:destPath error:nil]; // 删除旧文件
        [fm copyItemAtPath:tarPath toPath:destPath error:&error];
        
        if (error) {
            showAlert(@"错误", [NSString stringWithFormat:@"无法复制文件: %@", error.localizedDescription]);
            return;
        }
        
        // 执行安装
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSString *helper = rootHelperPath();
            if (helper) {
                int ret = spawnRoot(helper, @[@"install-trollstore", destPath], nil, nil);
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (ret == 0) {
                        showAlert(@"成功", @"TrollStore 已安装，请重启设备");
                    } else {
                        showAlert(@"错误", [NSString stringWithFormat:@"安装失败，错误码: %d\n\n请确保:\n1. 文件未损坏\n2. 有 root 权限\n3. 系统版本兼容", ret]);
                    }
                });
            } else {
                dispatch_async(dispatch_get_main_queue(), ^{
                    showAlert(@"错误", @"未找到 trollstorehelper\n请确保已通过其他方式安装 TrollStore 辅助工具");
                });
            }
        });
    }];
}

// 更新 TrollStore - 同样使用文件选择
- (void)updateTrollStorePressed {
    [self installTrollStorePressed];
}

- (void)uninstallTrollStorePressed {
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"确认卸载"
        message:@"这将卸载 TrollStore 及其所有安装的应用，是否继续？"
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
                    showAlert(@"成功", @"TrollStore 已卸载");
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
            // 使用 posix_spawn 替代 system
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

// 注册持久化助手 - 改为文件选择
- (void)registerPersistenceHelperPressed {
    [self showFilePickerForType:@"tipa"
        message:@"请选择 PersistenceHelper_Embedded.tipa 文件\n\n这是 TrollStore 的持久化助手安装包"
        completion:^(NSString *tipaPath) {
        if (!tipaPath) {
            showAlert(@"取消", @"未选择文件");
            return;
        }
        
        // 复制到 /tmp
        NSString *destPath = @"/tmp/PersistenceHelper_Embedded.tipa";
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm removeItemAtPath:destPath error:nil];
        
        NSError *error = nil;
        [fm copyItemAtPath:tipaPath toPath:destPath error:&error];
        
        if (error) {
            showAlert(@"错误", [NSString stringWithFormat:@"复制失败: %@", error.localizedDescription]);
            return;
        }
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSString *helper = rootHelperPath();
            NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
            int ret = -1;
            if (helper) {
                // 先安装 tipa 到 Tips 应用
                ret = spawnRoot(helper, @[@"install-tipa", destPath], nil, nil);
                if (ret == 0) {
                    // 然后注册为持久化助手
                    ret = spawnRoot(helper, @[@"register-user-persistence-helper", bundleID], nil, nil);
                }
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (ret == 0) {
                    showAlert(@"成功", @"已注册为 TrollStore 持久化助手\n\n请确保 Tips 应用未被删除");
                } else {
                    showAlert(@"错误", [NSString stringWithFormat:@"注册失败，错误码: %d\n\n请检查:\n1. 文件是否正确\n2. 是否有 root 权限\n3. Tips 应用是否存在", ret]);
                }
            });
        });
    }];
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

#pragma mark - Main Menu

- (void)showInjectedAlert {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Coruna + TrollStore"
        message:@"已向 SpringBoard 注入插件，在主屏幕长按左上角显示菜单喵~\no(=•ω＜=)ρ⌒☆\n\nTrollStore 状态: 检测中..."
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
            alert.message = [NSString stringWithFormat:@"已向 SpringBoard 注入插件，在主屏幕长按左上角显示菜单喵~\no(=•ω＜=)ρ⌒☆\n\nTrollStore 状态: %@", statusMsg];
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
            [self updateTrollStorePressed];
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
        showAlert(@"Action Button", @"单击: 开关闪光灯\n双击: Magic ✨\n长按: 触发原有的功能\n\n仅支持 iPhone 15 Pro+ (iOS 17)");
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"📦 加载 .dylib 插件"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UIDocumentPickerViewController *documentPickerVC = [[UIDocumentPickerViewController alloc]
                initForOpeningContentTypes:@[[UTType typeWithFilenameExtension:@"dylib" conformingToType:UTTypeData]]
                asCopy:NO];
        documentPickerVC.allowsMultipleSelection = YES;
        documentPickerVC.delegate = (id<UIDocumentPickerDelegate>)self;
        UIWindow *keyWindow = getKeyWindow();
        [keyWindow.rootViewController presentViewController:documentPickerVC animated:YES completion:nil];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"🐛 激活 FLEX 调试"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        Class flexManagerClass = NSClassFromString(@"FLEXManager");
        if (flexManagerClass) {
            id sharedManager = [flexManagerClass valueForKey:@"sharedManager"];
            [sharedManager performSelector:@selector(showExplorer)];
        } else {
            showAlert(@"Error", @"未找到 FLEXManager, 请先加载 libFLEX.dylib");
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
        [logContent writeToFile:logPath atomically:YES encoding:NSUTF8Encoding error:nil];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            UIAlertController *result = [UIAlertController alertControllerWithTitle:@"Tips 搜索完成"
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
        g_dateFormat = nil;
        initStatusBarTweak();
        showAlert(@"Reset", @"已恢复默认 (HH:mm / E dd/MM/yyyy).\n锁屏并重新解锁让更改生效");
    }]];

    [settings addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    UIWindow *keyWindow = getKeyWindow();
    [keyWindow.rootViewController presentViewController:settings animated:YES completion:nil];
}

// 文档选择器回调 - 处理 TrollStore 安装文件
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (urls.count == 0) return;
    
    NSURL *url = urls.firstObject;
    NSString *path = url.path;
    
    // 获取关联的回调
    void (^completion)(NSString *) = objc_getAssociatedObject(controller, "completionBlock");
    NSString *expectedExt = objc_getAssociatedObject(controller, "fileExtension");
    
    // 验证扩展名
    if (expectedExt && ![path.pathExtension.lowercaseString isEqualToString:expectedExt.lowercaseString]) {
        showAlert(@"错误", [NSString stringWithFormat:@"请选择 .%@ 文件", expectedExt]);
        if (completion) completion(nil);
        return;
    }
    
    // 安全访问文件
    [url startAccessingSecurityScopedResource];
    NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:path.lastPathComponent];
    
    NSError *error = nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    
    // 复制到临时目录
    [fm removeItemAtPath:tempPath error:nil];
    [fm copyItemAtPath:path toPath:tempPath error:&error];
    [url stopAccessingSecurityScopedResource];
    
    if (error) {
        showAlert(@"错误", [NSString stringWithFormat:@"无法访问文件: %@", error.localizedDescription]);
        if (completion) completion(nil);
        return;
    }
    
    if (completion) {
        completion(tempPath);
    }
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    void (^completion)(NSString *) = objc_getAssociatedObject(controller, "completionBlock");
    if (completion) completion(nil);
}

// 原有的 dylib 加载回调
- (void)loadDylibDocumentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (urls.count <= 0) return;
    NSString *log = @"";
    for (NSURL *url in urls) {
        NSString *path = url.path;
        log = [log stringByAppendingFormat:@"加载 %@:", path.lastPathComponent];
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

    // 移除自动下载 PersistenceHelper 的逻辑，改为首次启动提示
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
                         "  • TrollStore Helper integrated (本地文件安装模式)\n\n"
                         "Long-press the status bar for settings.\n\n"
                         "⚠️ 注意: 安装 TrollStore 需要手动下载文件:\n"
                         "1. TrollStore.tar - 主程序\n"
                         "2. PersistenceHelper_Embedded.tipa - 持久化助手\n"
                         "请从 GitHub (opa334/TrollStore) 下载到文件 App"
                preferredStyle:UIAlertControllerStyleAlert];
            [welcome addAction:[UIAlertAction actionWithTitle:@"Let's go!" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                [SpringBoard.sharedApplication showInjectedAlert];
            }]];
            UIWindow *keyWindow = getKeyWindow();
            [keyWindow.rootViewController presentViewController:welcome animated:YES completion:nil];
        }
    });
}
