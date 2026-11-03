/**************************************************************************/
/*  qbo_webview_ios.mm                                                    */
/*                                                                        */
/*  Godot 4.7 GDExtension: native WKWebView overlay for the club stage TV. */
/*                                                                        */
/*  The extension registers the class `QBOWebViewIOS` (RefCounted) with    */
/*  the following methods:                                                */
/*                                                                        */
/*      open(url: String) -> bool   show a fullscreen WKWebView           */
/*      close() -> void             hide it                               */
/*      is_open() -> bool           true while the overlay is visible     */
/*      set_insets(top: float, bottom: float) -> void                     */
/*      reload() -> void            reload the current page               */
/*                                                                        */
/*  GDScript reaches it through ClassDB:                                  */
/*      var view = ClassDB.instantiate("QBOWebViewIOS")                   */
/*      view.open("https://www.youtube.com/embed/…")                      */
/*                                                                        */
/*  YouTube embed URLs are loaded through a tiny HTML wrapper whose       */
/*  base URL is https://www.youtube.com, so Origin/Referer match the      */
/*  official iframe and playback error 153 does not happen.               */
/**************************************************************************/

#include "qbo_gdextension.h"

#include <string.h>

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#if __has_feature(modules)
@import WebKit;
#else
#import <WebKit/WebKit.h>
#endif

/* ------------------------------------------------------------- interface */

static GDExtensionClassLibraryPtr g_library = nullptr;
static QboFnRegisterClass g_register_class = nullptr;
static QboFnRegisterMethod g_register_method = nullptr;
static QboFnConstructObject g_construct_object = nullptr;
static QboFnObjectSetInstance g_object_set_instance = nullptr;
static QboFnStringNameNew g_string_name_new = nullptr;
static QboFnStringNew g_string_new = nullptr;
static QboFnGetFromVariantCtor g_get_from_ctor = nullptr;
static QboFnGetInternalPtr g_get_internal_ptr = nullptr;
static QboFnStringToUtf8 g_string_to_utf8 = nullptr;
static QboFnVariantGetType g_variant_get_type = nullptr;

static GDExtensionVariantFromTypeConstructorFunc g_ctor_bool = nullptr;
static GDExtensionVariantFromTypeConstructorFunc g_ctor_float = nullptr;

/* 8-byte aligned storage for opaque Godot values. */
static uint64_t g_sn_class[1];
static uint64_t g_sn_parent[1];

static bool g_registered = false;

/* --------------------------------------------------------------- methods */

enum {
	QBO_METHOD_OPEN = 1,
	QBO_METHOD_CLOSE = 2,
	QBO_METHOD_IS_OPEN = 3,
	QBO_METHOD_SET_INSETS = 4,
	QBO_METHOD_RELOAD = 5,
};

struct QboInstance {
	GDExtensionObjectPtr owner;
};

/* ------------------------------------------------------------- native UI */

static UIView *g_overlay = nil;
static WKWebView *g_web = nil;
static UIButton *g_close_button = nil;
static BOOL g_open = NO;
static CGFloat g_inset_top = 0.0;
static CGFloat g_inset_bottom = 0.0;

static void qbo_ios_close(void);

@interface QBOCloseTarget : NSObject
@end

@implementation QBOCloseTarget
- (void)tap:(id)sender {
	(void)sender;
	qbo_ios_close();
}
@end

static QBOCloseTarget *g_close_target = nil;

static UIWindow *qbo_key_window(void) {
	for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
		if (![scene isKindOfClass:[UIWindowScene class]]) {
			continue;
		}
		for (UIWindow *window in ((UIWindowScene *)scene).windows) {
			if (window.isKeyWindow) {
				return window;
			}
		}
	}
	return [UIApplication sharedApplication].windows.firstObject;
}

static void qbo_layout_close_button(void) {
	if (g_close_button == nil || g_overlay == nil) {
		return;
	}
	[g_close_button sizeToFit];
	CGRect frame = g_close_button.frame;
	CGFloat width = frame.size.width + 32.0;
	CGFloat height = frame.size.height + 16.0;
	CGFloat top = g_overlay.safeAreaInsets.top + g_inset_top + 12.0;
	CGRect bounds = g_overlay.bounds;
	g_close_button.frame = CGRectMake(bounds.size.width - width - 16.0, top, width, height);
}

