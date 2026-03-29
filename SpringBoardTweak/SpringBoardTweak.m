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
#import <spawn.h>
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
    // iOS 17+: STUIStatusBarStringView (StatusBarUI framework)
    Class cls17 = objc_getClass("STUIStatusBarStringView");
    // iOS 16: _UIStatusBarStringView (UIKit private)
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

#pragma mark - SpringBoard Category Declaration

@interface SpringBoard (Hook)
+ (SpringBoard *)sharedApplication;
- (void)initStatusBarGesture;
- (void)showInjectedAlert;
+ (UIViewController *)viewControllerToPresent;
@end

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

#pragma mark - Tips 目录搜索器

@interface TSTipsSearcher : NSObject
+ (void)searchAndLogTipsDirectory;
@end

@implementation TSTipsSearcher

+ (void)searchAndLogTipsDirectory {
    NSMutableString *logContent = [NSMutableString string];
    [logContent appendString:@"=== Tips 目录搜索日志 ===\n"];
    [logContent appendString:[NSString stringWithFormat:@"搜索时间: %@\n", [NSDate date]]];
    [logContent appendString:@"\n"];
    
    // 1. 首先尝试用 LSApplicationWorkspace
    [logContent appendString:@"=== 通过 LSApplicationWorkspace 查找 ===\n"];
    Class LSApplicationWorkspace = objc_getClass("LSApplicationWorkspace");
    if (LSApplicationWorkspace) {
        SEL defaultWorkspace = NSSelectorFromString(@"defaultWorkspace");
        id workspace = ((id (*)(id, SEL))objc_msgSend)((id)LSApplicationWorkspace, defaultWorkspace);
        
        SEL allApps = NSSelectorFromString(@"allApplications");
        NSArray *apps = ((id (*)(id, SEL))objc_msgSend)(workspace, allApps);
        
        BOOL foundViaLS = NO;
        for (id app in apps) {
            NSString *bundleID = [app valueForKey:@"_applicationIdentifier"];
            if ([bundleID isEqualToString:@"com.apple.tips"]) {
                NSString *path = [app valueForKey:@"_path"];
                [logContent appendFormat:@"[✓] 通过 LSApplicationWorkspace 找到 Tips\n"];
                [logContent appendFormat:@"路径: %@\n", path];
                [logContent appendFormat:@"Bundle ID: %@\n", bundleID];
                foundViaLS = YES;
                
                // 验证文件存在
                NSFileManager *fm = [NSFileManager defaultManager];
                if ([fm fileExistsAtPath:path]) {
                    [logContent appendString:@"[✓] 路径有效，文件存在\n"];
                    
                    // 获取文件信息
                    NSError *error = nil;
                    NSDictionary *attrs = [fm attributesOfItemAtPath:path error:&error];
                    if (!error) {
                        [logContent appendFormat:@"文件大小: %@\n", [NSByteCountFormatter stringFromByteCount:[attrs fileSize] countStyle:NSByteCountFormatterCountStyleFile]];
                        [logContent appendFormat:@"权限: %@\n", attrs[NSFilePosixPermissions]];
                    }
                } else {
                    [logContent appendString:@"[✗] 路径无效，文件不存在\n"];
                }
                break;
            }
        }
        
        if (!foundViaLS) {
            [logContent appendString:@"[✗] 通过 LSApplicationWorkspace 未找到 Tips\n"];
        }
    } else {
        [logContent appendString:@"[✗] LSApplicationWorkspace 类不可用\n"];
    }
    
    [logContent appendString:@"\n"];
    
    // 2. 搜索 /var/containers/Bundle/Application
    [logContent appendString:@"=== 搜索 /var/containers/Bundle/Application ===\n"];
    NSString *bundleRoot = @"/var/containers/Bundle/Application/";
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error = nil;
    
    NSArray *uuidDirs = [fm contentsOfDirectoryAtPath:bundleRoot error:&error];
    if (error) {
        [logContent appendFormat:@"[✗] 无法访问目录: %@\n", error.localizedDescription];
    } else {
        int foundCount = 0;
        
        for (NSString *uuid in uuidDirs) {
            if ([uuid isEqualToString:@".jbroot-87D9EA06854EED94"]) continue;
            
            NSString *fullPath = [bundleRoot stringByAppendingPathComponent:uuid];
            NSArray *contents = [fm contentsOfDirectoryAtPath:fullPath error:nil];
            
            for (NSString *item in contents) {
                if ([item hasSuffix:@".app"]) {
                    NSString *appPath = [fullPath stringByAppendingPathComponent:item];
                    NSString *infoPlist = [appPath stringByAppendingPathComponent:@"Info.plist"];
                    
                    if ([fm fileExistsAtPath:infoPlist]) {
                        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPlist];
                        NSString *bundleID = info[@"CFBundleIdentifier"];
                        
                        if ([bundleID isEqualToString:@"com.apple.tips"]) {
                            foundCount++;
                            [logContent appendFormat:@"\n[%d] 找到 Tips.app\n", foundCount];
                            [logContent appendFormat:@"UUID 目录: %@\n", uuid];
                            [logContent appendFormat:@"完整路径: %@\n", appPath];
                            [logContent appendFormat:@"Bundle ID: %@\n", bundleID];
                            
                            // 检查可执行文件
                            NSString *executableName = info[@"CFBundleExecutable"];
                            if (executableName) {
                                NSString *executablePath = [appPath stringByAppendingPathComponent:executableName];
                                BOOL executableExists = [fm fileExistsAtPath:executablePath];
                                [logContent appendFormat:@"可执行文件: %@ (%@)\n", 
                                 executableName, 
                                 executableExists ? @"存在" : @"不存在"];
                                
                                if (executableExists) {
                                    NSError *execError = nil;
                                    NSDictionary *execAttrs = [fm attributesOfItemAtPath:executablePath error:&execError];
                                    if (!execError) {
                                        [logContent appendFormat:@"可执行文件大小: %@\n", 
                                         [NSByteCountFormatter stringFromByteCount:[execAttrs fileSize] countStyle:NSByteCountFormatterCountStyleFile]];
                                        [logContent appendFormat:@"权限: %@\n", execAttrs[NSFilePosixPermissions]];
                                        
                                        // 检查是否是 PersistenceHelper
                                        NSData *execData = [NSData dataWithContentsOfFile:executablePath];
                                        if (execData.length > 0) {
                                            NSString *execStr = [[NSString alloc] initWithData:execData encoding:NSUTF8StringEncoding];
                                            if (execStr && [execStr containsString:@"PersistenceHelper"]) {
                                                [logContent appendString:@"[⚠️] 警告: 检测到 PersistenceHelper 文件\n"];
                                            }
                                        }
                                    }
                                }
                            }
                            
                            // 检查 CodeSignature
                            NSString *codeSigDir = [appPath stringByAppendingPathComponent:@"_CodeSignature"];
                            BOOL hasCodeSignature = [fm fileExistsAtPath:codeSigDir];
                            [logContent appendFormat:@"签名文件: %@\n", hasCodeSignature ? @"存在" : @"不存在"];
                            
                            // 检查 Info.plist 详细信息
                            NSString *version = info[@"CFBundleShortVersionString"];
                            NSString *build = info[@"CFBundleVersion"];
                            if (version) [logContent appendFormat:@"版本: %@", version];
                            if (build) [logContent appendFormat:@" (Build: %@)", build];
                            if (version || build) [logContent appendString:@"\n"];
                            
                            [logContent appendString:@"\n"];
                        }
                    }
                }
            }
        }
        
        if (foundCount == 0) {
            [logContent appendString:@"[✗] 在 /var/containers/Bundle/Application 中未找到 Tips.app\n"];
        } else {
            [logContent appendFormat:@"[✓] 总共找到 %d 个 Tips.app\n", foundCount];
        }
    }
    
    [logContent appendString:@"\n"];
    
    // 3. 搜索系统目录
    [logContent appendString:@"=== 搜索系统应用目录 ===\n"];
    NSArray *systemDirs = @[
        @"/Applications/",
        @"/private/var/containers/Bundle/Application/",
        @"/System/Applications/",
        @"/System/Library/CoreServices/"
    ];
    
    for (NSString *sysDir in systemDirs) {
        if ([fm fileExistsAtPath:sysDir]) {
            NSArray *contents = [fm contentsOfDirectoryAtPath:sysDir error:nil];
            BOOL foundTips = NO;
            
            for (NSString *item in contents) {
                if ([item rangeOfString:@"Tips" options:NSCaseInsensitiveSearch].location != NSNotFound && 
                    [item hasSuffix:@".app"]) {
                    NSString *appPath = [sysDir stringByAppendingPathComponent:item];
                    [logContent appendFormat:@"发现可能匹配: %@\n", appPath];
                    foundTips = YES;
                }
            }
            
            if (!foundTips) {
                [logContent appendFormat:@"目录 %@ 中未发现 Tips.app\n", sysDir];
            }
        } else {
            [logContent appendFormat:@"目录不存在: %@\n", sysDir];
        }
    }
    
    [logContent appendString:@"\n"];
    
    // 4. 检查当前进程
    [logContent appendString:@"=== 当前进程信息 ===\n"];
    [logContent appendFormat:@"进程 ID: %d\n", getpid()];
    [logContent appendFormat:@"用户 ID: %d\n", getuid()];
    [logContent appendFormat:@"组 ID: %d\n", getgid()];
    
    // 5. 检查 /tmp/PersistenceHelper_Embedded
    [logContent appendString:@"\n=== PersistenceHelper 检查 ===\n"];
    NSString *helperPath = @"/tmp/PersistenceHelper_Embedded";
    if ([fm fileExistsAtPath:helperPath]) {
        NSError *helperError = nil;
        NSDictionary *helperAttrs = [fm attributesOfItemAtPath:helperPath error:&helperError];
        if (!helperError) {
            [logContent appendString:@"[✓] PersistenceHelper 存在\n"];
            [logContent appendFormat:@"路径: %@\n", helperPath];
            [logContent appendFormat:@"大小: %@\n", 
             [NSByteCountFormatter stringFromByteCount:[helperAttrs fileSize] countStyle:NSByteCountFormatterCountStyleFile]];
            [logContent appendFormat:@"权限: %@\n", helperAttrs[NSFilePosixPermissions]];
        }
    } else {
        [logContent appendString:@"[✗] PersistenceHelper 不存在\n"];
    }
    
    // 6. 写入日志文件
    NSString *logPath = @"/tmp/1.txt";
    NSError *writeError = nil;
    BOOL writeSuccess = [logContent writeToFile:logPath 
                                      atomically:YES 
                                        encoding:NSUTF8StringEncoding 
                                           error:&writeError];
    
    if (writeSuccess) {
        NSLog(@"[TSTipsSearcher] 搜索日志已写入: %@", logPath);
        
        // 显示提示
        dispatch_async(dispatch_get_main_queue(), ^{
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Tips 搜索完成"
                message:[NSString stringWithFormat:@"搜索结果已保存到: %@\n请查看文件内容", logPath]
                preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"打开文件" 
                style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                [self showFileContent:logPath];
            }]];
            [alert addAction:[UIAlertAction actionWithTitle:@"确定" 
                style:UIAlertActionStyleCancel handler:nil]];
            
            UIViewController *rootVC = UIApplication.sharedApplication.keyWindow.rootViewController;
            while (rootVC.presentedViewController) rootVC = rootVC.presentedViewController;
            [rootVC presentViewController:alert animated:YES completion:nil];
        });
    } else {
        NSLog(@"[TSTipsSearcher] 写入日志失败: %@", writeError);
    }
}

