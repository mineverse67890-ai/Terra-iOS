//
//  AmeRootTabController.h
//  ★ [ROOTTAB] 把 App 根换成【真正的 UITabBarController】——音乐 / LiveContainer /
//  SideStore 都是这个结构:根 = 标签栏控制器,页面在其上,系统自己画底栏
//  (玻璃 / 高度 / 圆角 / 竖横屏适配全交给系统)。
//
//  为什么必须当根(而不是塞进某个小容器):
//    iOS 26 的标签栏只有在【控制器拥有全屏】时才走标准形态;塞进 68/92pt 的小容器
//    会被判定为紧凑环境 ⇒ 标题被摆到图标右边、并退化成实底(用户截图:纯黑、不半透)。
//
#import <UIKit/UIKit.h>

/// 标签被点:userInfo = @{@"index": @(0…3)}。LauncherMenuViewController 监听后
/// 直接调用已有的 handleMenuSelection: —— 导航语义一个字不变。
extern NSString * const AmeTabTappedNotification;

@interface AmeRootTabController : UITabBarController
/// 用给定主页(内容)建控制器:4 个标签 = 实例 / 下载 / 资源 / 设置。
/// 实例页承载主页内容(LauncherRootViewController 或 CardLayout)，下载、资源和设置各自显示对应页面。
+ (instancetype)tabControllerWithHomeViewController:(UIViewController *)home;
@end