static void qbo_teardown_views(void) {
	if (g_web != nil) {
		[g_web stopLoading];
		[g_web removeFromSuperview];
		g_web = nil;
	}
	if (g_close_button != nil) {
		[g_close_button removeFromSuperview];
		g_close_button = nil;
	}
	if (g_overlay != nil) {
		[g_overlay removeFromSuperview];
		g_overlay = nil;
	}
}

static NSString *qbo_youtube_html(NSString *embed_url) {
	return [NSString stringWithFormat:
			@"<!DOCTYPE html><html><head><meta charset=\"utf-8\">"
			 "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no\">"
			 "<style>html,body{margin:0;padding:0;background:#000;height:100%%;overflow:hidden;}"
			 "iframe{position:absolute;top:0;left:0;width:100%%;height:100%%;border:0;}</style></head>"
			 "<body><iframe src=\"%@\" allow=\"autoplay; encrypted-media; fullscreen; picture-in-picture\" "
			 "allowfullscreen frameborder=\"0\"></iframe></body></html>",
			embed_url];
}

static void qbo_present(NSString *target, BOOL youtube) {
	UIWindow *window = qbo_key_window();
	UIViewController *root = window.rootViewController;
	if (root == nil || root.view == nil) {
		g_open = NO;
		return;
	}

	qbo_teardown_views();

	UIView *overlay = [[UIView alloc] initWithFrame:root.view.bounds];
	overlay.backgroundColor = [UIColor blackColor];
	overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	overlay.tag = 0x51424F54; // 'QBOT'

	WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
	config.allowsInlineMediaPlayback = YES;
	config.allowsPictureInPictureMediaPlayback = YES;
	if (@available(iOS 10.0, *)) {
		config.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
	}

	WKWebView *web = [[WKWebView alloc] initWithFrame:overlay.bounds configuration:config];
	web.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	web.backgroundColor = [UIColor blackColor];
	web.opaque = NO;
	web.allowsBackForwardNavigationGestures = NO;
	web.scrollView.scrollEnabled = NO;
	web.scrollView.bounces = NO;
	[overlay addSubview:web];

	UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
	[close setTitle:@"✕ Đóng TV" forState:UIControlStateNormal];
	[close setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
	close.titleLabel.font = [UIFont boldSystemFontOfSize:16.0];
	close.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.66];
	close.layer.cornerRadius = 18.0;
	close.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
	if (g_close_target == nil) {
		g_close_target = [[QBOCloseTarget alloc] init];
	}
	[close addTarget:g_close_target action:@selector(tap:) forControlEvents:UIControlEventTouchUpInside];
	[overlay addSubview:close];

	g_overlay = overlay;
	g_web = web;
	g_close_button = close;
	g_open = YES;

	[root.view addSubview:overlay];
	qbo_layout_close_button();

	if (youtube) {
		[web loadHTMLString:qbo_youtube_html(target) baseURL:[NSURL URLWithString:@"https://www.youtube.com"]];
	} else {
		NSURL *url = [NSURL URLWithString:target];
		if (url == nil) {
			g_open = NO;
			qbo_teardown_views();
			return;
		}
		[web loadRequest:[NSURLRequest requestWithURL:url
										   cachePolicy:NSURLRequestUseProtocolCachePolicy
									   timeoutInterval:30.0]];
	}
}

static void qbo_ios_close(void) {
	g_open = NO;
	qbo_teardown_views();
}

static bool qbo_ios_open(const char *url) {
	if (url == nullptr || url[0] == '\0') {
		return false;
	}
	NSString *target = [NSString stringWithUTF8String:url];
	if (target == nil) {
		return false;
	}
	BOOL youtube = [target containsString:@"youtube.com/embed/"] ||
			[target containsString:@"youtube-nocookie.com/embed/"] ||
			[target containsString:@"youtu.be/"];
	g_open = YES;
	dispatch_async(dispatch_get_main_queue(), ^{
		qbo_present(target, youtube);
	});
	return true;
}

/* ------------------------------------------------------- argument helpers */

