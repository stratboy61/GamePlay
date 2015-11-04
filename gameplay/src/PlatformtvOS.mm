#ifdef __APPLE__

#include "Base.h"
#include "Platform.h"
#include "FileSystem.h"
#include "Game.h"
#include "Form.h"
#include "ScriptController.h"
#include <unistd.h>
#import <UIKit/UIKit.h>
#import <UIKit/UIGestureRecognizerSubclass.h>
#import <QuartzCore/QuartzCore.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/EAGLDrawable.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>
#import <mach/mach_time.h>

//#define FACEBOOK_SDK
#ifdef FACEBOOK_SDK
#import <FacebookSDK/FacebookSDK.h>
#endif

#define UIInterfaceOrientationEnum(x) ([x isEqualToString:@"UIInterfaceOrientationPortrait"]?UIInterfaceOrientationPortrait:			    \
				      ([x isEqualToString:@"UIInterfaceOrientationPortraitUpsideDown"]?UIInterfaceOrientationPortraitUpsideDown:    \
				      ([x isEqualToString:@"UIInterfaceOrientationLandscapeLeft"]?UIInterfaceOrientationLandscapeLeft:		    \
					UIInterfaceOrientationLandscapeRight)))

using namespace gameplay;

int __argc = 0;
char** __argv = 0;

@class AppDelegate;
@class View;

static AppDelegate *__appDelegate = NULL;
static View* __view = NULL;

class TouchPoint
{
public:
    unsigned int hashId;
    int x;
    int y;
    bool down;

    TouchPoint()
    {
	hashId = 0;
	x = 0;
	y = 0;
	down = false;
    }
};

// more than we'd ever need, to be safe
#define TOUCH_POINTS_MAX (10)
static TouchPoint __touchPoints[TOUCH_POINTS_MAX];

static double __timeStart;
static double __timeAbsolute;
static bool __vsync = WINDOW_VSYNC;
static float __pitch;
static float __roll;


std::vector<FbBundle>	    Platform::m_notifications;
std::vector<std::string>    Platform::m_permissions;
FacebookListener*	    Platform::m_fbListener = NULL;
Platform::MemoryWarningFunc Platform::m_memoryWarningFunc = NULL;

double getMachTimeInMilliseconds();

int getKey(unichar keyCode);
int getUnicode(int key);

@class ViewController;

@interface AppDelegate : UIApplication <UIApplicationDelegate>
{
    UIWindow* window;
    ViewController* viewController;
    //CMMotionManager *motionManager;
}
// FBSample logic
// In this sample the app delegate maintains a property for the current
// active session, and the view controllers reference the session via
// this property, as well as play a role in keeping the session object
// up to date; a more complicated application may choose to introduce
// a simple singleton that owns the active FBSession object as well
// as access to the object by the rest of the application
#ifdef FACEBOOK_SDK
@property (strong, nonatomic) FBSession *session;
#endif
@property (nonatomic, retain) ViewController *viewController;
@end

@interface View : UIView <UIKeyInput>
{
    EAGLContext* context;
    CADisplayLink* displayLink;
    BOOL updateFramebuffer;
    GLuint defaultFramebuffer;
    GLuint colorRenderbuffer;
    GLuint depthRenderbuffer;
    GLuint stencilRenderbuffer;
    GLint framebufferWidth;
    GLint framebufferHeight;
    GLuint multisampleFramebuffer;
    GLuint multisampleRenderbuffer;
    GLuint multisampleDepthbuffer;
    NSInteger swapInterval;
    BOOL updating;
    Game* game;
    BOOL oglDiscardSupported;

    UITapGestureRecognizer *_tapRecognizer;
    UITapGestureRecognizer *_doubleTapRecognizer;
    //UIPinchGestureRecognizer *_pinchRecognizer;
    UISwipeGestureRecognizer *_swipeRightRecognizer;
    UISwipeGestureRecognizer *_swipeLeftRecognizer;
    UISwipeGestureRecognizer *_swipeUpRecognizer;
    UISwipeGestureRecognizer *_swipeDownRecognizer;
}

@property (readonly, nonatomic, getter=isUpdating) BOOL updating;
@property (readonly, nonatomic, getter=getContext) EAGLContext* context;

- (void)startGame;
- (void)startUpdating;
- (void)stopUpdating;
- (void)update:(id)sender;
- (void)setSwapInterval:(NSInteger)interval;
- (int)swapInterval;
- (void)swapBuffers;
- (BOOL)showKeyboard;
- (BOOL)dismissKeyboard;
@end

@interface View (Private)
- (BOOL)createFramebuffer;
- (void)deleteFramebuffer;
@end

@implementation View

@synthesize updating;
@synthesize context;

+ (Class) layerClass
{
    return [CAEAGLLayer class];
}

- (id) initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame]))
    {
        // A system version of 3.1 or greater is required to use CADisplayLink.
        NSString *reqSysVer = @"3.1";
        NSString *currSysVer = [[UIDevice currentDevice] systemVersion];
        if ([currSysVer compare:reqSysVer options:NSNumericSearch] != NSOrderedAscending) {
            // Log the system version
            NSLog(@"System Version: %@", currSysVer);
        }
        else {
            GP_ERROR("Invalid OS Version: %s\n", (currSysVer == NULL?"NULL":[currSysVer cStringUsingEncoding:NSASCIIStringEncoding]));
            [self release];
            return nil;
        }

        // Check for OS 4.0+ features
        if ([currSysVer compare:@"4.0" options:NSNumericSearch] != NSOrderedAscending) {
            oglDiscardSupported = YES;
        } else {
            oglDiscardSupported = NO;
        }

        NSString* bundlePath = [[[NSBundle mainBundle] bundlePath] stringByAppendingString:@"/"];
        FileSystem::setResourcePath([bundlePath fileSystemRepresentation]);
        
        const CGFloat mainScreenScale = [[UIScreen mainScreen] scale];
        if (mainScreenScale > 1.0) {
            
            const Vector2 deviceOrientedSize = Platform::getMobileNativeResolution();
            Properties *config = Game::getInstance()->getConfig()->getNamespace("window", true); // this will read the player.config file for preferred resolution
            Platform::m_mobileScale = mainScreenScale * config->getFloat("scale");
            if (Platform::m_mobileScale < MATH_EPSILON)  {
                
                Platform::m_mobileScale = mainScreenScale;
                // we determine a default scale factor for the first use... and we target 960 for the height
                if (deviceOrientedSize.y > 960) {
                    const float scaled_height = deviceOrientedSize.y / Platform::m_mobileScale;
                    Platform::m_mobileScale = 960.0 / scaled_height;
                }
            }
            NSLog(@"Platform::m_mobileScale = %f", Platform::m_mobileScale);
        }
        
        // Configure the CAEAGLLayer and setup out the rendering context
        CAEAGLLayer* layer = (CAEAGLLayer *)self.layer;
        layer.opaque = TRUE;
        layer.drawableProperties = [NSDictionary dictionaryWithObjectsAndKeys:
                       [NSNumber numberWithBool:FALSE], kEAGLDrawablePropertyRetainedBacking,
                        kEAGLColorFormatRGBA8, kEAGLDrawablePropertyColorFormat, nil];
        self.contentScaleFactor = Platform::m_mobileScale;
        layer.contentsScale = Platform::m_mobileScale;

        context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
        if (!context || ![EAGLContext setCurrentContext:context]) {
            GP_ERROR("Failed to make context current.");
            [self release];
            return nil;
        }

        // Initialize Internal Defaults
        displayLink = nil;
        updateFramebuffer = YES;
        defaultFramebuffer = 0;
        colorRenderbuffer = 0;
        depthRenderbuffer = 0;
        stencilRenderbuffer = 0;
        framebufferWidth = 0;
        framebufferHeight = 0;
        multisampleFramebuffer = 0;
        multisampleRenderbuffer = 0;
        multisampleDepthbuffer = 0;
        swapInterval = 1;
        updating = FALSE;
        game = nil;
        
        Game::getInstance()->callPostConfigCallback();
    }
    return self;
}

- (void) dealloc
{
    if (game)
	game->exit();
    [self deleteFramebuffer];

    if ([EAGLContext currentContext] == context)
    {
	[EAGLContext setCurrentContext:nil];
    }
    [context release];
    [super dealloc];
}

- (BOOL)canBecomeFirstResponder
{
    // Override so we can control the keyboard
    return YES;
}

- (void) layoutSubviews
{
    // Called on 'resize'.
    // Mark that framebuffer needs to be updated.
    // NOTE: Current disabled since we need to have a way to reset the default frame buffer handle
    // in FrameBuffer.cpp (for FrameBuffer:bindDefault). This means that changing orientation at
    // runtime is currently not supported until we fix this.
    //updateFramebuffer = YES;
}

- (BOOL)createFramebuffer
{
    // iOS Requires all content go to a rendering buffer then it is swapped into the windows rendering surface
    assert(defaultFramebuffer == 0);

    // Create the default frame buffer
    GL_ASSERT( glGenFramebuffers(1, &defaultFramebuffer) );
    GL_ASSERT( glBindFramebuffer(GL_FRAMEBUFFER, defaultFramebuffer) );

    // Create a color buffer to attach to the frame buffer
    GL_ASSERT( glGenRenderbuffers(1, &colorRenderbuffer) );
    GL_ASSERT( glBindRenderbuffer(GL_RENDERBUFFER, colorRenderbuffer) );

    // Associate render buffer storage with CAEAGLLauyer so that the rendered content is display on our UI layer.
    [context renderbufferStorage:GL_RENDERBUFFER fromDrawable:(CAEAGLLayer *)self.layer];

    // Attach the color buffer to our frame buffer
    GL_ASSERT( glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, colorRenderbuffer) );

    // Retrieve framebuffer size
    GL_ASSERT( glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &framebufferWidth) );
    GL_ASSERT( glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &framebufferHeight) );

