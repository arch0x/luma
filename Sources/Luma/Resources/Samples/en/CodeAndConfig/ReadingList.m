#import <Foundation/Foundation.h>

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSArray<NSString *> *titles = @[@"Design notes", @"Lab notes"];
        for (NSString *title in titles) {
            NSLog(@"Continue reading: %@", title);
        }
    }
    return 0;
}