static bool qbo_arg_utf8(GDExtensionConstVariantPtr variant, char *out, int out_size) {
	if (variant == nullptr || out == nullptr || out_size <= 1) {
		return false;
	}
	out[0] = '\0';
	if (g_variant_get_type(variant) != GDEXTENSION_VARIANT_TYPE_STRING) {
		return false;
	}
	void *internal = g_get_internal_ptr(GDEXTENSION_VARIANT_TYPE_STRING)(const_cast<void *>(variant));
	if (internal == nullptr) {
		return false;
	}
	GDExtensionInt length = g_string_to_utf8((GDExtensionConstStringPtr)internal, nullptr, 0);
	if (length < 0) {
		return false;
	}
	if (length > out_size - 1) {
		length = out_size - 1;
	}
	g_string_to_utf8((GDExtensionConstStringPtr)internal, out, length + 1);
	out[length] = '\0';
	return true;
}

static double qbo_arg_double(GDExtensionConstVariantPtr variant, double fallback) {
	if (variant == nullptr) {
		return fallback;
	}
	if (g_variant_get_type(variant) != GDEXTENSION_VARIANT_TYPE_FLOAT) {
		return fallback;
	}
	void *internal = g_get_internal_ptr(GDEXTENSION_VARIANT_TYPE_FLOAT)(const_cast<void *>(variant));
	if (internal == nullptr) {
		return fallback;
	}
	return *static_cast<double *>(internal);
}

static void qbo_ret_bool(GDExtensionVariantPtr r_return, bool value) {
	if (r_return == nullptr) {
		return;
	}
	GDExtensionBool flag = value ? 1 : 0;
	g_ctor_bool(r_return, &flag);
}

/* ------------------------------------------------------------ method call */

static void qbo_call(void *method_userdata, GDExtensionClassInstancePtr p_instance,
		const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count,
		GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
	(void)p_instance;
	if (r_error != nullptr) {
		r_error->error = GDEXTENSION_CALL_OK;
		r_error->argument = 0;
		r_error->expected = 0;
	}

	const int method = (int)(intptr_t)method_userdata;
	switch (method) {
		case QBO_METHOD_OPEN: {
			if (p_argument_count < 1) {
				if (r_error != nullptr) {
					r_error->error = GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS;
					r_error->expected = 1;
				}
				return;
			}
			char buffer[4096];
			const bool ok = qbo_arg_utf8(p_args[0], buffer, (int)sizeof(buffer)) && qbo_ios_open(buffer);
			qbo_ret_bool(r_return, ok);
		} break;

		case QBO_METHOD_CLOSE: {
			qbo_ios_close();
		} break;

		case QBO_METHOD_IS_OPEN: {
			qbo_ret_bool(r_return, g_open);
		} break;

		case QBO_METHOD_SET_INSETS: {
			const double top = qbo_arg_double(p_argument_count > 0 ? p_args[0] : nullptr, 0.0);
			const double bottom = qbo_arg_double(p_argument_count > 1 ? p_args[1] : nullptr, 0.0);
			g_inset_top = (CGFloat)top;
			g_inset_bottom = (CGFloat)bottom;
			dispatch_async(dispatch_get_main_queue(), ^{
				qbo_layout_close_button();
			});
		} break;

		case QBO_METHOD_RELOAD: {
			dispatch_async(dispatch_get_main_queue(), ^{
				if (g_web != nil) {
					[g_web reload];
				}
			});
		} break;

		default:
			if (r_error != nullptr) {
				r_error->error = GDEXTENSION_CALL_ERROR_INVALID_METHOD;
			}
			break;
	}
}

/* --------------------------------------------------------- class plumbing */

static GDExtensionObjectPtr qbo_create_instance(void *p_class_userdata, GDExtensionBool p_notify_postinitialize) {
	(void)p_class_userdata;
	(void)p_notify_postinitialize;
	if (g_construct_object == nullptr) {
		return nullptr;
	}
	GDExtensionObjectPtr owner = g_construct_object((GDExtensionConstStringNamePtr)g_sn_parent);
	if (owner == nullptr) {
		return nullptr;
	}
	QboInstance *instance = new QboInstance();
	instance->owner = owner;
	g_object_set_instance(owner, (GDExtensionConstStringNamePtr)g_sn_class, (GDExtensionClassInstancePtr)instance);
	return owner;
}