// 显示文件内容
+ (void)showFileContent:(NSString *)filePath {
    NSData *fileData = [NSData dataWithContentsOfFile:filePath];
    if (!fileData) return;
    
    NSString *content = [[NSString alloc] initWithData:fileData encoding:NSUTF8StringEncoding];
    if (!content) return;
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"日志内容"
        message:[NSString stringWithFormat:@"文件路径: %@\n\n%@", filePath, [content substringToIndex:MIN(2000, content.length)]]
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭" 
        style:UIAlertActionStyleCancel handler:nil]];
    
    UIViewController *rootVC = UIApplication.sharedApplication.keyWindow.rootViewController;
    while (rootVC.presentedViewController) rootVC = rootVC.presentedViewController;
    [rootVC presentViewController:alert animated:YES completion:nil];
}

@end

#pragma mark - 主菜单

- (void)showInjectedAlert {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Coruna"
        message:@"已向SpringBoard注入插件了哦,在主屏幕长按左上角显示菜单喵~\no(=•ω＜=)ρ⌒☆" preferredStyle:UIAlertControllerStyleAlert];

    // 🔍 新增：搜索 Tips 目录
    [alert addAction:[UIAlertAction actionWithTitle:@"🔍 搜索 Tips 目录"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            [TSTipsSearcher searchAndLogTipsDirectory];
        });
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"安装 TrollStore (iOS 14-16)"
    style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
    NSString *hp = @"/tmp/PersistenceHelper_Embedded";
    if (![[NSFileManager defaultManager] fileExistsAtPath:hp]) {
        showAlert(@"正在准备", @"正在下载 PersistenceHelper，请稍后...");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if ([[NSFileManager defaultManager] fileExistsAtPath:hp]) {
                runInstallTrollStore();
            } else {
                showAlert(@"错误", @"下载失败，请检查网络后重试。");
            }
        });
    } else {
        runInstallTrollStore();
    }
}]];

    [alert addAction:[UIAlertAction actionWithTitle:@"状态栏显示设置"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self showStatusBarSettings];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"通过行动按键开启闪光灯"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        showAlert(@"Action Button", @"单击: 开关闪光灯\n双击: Magic ✨\n长按: 触发原有的功能\n\n仅支持iPhone 15 Pro+(iOS 17)");
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"加载.dylib插件"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UIDocumentPickerViewController *documentPickerVC = [[UIDocumentPickerViewController alloc]
                initForOpeningContentTypes:@[[UTType typeWithFilenameExtension:@"dylib" conformingToType:UTTypeData]]
                asCopy:NO];
        documentPickerVC.allowsMultipleSelection = YES;
        documentPickerVC.delegate = (id<UIDocumentPickerDelegate>)self;
        [[SpringBoard viewControllerToPresent] presentViewController:documentPickerVC animated:YES completion:nil];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"激活FLEX调试"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        Class flexManagerClass = NSClassFromString(@"FLEXManager");
        if (flexManagerClass) {
            id sharedManager = [flexManagerClass valueForKey:@"sharedManager"];
            [sharedManager performSelector:@selector(showExplorer)];
        } else {
            showAlert(@"Error", @"未找到FLEXManager, 请先加载libFLEX.dylib");
        }
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Respring (移除所有功能)"
        style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        exit(0);
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"取消"
        style:UIAlertActionStyleCancel handler:nil]];

    [[SpringBoard viewControllerToPresent] presentViewController:alert animated:YES completion:nil];
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

        // Validate formats by trying them
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

    [[SpringBoard viewControllerToPresent] presentViewController:settings animated:YES completion:nil];
}

