/**************************************************************************/
/*  qbo_gdextension.h                                                     */
/*                                                                        */
/*  Minimal subset of the Godot 4.7 GDExtension C interface.              */
/*                                                                        */
/*  Only the declarations actually used by the QBOWebViewIOS extension    */
/*  are kept here so the plugin can be compiled with nothing but the iOS  */
/*  SDK (no engine headers, no godot-cpp).  The declarations mirror       */
/*  `core/extension/gdextension_interface.h` of Godot 4.7 verbatim.       */
/*                                                                        */
/*  Layouts are ABI: do not reorder or resize anything.                   */
/**************************************************************************/
#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ------------------------------------------------------------------ types */

typedef void *GDExtensionVariantPtr;
typedef const void *GDExtensionConstVariantPtr;
typedef void *GDExtensionUninitializedVariantPtr;
typedef void *GDExtensionStringNamePtr;
typedef const void *GDExtensionConstStringNamePtr;
typedef void *GDExtensionUninitializedStringNamePtr;
typedef void *GDExtensionStringPtr;
typedef const void *GDExtensionConstStringPtr;
typedef void *GDExtensionUninitializedStringPtr;
typedef void *GDExtensionObjectPtr;
typedef void *GDExtensionTypePtr;
typedef const void *GDExtensionConstTypePtr;
typedef void *GDExtensionClassLibraryPtr;
typedef void *GDExtensionClassInstancePtr;
typedef int64_t GDExtensionInt;
typedef uint8_t GDExtensionBool;

typedef enum {
	GDEXTENSION_VARIANT_TYPE_NIL,

	/*  atomic types */
	GDEXTENSION_VARIANT_TYPE_BOOL,
	GDEXTENSION_VARIANT_TYPE_INT,
	GDEXTENSION_VARIANT_TYPE_FLOAT,
	GDEXTENSION_VARIANT_TYPE_STRING,

	/* math types */
	GDEXTENSION_VARIANT_TYPE_VECTOR2,
	GDEXTENSION_VARIANT_TYPE_VECTOR2I,
	GDEXTENSION_VARIANT_TYPE_RECT2,
	GDEXTENSION_VARIANT_TYPE_RECT2I,
	GDEXTENSION_VARIANT_TYPE_VECTOR3,
	GDEXTENSION_VARIANT_TYPE_VECTOR3I,
	GDEXTENSION_VARIANT_TYPE_TRANSFORM2D,
	GDEXTENSION_VARIANT_TYPE_VECTOR4,
	GDEXTENSION_VARIANT_TYPE_VECTOR4I,
	GDEXTENSION_VARIANT_TYPE_PLANE,
	GDEXTENSION_VARIANT_TYPE_QUATERNION,
	GDEXTENSION_VARIANT_TYPE_AABB,
	GDEXTENSION_VARIANT_TYPE_BASIS,
	GDEXTENSION_VARIANT_TYPE_TRANSFORM3D,
	GDEXTENSION_VARIANT_TYPE_PROJECTION,

	/* misc types */
	GDEXTENSION_VARIANT_TYPE_COLOR,
	GDEXTENSION_VARIANT_TYPE_STRING_NAME,
	GDEXTENSION_VARIANT_TYPE_NODE_PATH,
	GDEXTENSION_VARIANT_TYPE_RID,
	GDEXTENSION_VARIANT_TYPE_OBJECT,
	GDEXTENSION_VARIANT_TYPE_CALLABLE,
	GDEXTENSION_VARIANT_TYPE_SIGNAL,
	GDEXTENSION_VARIANT_TYPE_DICTIONARY,
	GDEXTENSION_VARIANT_TYPE_ARRAY,

	/* typed arrays */
	GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY,
	GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY,
	GDEXTENSION_VARIANT_TYPE_PACKED_INT64_ARRAY,
	GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY,
	GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT64_ARRAY,
	GDEXTENSION_VARIANT_TYPE_PACKED_STRING_ARRAY,
	GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR2_ARRAY,
	GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR3_ARRAY,
	GDEXTENSION_VARIANT_TYPE_PACKED_COLOR_ARRAY,
	GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR4_ARRAY,

	GDEXTENSION_VARIANT_TYPE_VARIANT_MAX
} GDExtensionVariantType;

typedef enum {
	GDEXTENSION_CALL_OK,
	GDEXTENSION_CALL_ERROR_INVALID_METHOD,
	GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT,
	GDEXTENSION_CALL_ERROR_TOO_MANY_ARGUMENTS,
	GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS,
	GDEXTENSION_CALL_ERROR_INSTANCE_IS_NULL,
	GDEXTENSION_CALL_ERROR_METHOD_NOT_CONST,
} GDExtensionCallErrorType;

typedef struct {
	GDExtensionCallErrorType error;
	int32_t argument;
	int32_t expected;
} GDExtensionCallError;

typedef void (*GDExtensionVariantFromTypeConstructorFunc)(GDExtensionUninitializedVariantPtr, GDExtensionTypePtr);
typedef void *(*GDExtensionVariantGetInternalPtrFunc)(GDExtensionVariantPtr);

/* ------------------------------------------------------- class registration */

typedef enum {
	GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE,
	GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_INT8,
	GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_INT16,
	GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_INT32,
	GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_INT64,
	GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_UINT8,
	GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_UINT16,
	GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_UINT32,
	GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_UINT64,
	GDEXTENSION_METHOD_ARGUMENT_METADATA_REAL_IS_FLOAT,
	GDEXTENSION_METHOD_ARGUMENT_METADATA_REAL_IS_DOUBLE,
	GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_CHAR16,
	GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_CHAR32,
} GDExtensionClassMethodArgumentMetadata;