static void qbo_free_instance(void *p_class_userdata, GDExtensionClassInstancePtr p_instance) {
	(void)p_class_userdata;
	delete static_cast<QboInstance *>(p_instance);
}

static void qbo_register_one_method(const char *name, int id, bool has_return, GDExtensionVariantType return_type,
		int argument_count, const GDExtensionVariantType *argument_types, const char **argument_names) {
	uint64_t name_sn[1] = { 0 };
	uint64_t ret_name_sn[1] = { 0 };
	uint64_t class_sn[1] = { 0 };
	uint64_t hint_string[1] = { 0 };
	uint64_t arg_names[2][1] = { { 0 }, { 0 } };

	g_string_name_new((GDExtensionUninitializedStringNamePtr)name_sn, name, 1);
	g_string_name_new((GDExtensionUninitializedStringNamePtr)ret_name_sn, "", 1);
	g_string_name_new((GDExtensionUninitializedStringNamePtr)class_sn, "", 1);
	g_string_new((GDExtensionUninitializedStringPtr)hint_string, "");

	GDExtensionPropertyInfo return_info;
	memset(&return_info, 0, sizeof(return_info));
	return_info.type = return_type;
	return_info.name = (GDExtensionStringNamePtr)ret_name_sn;
	return_info.class_name = (GDExtensionStringNamePtr)class_sn;
	return_info.hint_string = (GDExtensionStringPtr)hint_string;
	return_info.usage = 6; // PROPERTY_USAGE_STORAGE | PROPERTY_USAGE_EDITOR

	GDExtensionPropertyInfo args_info[2];
	GDExtensionClassMethodArgumentMetadata args_meta[2];
	memset(args_info, 0, sizeof(args_info));
	memset(args_meta, 0, sizeof(args_meta));
	for (int i = 0; i < argument_count; i++) {
		g_string_name_new((GDExtensionUninitializedStringNamePtr)arg_names[i], argument_names[i], 1);
		args_info[i].type = argument_types[i];
		args_info[i].name = (GDExtensionStringNamePtr)arg_names[i];
		args_info[i].class_name = (GDExtensionStringNamePtr)class_sn;
		args_info[i].hint_string = (GDExtensionStringPtr)hint_string;
		args_info[i].usage = 6;
		args_meta[i] = GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE;
	}

	GDExtensionClassMethodInfo info;
	memset(&info, 0, sizeof(info));
	info.name = (GDExtensionStringNamePtr)name_sn;
	info.method_userdata = (void *)(intptr_t)id;
	info.call_func = qbo_call;
	info.ptrcall_func = nullptr;
	info.method_flags = 1; // GDEXTENSION_METHOD_FLAG_NORMAL
	info.has_return_value = has_return ? 1 : 0;
	info.return_value_info = has_return ? &return_info : nullptr;
	info.return_value_metadata = GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE;
	info.argument_count = (uint32_t)argument_count;
	info.arguments_info = argument_count > 0 ? args_info : nullptr;
	info.arguments_metadata = argument_count > 0 ? args_meta : nullptr;
	info.default_argument_count = 0;
	info.default_arguments = nullptr;

	g_register_method(g_library, (GDExtensionConstStringNamePtr)g_sn_class, &info);
}