#ifdef DEBUG
    NSLog(@"width: %d, height: %d", framebufferWidth, framebufferHeight);
#endif
    // If multisampling is enabled in config, create and setup a multisample buffer
    Properties* config = Game::getInstance()->getConfig()->getNamespace("window", true);
    int samples = config ? config->getInt("samples") : 0;
    if (samples < 0)
	samples = 0;
    if (samples)
    {
	// Create multisample framebuffer
	GL_ASSERT( glGenFramebuffers(1, &multisampleFramebuffer) );
	GL_ASSERT( glBindFramebuffer(GL_FRAMEBUFFER, multisampleFramebuffer) );

	// Create multisample render and depth buffers
	GL_ASSERT( glGenRenderbuffers(1, &multisampleRenderbuffer) );
	GL_ASSERT( glGenRenderbuffers(1, &multisampleDepthbuffer) );

	// Try to find a supported multisample configuration starting with the defined sample count
	while (samples)
	{
	    GL_ASSERT( glBindRenderbuffer(GL_RENDERBUFFER, multisampleRenderbuffer) );
	    GL_ASSERT( glRenderbufferStorageMultisampleAPPLE(GL_RENDERBUFFER, samples, GL_RGBA8_OES, framebufferWidth, framebufferHeight) );
	    GL_ASSERT( glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, multisampleRenderbuffer) );

	    GL_ASSERT( glBindRenderbuffer(GL_RENDERBUFFER, multisampleDepthbuffer) );
	    GL_ASSERT( glRenderbufferStorageMultisampleAPPLE(GL_RENDERBUFFER, samples, GL_DEPTH_COMPONENT24_OES, framebufferWidth, framebufferHeight) );
	    GL_ASSERT( glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, multisampleDepthbuffer) );

	    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE)
		break; // success!

	    NSLog(@"Creation of multisample buffer with samples=%d failed. Attempting to use configuration with samples=%d instead: %x", samples, samples / 2, glCheckFramebufferStatus(GL_FRAMEBUFFER));
	    samples /= 2;
	}

	//todo: __multiSampling = samples > 0;

	// Re-bind the default framebuffer
	GL_ASSERT( glBindFramebuffer(GL_FRAMEBUFFER, defaultFramebuffer) );

	if (samples == 0)
	{
	    // Unable to find a valid/supported multisample configuratoin - fallback to no multisampling
	    GL_ASSERT( glDeleteRenderbuffers(1, &multisampleRenderbuffer) );
	    GL_ASSERT( glDeleteRenderbuffers(1, &multisampleDepthbuffer) );
	    GL_ASSERT( glDeleteFramebuffers(1, &multisampleFramebuffer) );
	    multisampleFramebuffer = multisampleRenderbuffer = multisampleDepthbuffer = 0;
	}
    }

    // Create default depth buffer and attach to the frame buffer.
    // Note: If we are using multisample buffers, we can skip depth buffer creation here since we only
    // need the color buffer to resolve to.
    if (multisampleFramebuffer == 0)
    {
	GL_ASSERT( glGenRenderbuffers(1, &depthRenderbuffer) );
	GL_ASSERT( glBindRenderbuffer(GL_RENDERBUFFER, depthRenderbuffer) );
	GL_ASSERT( glRenderbufferStorage(GL_RENDERBUFFER, /*GL_DEPTH_COMPONENT24_OES*/GL_DEPTH24_STENCIL8, framebufferWidth, framebufferHeight) );
	GL_ASSERT( glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, depthRenderbuffer) );
	GL_ASSERT( glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_STENCIL_ATTACHMENT, GL_RENDERBUFFER, depthRenderbuffer) );

     /*   GL_ASSERT( glGenRenderbuffers(1, &stencilRenderbuffer) );
	GL_ASSERT( glBindRenderbuffer(GL_RENDERBUFFER, stencilRenderbuffer) );
	GL_ASSERT( glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, framebufferWidth, framebufferHeight) );
	GL_ASSERT( glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_STENCIL_ATTACHMENT, GL_RENDERBUFFER, stencilRenderbuffer) );
      */
    }

    // Sanity check, ensure that the framebuffer is valid
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
    {
	NSLog(@"ERROR: Failed to make complete framebuffer object %x", glCheckFramebufferStatus(GL_FRAMEBUFFER));
	[self deleteFramebuffer];
	return NO;
    }

    // If multisampling is enabled, set the currently bound framebuffer to the multisample buffer
    // since that is the buffer code should be drawing into (and FrameBuffr::initialize will detect
    // and set this bound buffer as the default one during initialization.
    if (multisampleFramebuffer)
	GL_ASSERT( glBindFramebuffer(GL_FRAMEBUFFER, multisampleFramebuffer) );

    return YES;
}

- (void)deleteFramebuffer
{
    if (context)
    {
	[EAGLContext setCurrentContext:context];
	if (defaultFramebuffer)
	{
	    GL_ASSERT( glDeleteFramebuffers(1, &defaultFramebuffer) );
	    defaultFramebuffer = 0;
	}
	if (colorRenderbuffer)
	{
	    GL_ASSERT( glDeleteRenderbuffers(1, &colorRenderbuffer) );
	    colorRenderbuffer = 0;
	}
	if (depthRenderbuffer)
	{
	    GL_ASSERT( glDeleteRenderbuffers(1, &depthRenderbuffer) );
	    depthRenderbuffer = 0;
	}
	if (stencilRenderbuffer)
	{
	    GL_ASSERT( glDeleteRenderbuffers(1, &stencilRenderbuffer) );
	    stencilRenderbuffer = 0;
	}
	if (multisampleFramebuffer)
	{
	    GL_ASSERT( glDeleteFramebuffers(1, &multisampleFramebuffer) );
	    multisampleFramebuffer = 0;
	}
	if (multisampleRenderbuffer)
	{
	    GL_ASSERT( glDeleteRenderbuffers(1, &multisampleRenderbuffer) );
	    multisampleRenderbuffer = 0;
	}
	if (multisampleDepthbuffer)
	{
	    GL_ASSERT( glDeleteRenderbuffers(1, &multisampleDepthbuffer) );
	    multisampleDepthbuffer = 0;
	}
    }
}

- (void)setSwapInterval:(NSInteger)interval
{
    if (interval >= 1)
    {
	swapInterval = interval;
	if (updating)
	{
	    [self stopUpdating];
	    [self startUpdating];
	}
    }
}

- (int)swapInterval
{
    return swapInterval;
}

- (void)swapBuffers
{
    if (context)
    {
	if (multisampleFramebuffer)
	{
	    // Multisampling is enabled: resolve the multisample buffer into the default framebuffer
	    GL_ASSERT( glBindFramebuffer(GL_DRAW_FRAMEBUFFER_APPLE, defaultFramebuffer) );
	    GL_ASSERT( glBindFramebuffer(GL_READ_FRAMEBUFFER_APPLE, multisampleFramebuffer) );
	    GL_ASSERT( glResolveMultisampleFramebufferAPPLE() );

	    if (oglDiscardSupported)
	    {
		// Performance hint that the GL driver can discard the contents of the multisample buffers
		// since they have now been resolved into the default framebuffer
		const GLenum discards[]  = { GL_COLOR_ATTACHMENT0, GL_DEPTH_ATTACHMENT };
		GL_ASSERT( glDiscardFramebufferEXT(GL_READ_FRAMEBUFFER_APPLE, 2, discards) );
	    }
	}
	else
	{
	    if (oglDiscardSupported)
	    {
		// Performance hint to the GL driver that the depth buffer is no longer required.
		const GLenum discards[]  = { GL_DEPTH_ATTACHMENT };
		//GL_ASSERT( glBindFramebuffer(GL_FRAMEBUFFER, defaultFramebuffer) );
		GL_ASSERT( glDiscardFramebufferEXT(GL_FRAMEBUFFER, 1, discards) );
	    }
	}

	// Present the color buffer
	GL_ASSERT( glBindRenderbuffer(GL_RENDERBUFFER, colorRenderbuffer) );
	[context presentRenderbuffer:GL_RENDERBUFFER];
    }
}

- (void)startGame
{
    if (game == nil)
    {
	game = Game::getInstance();
	__timeStart = getMachTimeInMilliseconds();
	game->run();
    }
}

- (void)startUpdating
{
    if (!updating)
    {
	displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(update:)];
	[displayLink setFrameInterval:swapInterval];
	[displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
	if (game)
	    game->resume();
	updating = TRUE;
    }
}

- (void)stopUpdating
{
    if (updating)
    {
	if (game)
	    game->pause();
	[displayLink invalidate];
	displayLink = nil;
	updating = FALSE;
    }
}

- (void)update:(id)sender
{
    if (context != nil)
    {
	// Ensure our context is current
	[EAGLContext setCurrentContext:context];

	// If the framebuffer needs (re)creating, do so
	if (updateFramebuffer)
	{
	    updateFramebuffer = NO;
	    [self deleteFramebuffer];
	    [self createFramebuffer];

	    // Start the game after our framebuffer is created for the first time.
	    if (game == nil)
	    {
		[self startGame];

		// HACK: Skip the first display update after creating buffers and initializing the game.
		// If we don't do this, the first frame (which includes any drawing during initialization)
		// does not make it to the display for some reason.
		return;
	    }
	}

	// Bind our framebuffer for rendering.
	// If multisampling is enabled, bind the multisample buffer - otherwise bind the default buffer
	GL_ASSERT( glBindFramebuffer(GL_FRAMEBUFFER, multisampleFramebuffer ? multisampleFramebuffer : defaultFramebuffer) );
	GL_ASSERT( glViewport(0, 0, framebufferWidth, framebufferHeight) );

	// Execute a single game frame
	if (game)
	    game->frame();

	// Present the contents of the color buffer
	[self swapBuffers];
    }
}