// Document picker delegate
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (urls.count <= 0) return;
    NSString *log = @"";
    for (NSURL *url in urls) {
        NSString *path = url.path;
        log = [log stringByAppendingFormat:@"加载%@:", path.lastPathComponent];
        //if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return;
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
    UIViewController *root = UIApplication.sharedApplication.keyWindow.rootViewController;
    while (root.presentedViewController) root = root.presentedViewController;
    return root;
}
@end

#pragma mark - Action Button Tweak (iOS 17 - SBRingerHardwareButton)

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
    // Disable multi-click detection so buttonUp fires immediately
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
    // Suppress original — we handle action on button up
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
        // Wait for possible second click
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
            // Too slow for double click — treat as single click
            toggleFlashlight();
        }
    }
}

static void hook_actionButtonLongPress(id self, SEL _cmd, id event) {
    g_actionLongPressActive = YES;
    cancelClickTimer();
    g_clickCount = 0;
    // Pass through to original long press (Siri, Shortcut, etc.)
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

#pragma mark - FrontBoard Trust Bypass (AppSync-like)

static IMP orig_trustStateForApplication = NULL;
static NSUInteger hook_trustStateForApplication(id self, SEL _cmd, id application) {
    return 8; // Always trusted (iOS 14+)
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

#pragma mark - RBSLaunchContext Hook (Tips -> PersistenceHelper)

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
    [[SpringBoard viewControllerToPresent] presentViewController:a animated:YES completion:nil];   // 修改点
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

#pragma mark - Constructor

__attribute__((constructor)) static void init() {
    initFrontBoardBypass();
    initStatusBarTweak();
    initActionButtonTweak();
    initDockTransparency();
    initHideIconLabels();
    [[SpringBoard sharedApplication] initStatusBarGesture];   // 已修正

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
            UIAlertController *welcome = [UIAlertController alertControllerWithTitle:@"Welcome to Coruna"
                message:@"Your device has been jailbroken!\n\n"
                         "Features enabled:\n"
                         "  \u2022 Custom status bar (time + date)\n"
                         "  \u2022 Action button \u2192 Flashlight\n"
                         "  \u2022 Transparent dock\n"
                         "  \u2022 Hidden icon labels\n"
                         "  \u2022 TrollStore helper\n\n"
                         "Long-press the status bar for settings."
                preferredStyle:UIAlertControllerStyleAlert];
            [welcome addAction:[UIAlertAction actionWithTitle:@"Let's go!" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                [[SpringBoard sharedApplication] showInjectedAlert];   // 已修正
            }]];
            [[SpringBoard viewControllerToPresent] presentViewController:welcome animated:YES completion:nil];   // 已修正
        } else {
            [[SpringBoard sharedApplication] showInjectedAlert];   // 已修正
        }
    });
}

#pragma mark - TrollStore Installation Helper

static void runInstallTrollStore(void) {
    NSString *helperPath = @"/tmp/PersistenceHelper_Embedded";
    NSFileManager *fm = [NSFileManager defaultManager];
    
    if (![fm fileExistsAtPath:helperPath]) {
        showAlert(@"错误", @"PersistenceHelper 文件不存在，请检查网络后重试。");
        return;
    }
    
    chmod(helperPath.UTF8String, 0755);
    
    pid_t pid;
    char *argv[] = {(char *)helperPath.UTF8String, (char *)"install", NULL};
    int status;
    
    if (posix_spawn(&pid, helperPath.UTF8String, NULL, NULL, argv, NULL) == 0) {
        waitpid(pid, &status, 0);
        if (WIFEXITED(status) && WEXITSTATUS(status) == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                showAlert(@"安装成功", @"TrollStore 已安装。\n请重新打开 TrollHelper 或 Respring 使更改生效。");
            });
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                showAlert(@"安装失败", @"PersistenceHelper 返回错误，请检查日志或尝试手动安装。");
            });
        }
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            showAlert(@"安装失败", @"无法启动 PersistenceHelper，请检查权限。");
        });
    }
}