static void qbo_register_class(void) {
	if (g_registered) {
		return;
	}
	g_string_name_new((GDExtensionUninitializedStringNamePtr)g_sn_class, "QBOWebViewIOS", 1);
	g_string_name_new((GDExtensionUninitializedStringNamePtr)g_sn_parent, "RefCounted", 1);

	QboClassCreationInfo info;
	memset(&info, 0, sizeof(info));
	info.is_virtual = 0;
	info.is_abstract = 0;
	info.is_exposed = 1;
	info.is_runtime = 0;
	info.create_instance_func = qbo_create_instance;
	info.free_instance_func = qbo_free_instance;
	g_register_class(g_library, (GDExtensionConstStringNamePtr)g_sn_class, (GDExtensionConstStringNamePtr)g_sn_parent, &info);

	{
		const GDExtensionVariantType types[1] = { GDEXTENSION_VARIANT_TYPE_STRING };
		const char *names[1] = { "url" };
		qbo_register_one_method("open", QBO_METHOD_OPEN, true, GDEXTENSION_VARIANT_TYPE_BOOL, 1, types, names);
	}
	qbo_register_one_method("close", QBO_METHOD_CLOSE, false, GDEXTENSION_VARIANT_TYPE_NIL, 0, nullptr, nullptr);
	qbo_register_one_method("is_open", QBO_METHOD_IS_OPEN, true, GDEXTENSION_VARIANT_TYPE_BOOL, 0, nullptr, nullptr);
	{
		const GDExtensionVariantType types[2] = { GDEXTENSION_VARIANT_TYPE_FLOAT, GDEXTENSION_VARIANT_TYPE_FLOAT };
		const char *names[2] = { "top", "bottom" };
		qbo_register_one_method("set_insets", QBO_METHOD_SET_INSETS, false, GDEXTENSION_VARIANT_TYPE_NIL, 2, types, names);
	}
	qbo_register_one_method("reload", QBO_METHOD_RELOAD, false, GDEXTENSION_VARIANT_TYPE_NIL, 0, nullptr, nullptr);

	g_registered = true;
}

static void qbo_initialize(void *p_userdata, GDExtensionInitializationLevel p_level) {
	(void)p_userdata;
	if (p_level != GDEXTENSION_INITIALIZATION_SCENE) {
		return;
	}
	qbo_register_class();
}

static void qbo_deinitialize(void *p_userdata, GDExtensionInitializationLevel p_level) {
	(void)p_userdata;
	if (p_level != GDEXTENSION_INITIALIZATION_SCENE) {
		return;
	}
	if (g_registered) {
		dispatch_async(dispatch_get_main_queue(), ^{
			qbo_ios_close();
		});
	}
	g_registered = false;
}

/* ------------------------------------------------------------- entry point */

extern "C" GDExtensionBool qbo_webview_ios_init(GDExtensionInterfaceGetProcAddress p_get_proc_address,
		GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	if (p_get_proc_address == nullptr || r_initialization == nullptr) {
		return 0;
	}
	g_library = p_library;

	g_register_class = (QboFnRegisterClass)p_get_proc_address("classdb_register_extension_class6");
	g_register_method = (QboFnRegisterMethod)p_get_proc_address("classdb_register_extension_class_method");
	g_construct_object = (QboFnConstructObject)p_get_proc_address("classdb_construct_object3");
	g_object_set_instance = (QboFnObjectSetInstance)p_get_proc_address("object_set_instance");
	g_string_name_new = (QboFnStringNameNew)p_get_proc_address("string_name_new_with_latin1_chars");
	g_string_new = (QboFnStringNew)p_get_proc_address("string_new_with_latin1_chars");
	g_get_from_ctor = (QboFnGetFromVariantCtor)p_get_proc_address("get_variant_from_type_constructor");
	g_get_internal_ptr = (QboFnGetInternalPtr)p_get_proc_address("variant_get_ptr_internal_getter");
	g_string_to_utf8 = (QboFnStringToUtf8)p_get_proc_address("string_to_utf8_chars");
	g_variant_get_type = (QboFnVariantGetType)p_get_proc_address("variant_get_type");

	if (g_register_class == nullptr || g_register_method == nullptr || g_construct_object == nullptr ||
			g_object_set_instance == nullptr || g_string_name_new == nullptr || g_string_new == nullptr ||
			g_get_from_ctor == nullptr || g_get_internal_ptr == nullptr || g_string_to_utf8 == nullptr ||
			g_variant_get_type == nullptr) {
		NSLog(@"[QBO] WKWebView extension: missing GDExtension interface function");
		return 0;
	}

	g_ctor_bool = g_get_from_ctor(GDEXTENSION_VARIANT_TYPE_BOOL);
	g_ctor_float = g_get_from_ctor(GDEXTENSION_VARIANT_TYPE_FLOAT);
	if (g_ctor_bool == nullptr || g_ctor_float == nullptr) {
		return 0;
	}

	r_initialization->minimum_initialization_level = GDEXTENSION_INITIALIZATION_SCENE;
	r_initialization->userdata = nullptr;
	r_initialization->initialize = qbo_initialize;
	r_initialization->deinitialize = qbo_deinitialize;
	return 1;
}