- (BOOL)showKeyboard
{
    return [self becomeFirstResponder];
}

- (BOOL)dismissKeyboard
{
    return [self resignFirstResponder];
}

- (void)insertText:(NSString*)text
{
    if([text length] == 0) return;
    assert([text length] == 1);
    unichar c = [text characterAtIndex:0];
    int key = getKey(c);
    Platform::keyEventInternal(Keyboard::KEY_PRESS, key);

    int character = getUnicode(key);
    if (character)
    {
	Platform::keyEventInternal(Keyboard::KEY_CHAR, /*character*/c);
    }

    Platform::keyEventInternal(Keyboard::KEY_RELEASE, key);
}

- (void)deleteBackward
{
    Platform::keyEventInternal(Keyboard::KEY_PRESS, Keyboard::KEY_BACKSPACE);
    Platform::keyEventInternal(Keyboard::KEY_CHAR, getUnicode(Keyboard::KEY_BACKSPACE));
    Platform::keyEventInternal(Keyboard::KEY_RELEASE, Keyboard::KEY_BACKSPACE);
}

- (BOOL)hasText
{
    return YES;
}

- (void)touchesBegan:(NSSet*)touches withEvent:(UIEvent*)event
{
    unsigned int touchID = 0;
    for(UITouch* touch in touches)
    {
	CGPoint touchPoint = [touch locationInView:self];
	/*if(self.multipleTouchEnabled == YES)
	{
	    touchID = [touch hash];
	}*/

	// Nested loop efficiency shouldn't be a concern since both loop sizes are small (<= 10)
	int i = 0;
	while (i < TOUCH_POINTS_MAX && __touchPoints[i].down)
	{
	    i++;
	}

	if (i < TOUCH_POINTS_MAX)
	{
	    __touchPoints[i].hashId = touchID;
	    __touchPoints[i].x = touchPoint.x;
	    __touchPoints[i].y = touchPoint.y;
	    __touchPoints[i].down = true;

	    Platform::touchEventInternal(Touch::TOUCH_PRESS, __touchPoints[i].x, __touchPoints[i].y, i);
	}
	else
	{
	    print("touchesBegan: unable to find free element in __touchPoints");
	}
    }
}

- (void)touchesEnded:(NSSet*)touches withEvent:(UIEvent*)event
{
    unsigned int touchID = 0;
    for(UITouch* touch in touches)
    {
	CGPoint touchPoint = [touch locationInView:self];
	/*if(self.multipleTouchEnabled == YES)
	    touchID = [touch hash];*/

	// Nested loop efficiency shouldn't be a concern since both loop sizes are small (<= 10)
	bool found = false;
	for (int i = 0; !found && i < TOUCH_POINTS_MAX; i++)
	{
	    if (__touchPoints[i].down && __touchPoints[i].hashId == touchID)
	    {
		__touchPoints[i].down = false;
		Platform::touchEventInternal(Touch::TOUCH_RELEASE, touchPoint.x, touchPoint.y, i);
		found = true;
	    }
	}

	if (!found)
	{
	    // It seems possible to receive an ID not in the array.
	    // The best we can do is clear the whole array.
	    for (int i = 0; i < TOUCH_POINTS_MAX; i++)
	    {
		if (__touchPoints[i].down)
		{
		    __touchPoints[i].down = false;
		    Platform::touchEventInternal(Touch::TOUCH_RELEASE, __touchPoints[i].x, __touchPoints[i].y, i);
		}
	    }
	}
    }
}

- (void)touchesCancelled:(NSSet*)touches withEvent:(UIEvent*)event
{
    // No equivalent for this in GamePlay -- treat as touch end
    [self touchesEnded:touches withEvent:event];
}

- (void)touchesMoved:(NSSet*)touches withEvent:(UIEvent*)event
{
    unsigned int touchID = 0;
    for(UITouch* touch in touches)
    {
	CGPoint touchPoint = [touch locationInView:self];
	/*if(self.multipleTouchEnabled == YES)
	    touchID = [touch hash];*/

	// Nested loop efficiency shouldn't be a concern since both loop sizes are small (<= 10)
	for (int i = 0; i < TOUCH_POINTS_MAX; i++)
	{
	    if (__touchPoints[i].down && __touchPoints[i].hashId == touchID)
	    {
		__touchPoints[i].x = touchPoint.x;
		__touchPoints[i].y = touchPoint.y;
		Platform::touchEventInternal(Touch::TOUCH_MOVE, __touchPoints[i].x, __touchPoints[i].y, i);
		break;
	    }
	}
    }
}

// Gesture support for Mac OS X Trackpads
- (bool)isGestureRegistered: (Gesture::GestureEvent) evt
{
    switch(evt) {
	case Gesture::GESTURE_SWIPE:
	    return (_swipeRightRecognizer != NULL);
	/*case Gesture::GESTURE_PINCH:
	    return (_pinchRecognizer != NULL);*/
	case Gesture::GESTURE_TAP:
	    return (_tapRecognizer != NULL);
	case Gesture::GESTURE_DOUBLETAP:
	    return (_doubleTapRecognizer != NULL);
	default:
	    break;
    }
    return false;
}

- (void)registerGesture: (Gesture::GestureEvent) evt
{
    if((evt & Gesture::GESTURE_SWIPE) == Gesture::GESTURE_SWIPE  && _swipeDownRecognizer == NULL && _swipeUpRecognizer == NULL && _swipeRightRecognizer == NULL && _swipeLeftRecognizer == NULL)
    {
	// right swipe (default)
	_swipeRightRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipeGesture:)];
	[self addGestureRecognizer:_swipeRightRecognizer];

	// left swipe
	_swipeLeftRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipeGesture:)];
	_swipeLeftRecognizer.direction = UISwipeGestureRecognizerDirectionLeft;
	[self addGestureRecognizer:_swipeLeftRecognizer];

	// up swipe
	_swipeUpRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipeGesture:)];
	_swipeUpRecognizer.direction = UISwipeGestureRecognizerDirectionUp;
	[self addGestureRecognizer:_swipeUpRecognizer];

	// down swipe
	_swipeDownRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipeGesture:)];
	_swipeDownRecognizer.direction = UISwipeGestureRecognizerDirectionDown;
	[self addGestureRecognizer:_swipeDownRecognizer];
    }
    /*if((evt & Gesture::GESTURE_PINCH) == Gesture::GESTURE_PINCH && _pinchRecognizer == NULL)
    {
	_pinchRecognizer = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinchGesture:)];
	[self addGestureRecognizer:_pinchRecognizer];
    }*/
    if((evt & Gesture::GESTURE_TAP) == Gesture::GESTURE_TAP && _tapRecognizer == NULL)
    {
	_tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTapGesture:)];
	[self addGestureRecognizer:_tapRecognizer];
    }
    if((evt & Gesture::GESTURE_DOUBLETAP) == Gesture::GESTURE_DOUBLETAP && _doubleTapRecognizer == NULL)
    {
	_doubleTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTapGesture:)];
	_doubleTapRecognizer.numberOfTapsRequired = 2;
	[self addGestureRecognizer:_doubleTapRecognizer];
    }
}

- (void)unregisterGesture: (Gesture::GestureEvent) evt
{
    if((evt & Gesture::GESTURE_SWIPE) == Gesture::GESTURE_SWIPE && _swipeRightRecognizer != NULL&& _swipeDownRecognizer != NULL && _swipeLeftRecognizer != NULL && _swipeUpRecognizer != NULL)
    {
	[self removeGestureRecognizer:_swipeRightRecognizer];
	[_swipeRightRecognizer release];
	_swipeRightRecognizer = NULL;

	[self removeGestureRecognizer:_swipeLeftRecognizer];
	[_swipeLeftRecognizer release];
	_swipeLeftRecognizer = NULL;

	[self removeGestureRecognizer:_swipeUpRecognizer];
	[_swipeUpRecognizer release];
	_swipeUpRecognizer = NULL;

	[self removeGestureRecognizer:_swipeDownRecognizer];
	[_swipeDownRecognizer release];
	_swipeDownRecognizer = NULL;
    }
    /*if((evt & Gesture::GESTURE_PINCH) == Gesture::GESTURE_PINCH && _pinchRecognizer != NULL)
    {
	[self removeGestureRecognizer:_pinchRecognizer];
	[_pinchRecognizer release];
	_pinchRecognizer = NULL;
    }*/
    if((evt & Gesture::GESTURE_TAP) == Gesture::GESTURE_TAP && _tapRecognizer != NULL)
    {
	[self removeGestureRecognizer:_tapRecognizer];
	[_tapRecognizer release];
	_tapRecognizer = NULL;
    }
}

- (void)handleTapGesture:(UITapGestureRecognizer*)sender
{
    CGPoint location = [sender locationInView:self];
    if (sender.state == UIGestureRecognizerStateRecognized) {
	gameplay::Platform::gestureDoubleTapEventInternal(location.x,location.y);
    }
    //gameplay::Platform::gestureTapEventInternal(location.x, location.y);
}

/*- (void)handlePinchGesture:(UIPinchGestureRecognizer*)sender
{
    CGFloat factor = [sender scale];
    CGPoint location = [sender locationInView:self];
    gameplay::Platform::gesturePinchEventInternal(location.x, location.y, factor);
}*/

- (void)handleSwipeGesture:(UISwipeGestureRecognizer*)sender
{
    UISwipeGestureRecognizerDirection direction = [sender direction];
    CGPoint location = [sender locationInView:self];
    int gameplayDirection = 0;
    switch(direction) {
	case UISwipeGestureRecognizerDirectionRight:
	    gameplayDirection = Gesture::SWIPE_DIRECTION_RIGHT;
	    break;
	case UISwipeGestureRecognizerDirectionLeft:
	    gameplayDirection = Gesture::SWIPE_DIRECTION_LEFT;
	    break;
	case UISwipeGestureRecognizerDirectionUp:
	    gameplayDirection = Gesture::SWIPE_DIRECTION_UP;
	    break;
	case UISwipeGestureRecognizerDirectionDown:
	    gameplayDirection = Gesture::SWIPE_DIRECTION_DOWN;
	    break;
    }
    if([self isGestureRegistered:Gesture::GESTURE_SWIPE])
    {
	gameplay::Platform::gestureSwipeEventInternal(location.x, location.y, gameplayDirection);
    }
}

