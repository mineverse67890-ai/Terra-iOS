#import "DownloadCenterHost.h"
#import "DownloadHistoryViewController.h"
#import "DownloadTaskItem.h"
#import "DownloadTaskManager.h"

@interface TerraDownloadCenterHostController : UIViewController
+ (instancetype)makeHostWithTasksProvider:(NSArray<NSDictionary<NSString *, id> *> *(^)(void))tasksProvider
                            actionHandler:(void (^)(NSString *action, NSString *taskId))actionHandler;
- (void)downloadManagerDidUpdate:(NSNotification *)notification;
@end

static void TerraSwitchDownloadSource(DownloadTaskManager *manager,
                                     NSString *taskId,
                                     NSString *source,
                                     UIViewController *presenter) {
    __weak UIViewController *weakPresenter = presenter;
    [manager switchDownloadSourceForTaskId:taskId
                                  toSource:source
                                completion:^(BOOL shouldRecreate, BOOL supportsResume, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            UIViewController *strongPresenter = weakPresenter;
            if (!strongPresenter) return;
            if (error) {
                UIAlertController *alert = [UIAlertController
                    alertControllerWithTitle:@"Unable to switch download source"
                                     message:error.localizedDescription
                              preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                                         style:UIAlertActionStyleDefault
                                                       handler:nil]];
                [strongPresenter presentViewController:alert animated:YES completion:nil];
                return;
            }

            void (^resetTask)(void) = ^{
                [manager cancelTaskWithId:taskId];
                [manager removeTaskWithId:taskId];
            };
            if (supportsResume) {
                resetTask();
                return;
            }

            UIAlertController *confirmation = [UIAlertController
                alertControllerWithTitle:@"Switch download source"
                                 message:@"This task cannot resume. Switching sources will cancel and remove it."
                          preferredStyle:UIAlertControllerStyleAlert];
            [confirmation addAction:[UIAlertAction actionWithTitle:@"Keep Current Task"
                                                            style:UIAlertActionStyleCancel
                                                          handler:nil]];
            [confirmation addAction:[UIAlertAction actionWithTitle:@"Switch Source"
                                                            style:UIAlertActionStyleDestructive
                                                          handler:^(__unused UIAlertAction *action) {
                resetTask();
            }]];
            [strongPresenter presentViewController:confirmation animated:YES completion:nil];
            (void)shouldRecreate;
        });
    }];
}

UIViewController *TerraDownloadCenterViewControllerMake(void) {
    DownloadTaskManager *manager = [DownloadTaskManager sharedManager];
    __block __weak TerraDownloadCenterHostController *weakHost = nil;

    TerraDownloadCenterHostController *host =
        [TerraDownloadCenterHostController makeHostWithTasksProvider:^NSArray<NSDictionary<NSString *, id> *> *{
            NSArray<DownloadTaskItem *> *tasks = [[manager allTasks] sortedArrayUsingComparator:
                ^NSComparisonResult(DownloadTaskItem *first, DownloadTaskItem *second) {
                    return [second.createdDate compare:first.createdDate];
                }];
            NSMutableArray<NSDictionary<NSString *, id> *> *items = [NSMutableArray arrayWithCapacity:tasks.count];
            for (DownloadTaskItem *task in tasks) {
                [items addObject:@{
                    @"taskId": task.taskId ?: @"",
                    @"displayName": task.displayName.length > 0 ? task.displayName : task.resourceName ?: @"Download",
                    @"resourceType": task.resourceType ?: @"",
                    @"downloadSource": task.downloadSource ?: @"official",
                    @"state": @(task.state),
                    @"progress": @(task.progress),
                    @"totalSize": @(task.totalSize),
                    @"downloadedSize": @(task.downloadedSize),
                    @"speed": @(task.speed),
                    @"estimatedTimeRemaining": @(task.estimatedTimeRemaining),
                    @"supportsResume": @(task.supportsResume),
                    @"canRetry": @(task.retryHandler != nil && !task.needsRecreate && task.retryCount < task.maxRetryCount),
                    @"errorMessage": task.errorInfo.localizedDescription ?: @"",
                }];
            }
            return items;
        } actionHandler:^(NSString *action, NSString *taskId) {
            if ([action isEqualToString:@"history"]) {
                DownloadHistoryViewController *history = [[DownloadHistoryViewController alloc] init];
                UINavigationController *navigationController =
                    [[UINavigationController alloc] initWithRootViewController:history];
                navigationController.modalPresentationStyle = UIModalPresentationPageSheet;
                [weakHost presentViewController:navigationController animated:YES completion:nil];
                return;
            }
            if (taskId.length == 0) return;
            if ([action hasPrefix:@"source:"]) {
                NSString *source = [action substringFromIndex:@"source:".length];
                TerraSwitchDownloadSource(manager, taskId, source, weakHost);
            } else if ([action isEqualToString:@"pause"]) {
                [manager pauseTaskWithId:taskId];
            } else if ([action isEqualToString:@"resume"]) {
                [manager resumeTaskWithId:taskId];
            } else if ([action isEqualToString:@"cancel"]) {
                [manager cancelTaskWithId:taskId];
            } else if ([action isEqualToString:@"retry"]) {
                [manager retryTaskWithId:taskId];
            } else if ([action isEqualToString:@"remove"]) {
                [manager removeTaskWithId:taskId];
            }
        }];
    weakHost = host;
    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    [notificationCenter addObserver:host
                           selector:@selector(downloadManagerDidUpdate:)
                               name:DownloadTaskManagerDidUpdateTaskNotification
                             object:nil];
    [notificationCenter addObserver:host
                           selector:@selector(downloadManagerDidUpdate:)
                               name:DownloadTaskManagerAggregateStateDidChangeNotification
                             object:nil];
    return host;
}
