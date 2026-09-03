#import "ABMCClickManager.h"

static const uint64_t kABMCClickRecognitionWindow = 240 * NSEC_PER_MSEC;

@implementation ABMCClickManager {
    NSInteger _clickCount;
    dispatch_source_t _timer;
    dispatch_queue_t _queue;
    uint64_t _callbackGeneration;
}

+ (instancetype)sharedManager {
    static ABMCClickManager *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ABMCClickManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _clickCount = 0;
        _callbackGeneration = 0;
        _queue = dispatch_queue_create("com.huynguyen.abmc.clickqueue", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)registerClick {
    dispatch_async(_queue, ^{
        [self _cancelTimer];
        self->_clickCount++;

        if (self->_clickCount >= 2) {
            // The second release confirms a double click: fire it immediately.
            self->_clickCount = 0;
            [self _fireCallbackForCount:2 generation:self->_callbackGeneration];
            return;
        }

        // The first release starts the single/double-click recognition window.
        [self _startTimer];
    });
}

- (void)cancelPendingClicks {
    dispatch_sync(_queue, ^{
        // Invalidate callbacks that have left this queue but not reached main.
        self->_callbackGeneration++;
        [self _cancelTimer];
        self->_clickCount = 0;
    });
}

- (void)_startTimer {
    _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _queue);
    dispatch_source_set_timer(_timer,
                              dispatch_time(DISPATCH_TIME_NOW, kABMCClickRecognitionWindow),
                              DISPATCH_TIME_FOREVER,
                              0);
    dispatch_source_set_event_handler(_timer, ^{
        NSInteger count = self->_clickCount;
        uint64_t generation = self->_callbackGeneration;
        self->_clickCount = 0;
        [self _cancelTimer];
        [self _fireCallbackForCount:count generation:generation];
    });
    dispatch_resume(_timer);
}

- (void)_cancelTimer {
    if (_timer) {
        dispatch_source_cancel(_timer);
        _timer = nil;
    }
}

- (void)_fireCallbackForCount:(NSInteger)count generation:(uint64_t)generation {
    if (count < 1 || count > 2 || !self.clickCallback) return;

    ABMCClickCallback callback = [self.clickCallback copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        dispatch_async(self->_queue, ^{
            if (generation != self->_callbackGeneration) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                callback((ABMCClickType)count);
            });
        });
    });
}

@end