@end


static void safeSendMessage(FacebookAsyncReturnEvent fare, FACEBOOK_ID id, const std::string& message="")
{
    if (Platform::getFbListener()) {
        Platform::getFbListener()->onFacebookEvent(fare, id, message);
    }
}


@interface ViewController : UIViewController

@property (strong, nonatomic) NSString* mUserName;
@property (strong, nonatomic) NSString* mUserID;

- (void)startUpdating;
- (void)stopUpdating;
- (void)perfomFbLoginButtonClick;
#ifdef FACEBOOK_SDK
- (NSString*)getFbAppId;
- (void)refreshLoginStatus;

- (void)acceptedRequest:(NSString *)senderId requestId:(NSString *) requestId;
- (void)DeleteAcceptedRequest:(NSString *)requestId;
- (void)DeletePendingRequest:(NSString *)requestId;
- (void)FetchRequestDetails:(bool)pending;
- (void)FetchUserDetails;
- (void)sessionStateChanged:(FBSession *)session state:(FBSessionState) state error:(NSError *)error;
#endif
@end

@implementation ViewController

/**
 * A function for parsing URL parameters.
 */
- (NSDictionary*)parseURLParams:(NSString *)query {
    NSArray *pairs = [query componentsSeparatedByString:@"&"];
    NSMutableDictionary *params = [[NSMutableDictionary alloc] init];
    for (NSString *pair in pairs) {
	NSArray *kv = [pair componentsSeparatedByString:@"="];
	NSString *val =
	[kv[1] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
	params[kv[0]] = val;
    }
    return params;
}

- (void)perfomFbLoginButtonClick {
    // get the app delegate so that we can access the session property
    AppDelegate *appDelegate = __appDelegate;

#ifdef FACEBOOK_SDK
    // this button's job is to flip-flop the session from open to closed
    if (appDelegate.session.isOpen) {
	// if a user logs out explicitly, we delete any cached token information, and next
	// time they run the applicaiton they will be presented with log in UX again; most
	// users will simply close the app or switch away, without logging out; this will
	// cause the implicit cached-token login to occur on next launch of the application
	[appDelegate.session closeAndClearTokenInformation];

    } else {
	if (appDelegate.session.state != FBSessionStateCreated) {
	    // Create a new, logged out session.
	    appDelegate.session = [[FBSession alloc] init];
	}

	[self openSession];
    }
#endif
}

static NSMutableDictionary* convertToDictionary(const FbBundle& fbBundle)
{
    NSMutableArray *objects = [NSMutableArray array];
    NSMutableArray *keys = [NSMutableArray array];
    
    const std::vector<std::string>& bundle = fbBundle.getData();
    
    if(!bundle.size()) return nil;
    
    for(int i=0; i<bundle.size(); i+=2)
    {
        NSString* object = [NSString stringWithCString:bundle[i].c_str() encoding:[NSString defaultCStringEncoding]];
        NSString* key = [NSString stringWithCString:bundle[i+1].c_str() encoding:[NSString defaultCStringEncoding]];
        
        [objects addObject:object];
        [keys addObject:key];
    }
    
    return [NSMutableDictionary dictionaryWithObjects:objects forKeys:keys];
}

#ifdef FACEBOOK_SDK
- (void) openSession {

    AppDelegate *appDelegate = __appDelegate;

    [FBSession setActiveSession:appDelegate.session];

    // if the session isn't open, let's open it now and present the login UX to the user
    [appDelegate.session openWithCompletionHandler:^(FBSession *session,
						     FBSessionState state,
						     NSError *error) {
	// and here we make sure to update our UX according to the new session state
	[self sessionStateChanged:session state:state error:error];

    }];
}

- (void)refreshLoginStatus {

    AppDelegate *appDelegate = __appDelegate;
    if (!appDelegate.session.isOpen) {
        // create a fresh session object
        appDelegate.session = [[FBSession alloc] init];
        
        // if we don't have a cached token, a call to open here would cause UX for login to
        // occur; we don't want that to happen unless the user clicks the login button, and so
        // we check here to make sure we have a token before calling open
        if (appDelegate.session.state == FBSessionStateCreatedTokenLoaded) {
            
            [self openSession];
        }
    } else {
        safeSendMessage(FARE_STATE_CHANGED, 0L, "Session already opened");
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
}

// This method will handle ALL the session state changes in the app
- (void)sessionStateChanged:(FBSession *)session state:(FBSessionState) state error:(NSError *)error
{
    // If the session was opened successfully
    if (!error && state == FBSessionStateOpen) {

        safeSendMessage(FARE_STATE_CHANGED, 0L, "Session opened");

        [self FetchUserDetails];
        
        return;
    }
    if (state == FBSessionStateClosed || state == FBSessionStateClosedLoginFailed){
        // If the session is closed
        safeSendMessage(FARE_STATE_CHANGED, 0L, "Session closed");
    }

    // Handle errors
    if (error){
	std::string message;
	NSString *alertText;
	NSString *alertTitle;
	// If the error requires people using an app to make an action outside of the app in order to recover
	if ([FBErrorUtility shouldNotifyUserForError:error] == YES){
	    message = "Something went wrong. ";
	    message += [[FBErrorUtility userMessageForError:error] UTF8String];
	} else {

	    // If the user cancelled login, do nothing
	    if ([FBErrorUtility errorCategoryForError:error] == FBErrorCategoryUserCancelled) {
		message = "User cancelled login";

		// Handle session closures that happen outside of the app
	    } else if ([FBErrorUtility errorCategoryForError:error] == FBErrorCategoryAuthenticationReopenSession){
		message = "Session Error. ";
		message += "Your current session is no longer valid. Please log in again.";

		// Here we will handle all other errors with a generic error message.
		// We recommend you check our Handling Errors guide for more information
		// https://developers.facebook.com/docs/ios/errors/
	    } else {
		//Get more error information from the error
		NSDictionary *errorInformation = [[[error.userInfo objectForKey:@"com.facebook.sdk:ParsedJSONResponseKey"] objectForKey:@"body"] objectForKey:@"error"];

		// Show the user an error message
		  message = "Something went wrong. ";
		message += [[NSString stringWithFormat:@"Please retry. \n\n If the problem persists contact us and mention this error code: %@", [errorInformation objectForKey:@"message"]] UTF8String];
	    }
	}
	// Clear this token
	[FBSession.activeSession closeAndClearTokenInformation];

	safeSendMessage(FARE_ERROR, 0L, message);
	safeSendMessage(FARE_STATE_CHANGED, 0L, "Session closed");
    }
}

- (void)FetchUserPermissions
{
    Platform::getPermissions().clear();
    for(NSString* permission in FBSession.activeSession.permissions) {
        Platform::getPermissions().push_back(std::string([permission UTF8String]));
    }
}

- (void)acceptedRequest: (NSString *)senderId requestId:(NSString *) requestId
{
    NSString *accessToken = [[[FBSession activeSession] accessTokenData] accessToken];
    NSDictionary *params = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                            senderId, @"from_id",
                            accessToken, @"access_token", nil];
    NSMutableArray *pairs = [[NSMutableArray alloc] initWithCapacity:0];
    for (NSString *key in params) {
        [pairs addObject:[NSString stringWithFormat:@"%@=%@", key, params[key]]];
    }
    // We finally join the pairs of our array using the '&'
    NSString *requestParams = [pairs componentsJoinedByString:@"&"];
    
    NSMutableURLRequest *phpRequest = [NSMutableURLRequest requestWithURL:[NSURL
                                            URLWithString:[NSString stringWithFormat:@"%@?%@", @"http://www.nderescue.com/facebook/request.php", requestParams]]
                                            cachePolicy:NSURLRequestUseProtocolCachePolicy
                                            timeoutInterval:20.0];
    
    [phpRequest setHTTPMethod:@"GET"];
#ifdef DEBUG
    NSLog(@"%@", phpRequest);
#endif

    NSHTTPURLResponse *response = nil;
    NSError *error = nil;
    NSData *returnData = [NSURLConnection sendSynchronousRequest:phpRequest
                                          returningResponse:&response
                                                error:&error];
    if (error == nil) {
        const std::string request_id([requestId UTF8String]);
        safeSendMessage(FARE_REMOVE_PENDING_REQUEST, 0L, request_id);

    } else {
        NSLog(@"%@",[error localizedDescription]);
        NSLog(@"%zd",[response statusCode]);
    }
}

- (void)DeleteAcceptedRequest: (NSString *)requestId
{
    [FBRequestConnection startWithGraphPath:requestId
                                 parameters:nil
                                 HTTPMethod:@"DELETE"
                          completionHandler:^(FBRequestConnection *connection, id result, NSError *error) {
                              if (!error) {
                                  NSLog(@"request: %@ successfully deleted!", requestId);
                                  const std::string request_id([requestId UTF8String]);
                                  safeSendMessage(FARE_REMOVE_ACCEPTED_REQUEST, 0L, request_id);
                              } else {
                                  NSLog(@"%@",[error localizedDescription]);
                              }
                          }];
}

- (void)DeletePendingRequest: (NSString *)requestId
{
    [FBRequestConnection startWithGraphPath:requestId
                                 parameters:nil
                                 HTTPMethod:@"DELETE"
                          completionHandler:^(FBRequestConnection *connection, id result, NSError *error) {
                              if (!error) {
                                  NSLog(@"request: %@ successfully deleted!", requestId);
                                  const std::string request_id([requestId UTF8String]);
                                  safeSendMessage(FARE_REMOVE_PENDING_REQUEST, 0L, request_id);
                              } else {
                                  NSLog(@"%@",[error localizedDescription]);
                              }
                          }];
}

- (NSString*)getFbAppId
{
    return [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"FacebookAppID"] copy];
}