typedef struct {
	GDExtensionVariantType type;
	GDExtensionStringNamePtr name;
	GDExtensionStringNamePtr class_name;
	uint32_t hint;
	GDExtensionStringPtr hint_string;
	uint32_t usage;
} GDExtensionPropertyInfo;

typedef void (*GDExtensionClassMethodCall)(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error);
typedef void (*GDExtensionClassMethodPtrCall)(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstTypePtr *p_args, GDExtensionTypePtr r_ret);

typedef struct {
	GDExtensionStringNamePtr name;
	void *method_userdata;
	GDExtensionClassMethodCall call_func;
	GDExtensionClassMethodPtrCall ptrcall_func;
	uint32_t method_flags;
	GDExtensionBool has_return_value;
	GDExtensionPropertyInfo *return_value_info;
	GDExtensionClassMethodArgumentMetadata return_value_metadata;
	uint32_t argument_count;
	GDExtensionPropertyInfo *arguments_info;
	GDExtensionClassMethodArgumentMetadata *arguments_metadata;
	uint32_t default_argument_count;
	GDExtensionVariantPtr *default_arguments;
} GDExtensionClassMethodInfo;

typedef GDExtensionObjectPtr (*GDExtensionClassCreateInstance3)(void *p_class_userdata, GDExtensionBool p_notify_postinitialize);
typedef void (*GDExtensionClassFreeInstance)(void *p_class_userdata, GDExtensionClassInstancePtr p_instance);

/* GDExtensionClassCreationInfo6 (Godot 4.7). */
typedef struct {
	GDExtensionBool is_virtual;
	GDExtensionBool is_abstract;
	GDExtensionBool is_exposed;
	GDExtensionBool is_runtime;
	GDExtensionConstStringPtr icon_path;
	void *set_func;
	void *get_func;
	void *get_property_list_func;
	void *free_property_list_func;
	void *property_can_revert_func;
	void *property_get_revert_func;
	void *validate_property_func;
	void *notification_func;
	void *to_string_func;
	void *reference_func;
	void *unreference_func;
	GDExtensionClassCreateInstance3 create_instance_func;
	GDExtensionClassFreeInstance free_instance_func;
	void *recreate_instance_func;
	void *get_virtual_func;
	void *get_virtual_call_data_func;
	void *call_virtual_with_data_func;
	void *class_userdata;
} QboClassCreationInfo;

typedef enum {
	GDEXTENSION_INITIALIZATION_CORE,
	GDEXTENSION_INITIALIZATION_SERVERS,
	GDEXTENSION_INITIALIZATION_SCENE,
	GDEXTENSION_INITIALIZATION_EDITOR,
	GDEXTENSION_MAX_INITIALIZATION_LEVEL,
} GDExtensionInitializationLevel;

typedef void (*GDExtensionInitializeCallback)(void *p_userdata, GDExtensionInitializationLevel p_level);
typedef void (*GDExtensionDeinitializeCallback)(void *p_userdata, GDExtensionInitializationLevel p_level);

typedef struct {
	GDExtensionInitializationLevel minimum_initialization_level;
	void *userdata;
	GDExtensionInitializeCallback initialize;
	GDExtensionDeinitializeCallback deinitialize;
} GDExtensionInitialization;

typedef void (*GDExtensionInterfaceFunctionPtr)();
typedef GDExtensionInterfaceFunctionPtr (*GDExtensionInterfaceGetProcAddress)(const char *p_function_name);

typedef GDExtensionBool (*GDExtensionInitializationFunction)(GDExtensionInterfaceGetProcAddress p_get_proc_address, GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization);

/* -------------------------------------------------------- used interface fns */

typedef void (*QboFnRegisterClass)(GDExtensionClassLibraryPtr p_library, GDExtensionConstStringNamePtr p_class_name, GDExtensionConstStringNamePtr p_parent_class_name, const QboClassCreationInfo *p_extension_funcs);
typedef void (*QboFnRegisterMethod)(GDExtensionClassLibraryPtr p_library, GDExtensionConstStringNamePtr p_class_name, const GDExtensionClassMethodInfo *p_method_info);
typedef GDExtensionObjectPtr (*QboFnConstructObject)(GDExtensionConstStringNamePtr p_classname);
typedef void (*QboFnObjectSetInstance)(GDExtensionObjectPtr p_o, GDExtensionConstStringNamePtr p_classname, GDExtensionClassInstancePtr p_instance);
typedef void (*QboFnStringNameNew)(GDExtensionUninitializedStringNamePtr r_dest, const char *p_contents, GDExtensionBool p_is_static);
typedef void (*QboFnStringNew)(GDExtensionUninitializedStringPtr r_dest, const char *p_contents);
typedef GDExtensionVariantFromTypeConstructorFunc (*QboFnGetFromVariantCtor)(GDExtensionVariantType p_type);
typedef GDExtensionVariantGetInternalPtrFunc (*QboFnGetInternalPtr)(GDExtensionVariantType p_type);
typedef GDExtensionInt (*QboFnStringToUtf8)(GDExtensionConstStringPtr p_self, char *r_text, GDExtensionInt p_max_write_length);
typedef GDExtensionVariantType (*QboFnVariantGetType)(GDExtensionConstVariantPtr p_self);

#ifdef __cplusplus
}
#endif
