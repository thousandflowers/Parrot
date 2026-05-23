// macOS 26+ NSHostingView bug: updateConstraints → updateWindowContentSizeExtremaIfNecessary
// → re-entrant setNeedsUpdateConstraints → _postWindowNeedsUpdateConstraints throws
// NSGenericException → AppKit's display-cycle observer calls objc_exception_rethrow → SIGABRT.
//
// Root fix: swizzle -[NSView setNeedsUpdateConstraints:] to detect per-window re-entrancy
// and DEFER the call (not drop it) until after the current constraint pass completes.
// This applies to ALL NSHostingView instances — including system-owned status-bar windows —
// without subclassing. The @try/@catch on updateConstraintsIfNeeded / layoutIfNeeded is a
// safety net for any exception that slips through.

#import <AppKit/AppKit.h>
#import <objc/runtime.h>

// Windows currently inside updateConstraintsIfNeeded or layoutIfNeeded (main thread only).
static NSMutableSet<NSNumber *> *_parrot_windowsInPass;

static BOOL _parrot_isConstraintLoopException(NSException *e) {
    if (![e.name isEqualToString:NSGenericException]) return NO;
    NSString *r = e.reason;
    return r != nil && ([r containsString:@"Update Constraints"] ||
                        [r containsString:@"marked as needing"]);
}

static void _parrot_swizzle(Class cls, SEL orig, SEL repl) {
    Method m = class_getInstanceMethod(cls, orig);
    Method r = class_getInstanceMethod(cls, repl);
    if (m && r) method_exchangeImplementations(m, r);
}

static inline NSNumber *_parrot_wkey(NSWindow *w) {
    return @((uintptr_t)(__bridge void *)w);
}

// ---------------------------------------------------------------------------
// NSWindow — track which windows are in a constraint/layout pass

@implementation NSWindow (ParrotConstraintLoopFix)

+ (void)load {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        _parrot_windowsInPass = [NSMutableSet new];
        _parrot_swizzle([NSWindow class],
                        @selector(updateConstraintsIfNeeded),
                        @selector(_parrot_ucin));
        _parrot_swizzle([NSWindow class],
                        @selector(layoutIfNeeded),
                        @selector(_parrot_lin));
        _parrot_swizzle([NSView class],
                        @selector(setNeedsUpdateConstraints:),
                        @selector(_parrot_setNUC:));
    });
}

- (void)_parrot_ucin {
    NSNumber *k = _parrot_wkey(self);
    [_parrot_windowsInPass addObject:k];
    @try { [self _parrot_ucin]; }
    @catch (NSException *e) { if (!_parrot_isConstraintLoopException(e)) @throw; }
    @finally { [_parrot_windowsInPass removeObject:k]; }
}

- (void)_parrot_lin {
    NSNumber *k = _parrot_wkey(self);
    [_parrot_windowsInPass addObject:k];
    @try { [self _parrot_lin]; }
    @catch (NSException *e) { if (!_parrot_isConstraintLoopException(e)) @throw; }
    @finally { [_parrot_windowsInPass removeObject:k]; }
}

@end

// ---------------------------------------------------------------------------
// NSView — defer re-entrant setNeedsUpdateConstraints: calls

@implementation NSView (ParrotConstraintLoopFix)

- (void)_parrot_setNUC:(BOOL)flag {
    if (flag) {
        NSWindow *w = self.window;
        if (w && [_parrot_windowsInPass containsObject:_parrot_wkey(w)]) {
            // Re-entrant: defer until after the current pass so AppKit accepts it.
            __weak NSView *weak = self;
            dispatch_async(dispatch_get_main_queue(), ^{
                [weak setNeedsUpdateConstraints:YES];
            });
            return;
        }
    }
    // Not re-entrant — call original (swizzled selector holds original IMP).
    [self _parrot_setNUC:flag];
}

@end