- (void)FetchRequestDetails:(bool)pending;
{
    [FBRequestConnection startWithGraphPath:@"me/apprequests"
                          completionHandler:^(FBRequestConnection *connection, id result, NSError *error) {
                              if (!error) {
#ifdef DEBUG
                                  NSLog(@"user apprequest: %@", result);
#endif
                                  NSArray *data_list = [result objectForKey:@"data"];
                                  for(id single_data in data_list)
                                  {
                                      NSString *applicationId = [[single_data objectForKey:@"application"] objectForKey:@"id"];
                                      NSString *appId = [self getFbAppId];
                                      if (![applicationId isEqualToString:appId]) {
                                          continue;
                                      }
                                      NSString *userId = [[single_data objectForKey:@"to"] objectForKey:@"id"];
                                      if (![userId isEqualToString:self.mUserID]) {
                                          continue;
                                      }
                                      NSString *requestId = [single_data objectForKey:@"id"];
                                      const std::string request_id([requestId UTF8String]);

                                      NSString *senderId = [single_data objectForKey:@"data"];
                                      if (pending) {
                                          if (!senderId) {
                                              NSString *fromId = [[single_data objectForKey:@"from"] objectForKey:@"id"];
                                              safeSendMessage(FARE_ADD_PENDING_REQUEST, [fromId longLongValue], request_id);
                                          }
                                      } else {
                                          if (senderId) {
                                            // we send a message *only if* there is a senderId
                                            safeSendMessage(FARE_ADD_ACCEPTED_REQUEST, [senderId longLongValue], request_id);
                                        }
                                      }
                                  }
                              } else {
                                  // An error occurred, we need to handle the error
                                  NSLog(@"%@",[error localizedDescription]);
                              }
                          }];
}

- (void)FetchUserDetails
{
    // Start the facebook request
    [[FBRequest requestForMe]
     startWithCompletionHandler:
     ^(FBRequestConnection *connection, NSDictionary<FBGraphUser> *result, NSError *error)
     {
	 // Did everything come back okay with no errors?
	 if (!error && result) {
	     // If so we can extract out the player's Facebook ID and first name
	     self.mUserName = [[NSString alloc] initWithString:result.first_name];
	     self.mUserID = [[NSString alloc] initWithString:result.objectID];
         safeSendMessage(FARE_USERINFO_RETRIEVED, 0L);
	 }
	 else {
	     NSLog(@"%@",[error localizedDescription]);
     }
     }];

    [self FetchUserPermissions];
  
}
#endif

- (id)init
{
    if((self = [super init]))
    {
    }
    return self;
}

- (void)dealloc
{
    __view = nil;
    [super dealloc];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];

    Platform::memoryWarningCallback();
}

#pragma mark - View lifecycle
- (void)loadView
{
    self.view = [[[View alloc] init] autorelease];
    if(__view == nil)
    {
	__view = (View*)self.view;
    }
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    // Fetch the supported orientations array
    NSArray *supportedOrientations = NULL;
    if([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
    {
	supportedOrientations = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"UISupportedInterfaceOrientations~ipad"];
    }
    else if([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone)
    {
	supportedOrientations = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"UISupportedInterfaceOrientations~iphone"];
    }

    if(supportedOrientations == NULL)
    {
       supportedOrientations = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"UISupportedInterfaceOrientations"];
    }

    // If no supported orientations default to v1.0 handling (landscape only)
    if(supportedOrientations == nil) {
	return UIInterfaceOrientationIsLandscape(interfaceOrientation);
    }
    for(NSString *s in supportedOrientations) {
	if(interfaceOrientation == UIInterfaceOrientationEnum(s)) return YES;
    }
    return NO;
}

- (void)startUpdating
{
    [(View*)self.view startUpdating];
}

- (void)stopUpdating
{
    [(View*)self.view stopUpdating];
}

-(BOOL)canBecomeFirstResponder {
    return YES;
}

-(void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self becomeFirstResponder];
}

- (void)viewWillDisappear:(BOOL)animated {
    [self resignFirstResponder];
    [super viewWillDisappear:animated];
}

- (void)motionEnded:(UIEventSubtype)motion withEvent:(UIEvent *)event
{
    if (motion == UIEventSubtypeMotionShake)
    {
	gameplay::Game::getInstance()->deviceShakenEvent();
    }
}

@end





@implementation AppDelegate

@synthesize viewController;

