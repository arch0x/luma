#import <Foundation/Foundation.h>

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSArray<NSString *> *titles = @[@"设计文档", @"实验记录"];
        for (NSString *title in titles) {
            NSLog(@"继续阅读：%@", title);
        }
    }
    return 0;
}