/**
* A function for parsing URL parameters.
*/
- (NSDictionary*)parseURLParams:(NSString *)query {
    NSArray *pairs = [query componentsSeparatedByString:@"&"];
    NSMutableDictionary *params = [[NSMutableDictionary alloc] init];
    for (NSString *pair in pairs) {
	NSArray *kv = [pair componentsSeparatedByString:@"="];
	NSString *val =
	[kv[1] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
	params[kv[0]] = val;
    }
    return params;
}

#ifdef FACEBOOK_SDK
- (void) notificationGet:(NSString *)requestid {
    [FBRequestConnection startWithGraphPath:requestid
			  completionHandler:^(FBRequestConnection *connection,
					      id result,
					      NSError *error) {
			      if (!error) {

				      FbBundle bundle;
				      bundle.addPair(std::string([result[@"from"][@"name"] UTF8String]), "from_name");
				      bundle.addPair(std::string([result[@"from"][@"id"] UTF8String]), "from_id");
				      bundle.addPair(std::string([result[@"id"] UTF8String]), "request_id");
				      bundle.addPair(std::string([result[@"message"] UTF8String]), "message");

				      if(result[@"data"])
				      {
					 bundle.addPair(std::string([result[@"data"] UTF8String]), "data");
				      }

				      Platform::getNotifications().push_back(bundle);
				  if(Platform::getFbListener())
				  {
				      Platform::getFbListener()->onFacebookEvent(FARE_NONE, 0L, "TODO"); //TODO:
				  }


			      }
			  }];
}

- (void) handleAppLinkData:(FBAppLinkData *)appLinkData {
    NSString *targetURLString = appLinkData.originalQueryParameters[@"target_url"];
    if (targetURLString) {
	NSURL *targetURL = [NSURL URLWithString:targetURLString];
	NSDictionary *targetParams = [self parseURLParams:[targetURL query]];
	NSString *ref = [targetParams valueForKey:@"ref"];
	// Check for the ref parameter to check if this is one of
	// our incoming news feed link, otherwise it can be an
	// an attribution link
	if ([ref isEqualToString:@"notif"]) {
	    // Get the request id
	    NSString *requestIDParam = targetParams[@"request_ids"];
	    NSArray *requestIDs = [requestIDParam
				   componentsSeparatedByString:@","];

	    for(id element in requestIDs)
	    {
		[self notificationGet:element];
	    }


	}
    }
}

- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation {
    // attempt to extract a token from the url
    return [FBAppCall handleOpenURL:url
		  sourceApplication:sourceApplication
		    fallbackHandler:^(FBAppCall *call) {
                
               
            // Retrieve the link associated with the post
            NSURL *targetURL = [[call appLinkData] targetURL];
                
            const std::string foo([[targetURL absoluteString] UTF8String]);
GP_WARN("targetURL=%s", foo.c_str());
                
			// If there is an active session
			if (FBSession.activeSession.isOpen) {
                GP_WARN("openURL - FBSession.activeSession.isOpen");
			    // Check the incoming link
			    [self handleAppLinkData:call.appLinkData];
			} else if (call.accessTokenData) {
                GP_WARN("openURL - !FBSession.activeSession.isOpen");
			    // If token data is passed in and there's
			    // no active session.
			  /*  if ([self handleAppLinkToken:call.accessTokenData]) {
				// Attempt to open the session using the
				// cached token and if successful then
				// check the incoming link
				[self handleAppLinkData:call.appLinkData];
			    }*/
			}
		    }];
}
#endif

- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions
{
    __appDelegate = self;
    /*[UIApplication sharedApplication].statusBarHidden = YES;
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
    application.applicationSupportsShakeToEdit = YES;*/

    [window addSubview:viewController.view];
    [window makeKeyAndVisible];

    /*motionManager = [[CMMotionManager alloc] init];
    if([motionManager isAccelerometerAvailable] == YES)
    {
	motionManager.accelerometerUpdateInterval = 1 / 40.0;	 // 40Hz
	[motionManager startAccelerometerUpdates];
    }
    if([motionManager isGyroAvailable] == YES)
    {
	motionManager.gyroUpdateInterval = 1 / 40.0;	// 40Hz
	[motionManager startGyroUpdates];
    }*/

    window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    viewController = [[ViewController alloc] init];
    [window setRootViewController:viewController];
    [window makeKeyAndVisible];
    
    NSURL *the_url = (NSURL *)[launchOptions valueForKey:UIApplicationLaunchOptionsURLKey];
    if (the_url) {
        NSString *urlString = [the_url absoluteString];
        const std::string foo([urlString UTF8String]);
        GP_WARN(foo.c_str());
    }
    return YES;
}

- (void)getAccelerometerPitch:(float*)pitch roll:(float*)roll
{
    /*float p = 0.0f;
    float r = 0.0f;
    CMAccelerometerData* accelerometerData = motionManager.accelerometerData;
    if(accelerometerData != nil)
    {
	float tx, ty, tz;

	switch ([[UIApplication sharedApplication] statusBarOrientation])
	{
	case UIInterfaceOrientationLandscapeRight:
	    tx = -accelerometerData.acceleration.y;
	    ty = accelerometerData.acceleration.x;
	    break;

	case UIInterfaceOrientationLandscapeLeft:
	    tx = accelerometerData.acceleration.y;
	    ty = -accelerometerData.acceleration.x;
	    break;

	case UIInterfaceOrientationPortraitUpsideDown:
	    tx = -accelerometerData.acceleration.y;
	    ty = -accelerometerData.acceleration.x;
	    break;

	case UIInterfaceOrientationPortrait:
	    tx = accelerometerData.acceleration.x;
	    ty = accelerometerData.acceleration.y;
	    break;
	}
	tz = accelerometerData.acceleration.z;

	p = atan(ty / sqrt(tx * tx + tz * tz)) * 180.0f * M_1_PI;
	r = atan(tx / sqrt(ty * ty + tz * tz)) * 180.0f * M_1_PI;
    }

    if(pitch != NULL)
	*pitch = p;
    if(roll != NULL)
	*roll = r;*/
}

- (void)getRawAccelX:(float*)x Y:(float*)y Z:(float*)z
{
    /*CMAccelerometerData* accelerometerData = motionManager.accelerometerData;
    if(accelerometerData != nil)
    {
	*x = -9.81f * accelerometerData.acceleration.x;
	*y = -9.81f * accelerometerData.acceleration.y;
	*z = -9.81f * accelerometerData.acceleration.z;
    }*/
}

- (void)getRawGyroX:(float*)x Y:(float*)y Z:(float*)z
{
    /*CMGyroData* gyroData = motionManager.gyroData;
    if(gyroData != nil)
    {
	*x = gyroData.rotationRate.x;
	*y = gyroData.rotationRate.y;
	*z = gyroData.rotationRate.z;
    }*/
}

- (void)applicationWillResignActive:(UIApplication*)application
{
    Game::getInstance()->applicationWillResignActive();
    [viewController stopUpdating];
}

- (void)applicationDidEnterBackground:(UIApplication*)application
{
    Game::getInstance()->applicationDidEnterBackground();
    [viewController stopUpdating];
}

- (void)applicationWillEnterForeground:(UIApplication*)application
{
    [viewController startUpdating];
    Game::getInstance()->applicationWillEnterForeground();
}

- (void)applicationDidBecomeActive:(UIApplication*)application
{
#ifdef FACEBOOK_SDK
    [FBAppEvents activateApp];
#endif
    /*
     Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
     */
    [viewController startUpdating];
    Game::getInstance()->applicationDidBecomeActive();


#ifdef FACEBOOK_SDK
    // We need to properly handle activation of the application with regards to SSO
    //	(e.g., returning from iOS 6.0 authorization dialog or from fast app switching).
    [FBAppCall handleDidBecomeActiveWithSession:self.session];
#endif
}

- (void)applicationWillTerminate:(UIApplication*)application
{
    Game::getInstance()->applicationWillTerminate();
    [viewController stopUpdating];

    // if the app is going away, we close the session if it is open
    // this is a good idea because things may be hanging off the session, that need
    // releasing (completion block, etc.) and other components in the app may be awaiting
    // close notification in order to do cleanup
#ifdef FACEBOOK_SDK
    [self.session close];
#endif
}

- (void)dealloc
{
    [window setRootViewController:nil];
    [viewController release];
    [window release];
    //[motionManager release];
    [super dealloc];
}

@end


double getMachTimeInMilliseconds()
{
    static const double kOneMillion = 1000 * 1000;
    static mach_timebase_info_data_t s_timebase_info;

    if (s_timebase_info.denom == 0)
	(void) mach_timebase_info(&s_timebase_info);

    // mach_absolute_time() returns billionth of seconds, so divide by one million to get milliseconds
    GP_ASSERT(s_timebase_info.denom);
    return ((double)mach_absolute_time() * (double)s_timebase_info.numer) / (kOneMillion * (double)s_timebase_info.denom);
}

int getKey(unichar keyCode)
{
    switch(keyCode)
    {
	case 0x0A:
	    return Keyboard::KEY_RETURN;
	case 0x20:
	    return Keyboard::KEY_SPACE;

	case 0x30:
	    return Keyboard::KEY_ZERO;
	case 0x31:
	    return Keyboard::KEY_ONE;
	case 0x32:
	    return Keyboard::KEY_TWO;
	case 0x33:
	    return Keyboard::KEY_THREE;
	case 0x34:
	    return Keyboard::KEY_FOUR;
	case 0x35:
	    return Keyboard::KEY_FIVE;
	case 0x36:
	    return Keyboard::KEY_SIX;
	case 0x37:
	    return Keyboard::KEY_SEVEN;
	case 0x38:
	    return Keyboard::KEY_EIGHT;
	case 0x39:
	    return Keyboard::KEY_NINE;

	case 0x41:
	    return Keyboard::KEY_CAPITAL_A;
	case 0x42:
	    return Keyboard::KEY_CAPITAL_B;
	case 0x43:
	    return Keyboard::KEY_CAPITAL_C;
	case 0x44:
	    return Keyboard::KEY_CAPITAL_D;
	case 0x45:
	    return Keyboard::KEY_CAPITAL_E;
	case 0x46:
	    return Keyboard::KEY_CAPITAL_F;
	case 0x47:
	    return Keyboard::KEY_CAPITAL_G;
	case 0x48:
	    return Keyboard::KEY_CAPITAL_H;
	case 0x49:
	    return Keyboard::KEY_CAPITAL_I;
	case 0x4A:
	    return Keyboard::KEY_CAPITAL_J;
	case 0x4B:
	    return Keyboard::KEY_CAPITAL_K;
	case 0x4C:
	    return Keyboard::KEY_CAPITAL_L;
	case 0x4D:
	    return Keyboard::KEY_CAPITAL_M;
	case 0x4E:
	    return Keyboard::KEY_CAPITAL_N;
	case 0x4F:
	    return Keyboard::KEY_CAPITAL_O;
	case 0x50:
	    return Keyboard::KEY_CAPITAL_P;
	case 0x51:
	    return Keyboard::KEY_CAPITAL_Q;
	case 0x52:
	    return Keyboard::KEY_CAPITAL_R;
	case 0x53:
	    return Keyboard::KEY_CAPITAL_S;
	case 0x54:
	    return Keyboard::KEY_CAPITAL_T;
	case 0x55:
	    return Keyboard::KEY_CAPITAL_U;
	case 0x56:
	    return Keyboard::KEY_CAPITAL_V;
	case 0x57:
	    return Keyboard::KEY_CAPITAL_W;
	case 0x58:
	    return Keyboard::KEY_CAPITAL_X;
	case 0x59:
	    return Keyboard::KEY_CAPITAL_Y;
	case 0x5A:
	    return Keyboard::KEY_CAPITAL_Z;


	case 0x61:
	    return Keyboard::KEY_A;
	case 0x62:
	    return Keyboard::KEY_B;
	case 0x63:
	    return Keyboard::KEY_C;
	case 0x64:
	    return Keyboard::KEY_D;
	case 0x65:
	    return Keyboard::KEY_E;
	case 0x66:
	    return Keyboard::KEY_F;
	case 0x67:
	    return Keyboard::KEY_G;
	case 0x68:
	    return Keyboard::KEY_H;
	case 0x69:
	    return Keyboard::KEY_I;
	case 0x6A:
	    return Keyboard::KEY_J;
	case 0x6B:
	    return Keyboard::KEY_K;
	case 0x6C:
	    return Keyboard::KEY_L;
	case 0x6D:
	    return Keyboard::KEY_M;
	case 0x6E:
	    return Keyboard::KEY_N;
	case 0x6F:
	    return Keyboard::KEY_O;
	case 0x70:
	    return Keyboard::KEY_P;
	case 0x71:
	    return Keyboard::KEY_Q;
	case 0x72:
	    return Keyboard::KEY_R;
	case 0x73:
	    return Keyboard::KEY_S;
	case 0x74:
	    return Keyboard::KEY_T;
	case 0x75:
	    return Keyboard::KEY_U;
	case 0x76:
	    return Keyboard::KEY_V;
	case 0x77:
	    return Keyboard::KEY_W;
	case 0x78:
	    return Keyboard::KEY_X;
	case 0x79:
	    return Keyboard::KEY_Y;
	case 0x7A:
	    return Keyboard::KEY_Z;
	default:
	    break;

       // Symbol Row 3
	case 0x2E:
	    return Keyboard::KEY_PERIOD;
	case 0x2C:
	    return Keyboard::KEY_COMMA;
	case 0x3F:
	    return Keyboard::KEY_QUESTION;
	case 0x21:
	    return Keyboard::KEY_EXCLAM;
	case 0x27:
	    return Keyboard::KEY_APOSTROPHE;

	// Symbols Row 2
	case 0x2D:
	    return Keyboard::KEY_MINUS;
	case 0x2F:
	    return Keyboard::KEY_SLASH;
	case 0x3A:
	    return Keyboard::KEY_COLON;
	case 0x3B:
	    return Keyboard::KEY_SEMICOLON;
	case 0x28:
	    return Keyboard::KEY_LEFT_PARENTHESIS;
	case 0x29:
	    return Keyboard::KEY_RIGHT_PARENTHESIS;
	case 0x24:
	    return Keyboard::KEY_DOLLAR;
	case 0x26:
	    return Keyboard::KEY_AMPERSAND;
	case 0x40:
	    return Keyboard::KEY_AT;
	case 0x22:
	    return Keyboard::KEY_QUOTE;

	// Numeric Symbols Row 1
	case 0x5B:
	    return Keyboard::KEY_LEFT_BRACKET;
	case 0x5D:
	    return Keyboard::KEY_RIGHT_BRACKET;
	case 0x7B:
	    return Keyboard::KEY_LEFT_BRACE;
	case 0x7D:
	    return Keyboard::KEY_RIGHT_BRACE;
	case 0x23:
	    return Keyboard::KEY_NUMBER;
	case 0x25:
	    return Keyboard::KEY_PERCENT;
	case 0x5E:
	    return Keyboard::KEY_CIRCUMFLEX;
	case 0x2A:
	    return Keyboard::KEY_ASTERISK;
	case 0x2B:
	    return Keyboard::KEY_PLUS;
	case 0x3D:
	    return Keyboard::KEY_EQUAL;

	// Numeric Symbols Row 2
	case 0x5F:
	    return Keyboard::KEY_UNDERSCORE;
	case 0x5C:
	    return Keyboard::KEY_BACK_SLASH;
	case 0x7C:
	    return Keyboard::KEY_BAR;
	case 0x7E:
	    return Keyboard::KEY_TILDE;
	case 0x3C:
	    return Keyboard::KEY_LESS_THAN;
	case 0x3E:
	    return Keyboard::KEY_GREATER_THAN;
	case 0x80:
	    return Keyboard::KEY_EURO;
	case 0xA3:
	    return Keyboard::KEY_POUND;
	case 0xA5:
	    return Keyboard::KEY_YEN;
	case 0xB7:
	    return Keyboard::KEY_MIDDLE_DOT;
    }
    return Keyboard::KEY_NONE;
}

/**
 * Returns the unicode value for the given keycode or zero if the key is not a valid printable character.
 */
int getUnicode(int key)
{

    switch (key)
    {
	case Keyboard::KEY_BACKSPACE:
	    return 0x0008;
	case Keyboard::KEY_TAB:
	    return 0x0009;
	case Keyboard::KEY_RETURN:
	case Keyboard::KEY_KP_ENTER:
	    return 0x000A;
	case Keyboard::KEY_ESCAPE:
	    return 0x001B;
	case Keyboard::KEY_SPACE:
	case Keyboard::KEY_EXCLAM:
	case Keyboard::KEY_QUOTE:
	case Keyboard::KEY_NUMBER:
	case Keyboard::KEY_DOLLAR:
	case Keyboard::KEY_PERCENT:
	case Keyboard::KEY_CIRCUMFLEX:
	case Keyboard::KEY_AMPERSAND:
	case Keyboard::KEY_APOSTROPHE:
	case Keyboard::KEY_LEFT_PARENTHESIS:
	case Keyboard::KEY_RIGHT_PARENTHESIS:
	case Keyboard::KEY_ASTERISK:
	case Keyboard::KEY_PLUS:
	case Keyboard::KEY_COMMA:
	case Keyboard::KEY_MINUS:
	case Keyboard::KEY_PERIOD:
	case Keyboard::KEY_SLASH:
	case Keyboard::KEY_ZERO:
	case Keyboard::KEY_ONE:
	case Keyboard::KEY_TWO:
	case Keyboard::KEY_THREE:
	case Keyboard::KEY_FOUR:
	case Keyboard::KEY_FIVE:
	case Keyboard::KEY_SIX:
	case Keyboard::KEY_SEVEN:
	case Keyboard::KEY_EIGHT:
	case Keyboard::KEY_NINE:
	case Keyboard::KEY_COLON:
	case Keyboard::KEY_SEMICOLON:
	case Keyboard::KEY_LESS_THAN:
	case Keyboard::KEY_EQUAL:
	case Keyboard::KEY_GREATER_THAN:
	case Keyboard::KEY_QUESTION:
	case Keyboard::KEY_AT:
	case Keyboard::KEY_CAPITAL_A:
	case Keyboard::KEY_CAPITAL_B:
	case Keyboard::KEY_CAPITAL_C:
	case Keyboard::KEY_CAPITAL_D:
	case Keyboard::KEY_CAPITAL_E:
	case Keyboard::KEY_CAPITAL_F:
	case Keyboard::KEY_CAPITAL_G:
	case Keyboard::KEY_CAPITAL_H:
	case Keyboard::KEY_CAPITAL_I:
	case Keyboard::KEY_CAPITAL_J:
	case Keyboard::KEY_CAPITAL_K:
	case Keyboard::KEY_CAPITAL_L:
	case Keyboard::KEY_CAPITAL_M:
	case Keyboard::KEY_CAPITAL_N:
	case Keyboard::KEY_CAPITAL_O:
	case Keyboard::KEY_CAPITAL_P:
	case Keyboard::KEY_CAPITAL_Q:
	case Keyboard::KEY_CAPITAL_R:
	case Keyboard::KEY_CAPITAL_S:
	case Keyboard::KEY_CAPITAL_T:
	case Keyboard::KEY_CAPITAL_U:
	case Keyboard::KEY_CAPITAL_V:
	case Keyboard::KEY_CAPITAL_W:
	case Keyboard::KEY_CAPITAL_X:
	case Keyboard::KEY_CAPITAL_Y:
	case Keyboard::KEY_CAPITAL_Z:
	case Keyboard::KEY_LEFT_BRACKET:
	case Keyboard::KEY_BACK_SLASH:
	case Keyboard::KEY_RIGHT_BRACKET:
	case Keyboard::KEY_UNDERSCORE:
	case Keyboard::KEY_GRAVE:
	case Keyboard::KEY_A:
	case Keyboard::KEY_B:
	case Keyboard::KEY_C:
	case Keyboard::KEY_D:
	case Keyboard::KEY_E:
	case Keyboard::KEY_F:
	case Keyboard::KEY_G:
	case Keyboard::KEY_H:
	case Keyboard::KEY_I:
	case Keyboard::KEY_J:
	case Keyboard::KEY_K:
	case Keyboard::KEY_L:
	case Keyboard::KEY_M:
	case Keyboard::KEY_N:
	case Keyboard::KEY_O:
	case Keyboard::KEY_P:
	case Keyboard::KEY_Q:
	case Keyboard::KEY_R:
	case Keyboard::KEY_S:
	case Keyboard::KEY_T:
	case Keyboard::KEY_U:
	case Keyboard::KEY_V:
	case Keyboard::KEY_W:
	case Keyboard::KEY_X:
	case Keyboard::KEY_Y:
	case Keyboard::KEY_Z:
	case Keyboard::KEY_LEFT_BRACE:
	case Keyboard::KEY_BAR:
	case Keyboard::KEY_RIGHT_BRACE:
	case Keyboard::KEY_TILDE:
	    return key;
	default:
	    return 0;
    }
}

namespace gameplay
{

extern void print(const char* format, ...)
{
    GP_ASSERT(format);
    va_list argptr;
    va_start(argptr, format);
    vfprintf(stderr, format, argptr);
    va_end(argptr);
}

Platform::Platform(Game* game) : _game(game)
{
}

Platform::~Platform()
{
}

Platform* Platform::create(Game* game, void* attachToWindow)
{
    Platform* platform = new Platform(game);
    return platform;
}

int Platform::enterMessagePump()
{
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    [AppDelegate load];
    UIApplicationMain(0, nil, NSStringFromClass([AppDelegate class]), NSStringFromClass([AppDelegate class]));
    [pool release];
    return EXIT_SUCCESS;
}

void Platform::signalShutdown()
{
    // Cannot 'exit' an iOS Application
    assert(false);
    [__view stopUpdating];
    exit(0);
}

bool Platform::canExit()
{
    return false;
}

static CGSize getDeviceOrientedSize(UIInterfaceOrientation uiio)
{
    CGFloat localWidth = [[UIScreen mainScreen] bounds].size.width;
    CGFloat localHeight = [[UIScreen mainScreen] bounds].size.height;
    
    /*if ([[[UIDevice currentDevice] systemVersion] compare:@"8.0" options:NSNumericSearch] == NSOrderedAscending ) {
        if ((uiio != UIInterfaceOrientationPortrait) && (uiio != UIInterfaceOrientationPortraitUpsideDown)) {
            localWidth = [[UIScreen mainScreen] bounds].size.height;
            localHeight = [[UIScreen mainScreen] bounds].size.width;
        }
    } else if ((uiio == UIInterfaceOrientationPortrait) || (uiio == UIInterfaceOrientationPortraitUpsideDown)) {
        localWidth = [[UIScreen mainScreen] bounds].size.height;
        localHeight = [[UIScreen mainScreen] bounds].size.width;
    }*/
    return CGSizeMake(localWidth, localHeight);
}

gameplay::Vector2 Platform::getMobileNativeResolution()
{
    /*const CGSize size = getDeviceOrientedSize([__appDelegate.viewController interfaceOrientation]);
    const float scale = [[UIScreen mainScreen] scale];
    return Vector2(scale*size.width, scale*size.height);*/
    CGFloat localWidth = [[UIScreen mainScreen] bounds].size.width;
    CGFloat localHeight = [[UIScreen mainScreen] bounds].size.height;
    return Vector2(localWidth, localHeight);
}

unsigned int Platform::getDisplayWidth()
{
    const CGFloat size = [[UIScreen mainScreen] bounds].size.width;
    return Platform::m_mobileScale * size;
}

unsigned int Platform::getDisplayHeight()
{
    const CGFloat size = [[UIScreen mainScreen] bounds].size.height;
    return Platform::m_mobileScale * size;
}

double Platform::getAbsoluteTime()
{
    __timeAbsolute = getMachTimeInMilliseconds();
    return __timeAbsolute;
}

void Platform::setAbsoluteTime(double time)
{
    __timeAbsolute = time;
}

bool Platform::isVsync()
{
    return __vsync;
}

void Platform::setVsync(bool enable)
{
    __vsync = enable;
}

void Platform::swapBuffers()
{
    if (__view)
	[__view swapBuffers];
}

void Platform::sleep(long ms)
{
    usleep(ms * 1000);
}

bool Platform::canChangeResolution()
{
    return true;
}

bool Platform::hasAccelerometer()
{
    return true;
}

void Platform::getAccelerometerValues(float* pitch, float* roll)
{
    [__appDelegate getAccelerometerPitch:pitch roll:roll];
}

void Platform::getRawSensorValues(float* accelX, float* accelY, float* accelZ, float* gyroX, float* gyroY, float* gyroZ)
{
    float x, y, z;
    [__appDelegate getRawAccelX:&x Y:&y Z:&z];
    if (accelX)
    {
	*accelX = x;
    }
    if (accelY)
    {
	*accelY = y;
    }
    if (accelZ)
    {
	*accelZ = z;
    }

    [__appDelegate getRawGyroX:&x Y:&y Z:&z];
    if (gyroX)
    {
	*gyroX = x;
    }
    if (gyroY)
    {
	*gyroY = y;
    }
    if (gyroZ)
    {
	*gyroZ = z;
    }
}

void Platform::getArguments(int* argc, char*** argv)
{
    if (argc)
	*argc = __argc;
    if (argv)
	*argv = __argv;
}

bool Platform::hasMouse()
{
    // not supported
    return false;
}

void Platform::setMouseCaptured(bool captured)
{
    // not supported
}

bool Platform::isMouseCaptured()
{
    // not supported
    return false;
}

void Platform::setCursorVisible(bool visible)
{
    // not supported
}

bool Platform::isCursorVisible()
{
    // not supported
    return false;
}

void Platform::setMultiSampling(bool enabled)
{
    //todo
}

bool Platform::isMultiSampling()
{
    return false; //todo
}

void Platform::setMultiTouch(bool enabled)
{
    //__view.multipleTouchEnabled = enabled;
}

bool Platform::isMultiTouch()
{
    return false;
}

void Platform::displayKeyboard(bool display)
{
    if(__view)
    {
	if(display)
	{
	    [__view showKeyboard];
	}
	else
	{
	    [__view dismissKeyboard];
	}
    }
}

void Platform::shutdownInternal()
{
    Game::getInstance()->shutdown();
}

bool Platform::isGestureSupported(Gesture::GestureEvent evt)
{
    return true;
}

void Platform::registerGesture(Gesture::GestureEvent evt)
{
    [__view registerGesture:evt];
}

void Platform::unregisterGesture(Gesture::GestureEvent evt)
{
    [__view unregisterGesture:evt];
}

bool Platform::isGestureRegistered(Gesture::GestureEvent evt)
{
    return [__view isGestureRegistered:evt];
}

void Platform::pollGamepadState(Gamepad* gamepad)
{
}

bool Platform::launchURL(const char *url)
{
    if (url == NULL || *url == '\0')
	return false;

    return [[UIApplication sharedApplication] openURL:[NSURL URLWithString:[NSString stringWithUTF8String: url]]];
}

const char *Platform::getAppDocumentDirectory(const char *filename2Append)
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentPath = [paths objectAtIndex:0];
	return [[documentPath stringByAppendingPathComponent: [NSString stringWithUTF8String: filename2Append]] UTF8String];
}

void Platform::refreshLoginStatus()
{
    [__appDelegate.viewController refreshLoginStatus];
}

void Platform::performFbLoginButtonClick()
{
    [__appDelegate.viewController perfomFbLoginButtonClick];
}

bool Platform::isUserLogged()
{
#ifdef FACEBOOK_SDK
    return __appDelegate.session.isOpen;
#else
    return false;
#endif
}

void Platform::acceptRequest(const std::string &sender_id, const std::string &request_id)
{
    [__appDelegate.viewController acceptedRequest: [NSString stringWithUTF8String: sender_id.c_str()] requestId:[NSString stringWithUTF8String: request_id.c_str()]];
}

void Platform::fetchAcceptedRequestList()
{
    [__appDelegate.viewController FetchRequestDetails:false];
}
   
void Platform::fetchPendingRequestList()
{
    [__appDelegate.viewController FetchRequestDetails:true];
}
    
void Platform::deleteAcceptedRequest(const std::string &request_id)
{
    NSString *requestId =[NSString stringWithCString:request_id.c_str() encoding:[NSString defaultCStringEncoding]];
    [__appDelegate.viewController DeleteAcceptedRequest:requestId];
}

void Platform::deletePendingRequest(const std::string &request_id)
{
    NSString *requestId =[NSString stringWithCString:request_id.c_str() encoding:[NSString defaultCStringEncoding]];
    [__appDelegate.viewController DeletePendingRequest:requestId];
}

void Platform::sendRequest(const std::string& graphPath, const FbBundle& bundle, HTTP_METHOD method, const std::string &callbackId)
{
#ifdef FACEBOOK_SDK
    NSMutableDictionary* params = convertToDictionary(bundle);
    NSString* path = [NSString stringWithUTF8String: graphPath.c_str()];

    NSString* httpMethod;

    switch(method){
	case HTTP_GET:
	    httpMethod = @"GET";
	    break;
	case HTTP_POST:
	    httpMethod = @"POST";
	    break;
	case HTTP_DELETE:
	    httpMethod = @"DELETE";
	    break;
    }

    [FBRequestConnection startWithGraphPath:path
				 parameters:params
				 HTTPMethod:httpMethod
			  completionHandler:^(FBRequestConnection *connection, id result, NSError *error) {
                  if (error) {
                      NSLog(@"%@",[error localizedDescription]);
                      safeSendMessage(FARE_ERROR, 0L);
                  }
                  else {
                      safeSendMessage(FARE_SCORE_POSTED, 0L);
                  }
              }];
#endif
}

void Platform::sendRequestDialog(const FbBundle &bundle, const std::string &title, const std::string &message)
{
    NSMutableDictionary* params = convertToDictionary(bundle);
    NSString* m =[NSString stringWithCString:message.c_str() encoding:[NSString defaultCStringEncoding]];
    NSString* t =[NSString stringWithCString:title.c_str() encoding:[NSString defaultCStringEncoding]];

#ifdef FACEBOOK_SDK
	[FBWebDialogs
	 presentRequestsDialogModallyWithSession:nil
	 message:m
	 title:t
	 parameters:params
	 handler:^(FBWebDialogResult result, NSURL *resultURL, NSError *error) {
	     if (error) {
		 // Error launching the dialog or sending the request.
		 safeSendMessage(FARE_ERROR, 0L, "Error sending request.");
	     } else {
             if (result == FBWebDialogResultDialogNotCompleted) {
                 // User clicked the "x" icon
                 NSLog(@"User canceled request.");
             } else {
                 // Handle the send request callback
                 bool requestOk = false;
                 NSArray *urlPairResult = [[resultURL query] componentsSeparatedByString:@"&"];
                 for (NSString *pair in urlPairResult) {
                     
                     NSArray *kv = [pair componentsSeparatedByString:@"="];
#ifdef DEBUG
                     NSLog(@"urlParams: %@, %@", kv[0], kv[1]);
#endif
                     NSString *val = [kv[0] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
                     if ([val isEqualToString:@"request"]) {
                         requestOk = true;
                         continue;
                     }
                     if (requestOk) {
                         NSString *recipient_id = [kv[1] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
                         safeSendMessage(FARE_ADD_RECIPIENT, [recipient_id longLongValue], "");
                     }
                 }
             }
	     }
	 }];
#endif
}

void Platform::updateFriendsAsync()
{
#ifdef FACEBOOK_SDK
    NSString* scores = @"/scores";

    NSString* graphPath = [NSString stringWithFormat:@"%@%@", [__appDelegate.viewController getFbAppId] , scores ];

    [FBRequestConnection startWithGraphPath:graphPath parameters:nil HTTPMethod:@"GET" completionHandler:^(FBRequestConnection *connection, id result, NSError *error) {

	if(error) {
	    safeSendMessage(FARE_ERROR, 0L, "error fetching friends data");
	}

	if (result && !error) {

	    NSArray *array = [result objectForKey:@"data"];
	    for (id element in array) {
            NSString *name	    = [[element objectForKey:@"user"] objectForKey:@"name"];
            NSString *userId    = [[element objectForKey:@"user"] objectForKey:@"id"];
            int score = [[element objectForKey:@"score"] intValue];

            safeSendMessage(FARE_ADD_FRIEND, [userId longLongValue], [[NSString stringWithFormat: @"%@<|>%d.", name, score] UTF8String]);
	    }
	}

    }];
#endif
}

FACEBOOK_ID Platform::getUserId()
{
    return [__appDelegate.viewController.mUserID longLongValue];
}

std::string Platform::getUserName()
{
    return std::string([__appDelegate.viewController.mUserName UTF8String]);
}


std::string Platform::getAppId()
{
#ifdef FACEBOOK_SDK
    return std::string([[__appDelegate.viewController getFbAppId] UTF8String]);
#else
    return "";
#endif
}


void Platform::requestNewPermissionAsync(const std::string &permission)
{

   NSString* perm = [NSString stringWithCString:permission.c_str() encoding:[NSString defaultCStringEncoding]];

#ifdef FACEBOOK_SDK
    [FBSession.activeSession requestNewPublishPermissions:[NSArray arrayWithObject:perm]
					  defaultAudience:FBSessionDefaultAudienceFriends
					completionHandler:^(FBSession *session, NSError *error) {
					    __block NSString *alertText;
					    __block NSString *alertTitle;
					    if (!error) {
						if ([FBSession.activeSession.permissions
						     indexOfObject:perm] == NSNotFound){
						    // Permission not granted, tell the user we will not publish
						    alertTitle = @"Permission not granted";
						    alertText = @"Your action will not be published to Facebook.";
						    [[[UIAlertView alloc] initWithTitle:alertTitle
										message:alertText
									       delegate:__appDelegate
								      cancelButtonTitle:@"OK!"
								      otherButtonTitles:nil] show];
						} else {

						    [__appDelegate.viewController FetchUserPermissions];
						    safeSendMessage(FARE_NONE, 0L, "TODO"); //TODO:

						}

					    } else {
						safeSendMessage(FARE_ERROR, 0L, "error requesting additional permission");
					    }
					}];
#endif
}


}

#endif
