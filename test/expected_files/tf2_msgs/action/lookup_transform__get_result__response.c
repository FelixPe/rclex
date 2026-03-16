// clang-format off
#include "lookup_transform__get_result__response.h"
#include "../../../macros.h"
#include "../../../resource_types.h"
#include "../../../terms.h"

#include <erl_nif.h>

#include <rosidl_runtime_c/message_type_support_struct.h>
#include <rosidl_runtime_c/primitives_sequence.h>
#include <rosidl_runtime_c/primitives_sequence_functions.h>
#include <rosidl_runtime_c/string.h>
#include <rosidl_runtime_c/string_functions.h>

#include <builtin_interfaces/msg/detail/time__functions.h>
#include <builtin_interfaces/msg/detail/time__struct.h>

#include <geometry_msgs/msg/detail/quaternion__functions.h>
#include <geometry_msgs/msg/detail/quaternion__struct.h>

#include <geometry_msgs/msg/detail/transform__functions.h>
#include <geometry_msgs/msg/detail/transform__struct.h>

#include <geometry_msgs/msg/detail/transform_stamped__functions.h>
#include <geometry_msgs/msg/detail/transform_stamped__struct.h>

#include <geometry_msgs/msg/detail/vector3__functions.h>
#include <geometry_msgs/msg/detail/vector3__struct.h>

#include <std_msgs/msg/detail/header__functions.h>
#include <std_msgs/msg/detail/header__struct.h>

#include <tf2_msgs/action/detail/lookup_transform__functions.h>
#include <tf2_msgs/action/detail/lookup_transform__struct.h>

#include <tf2_msgs/msg/detail/tf2_error__functions.h>
#include <tf2_msgs/msg/detail/tf2_error__struct.h>

#include <tf2_msgs/action/detail/lookup_transform__functions.h>
#include <tf2_msgs/action/detail/lookup_transform__struct.h>
#include <tf2_msgs/action/detail/lookup_transform__type_support.h>

#include <stddef.h>
#include <stdint.h>
#include <string.h>

ERL_NIF_TERM nif_tf2_msgs_action_lookup_transform__get_result__response_type_support(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  ignore_unused(argv);

  if (argc != 0) return enif_make_badarg(env);

  const rosidl_message_type_support_t *ts_p = ROSIDL_GET_MSG_TYPE_SUPPORT(tf2_msgs, action, LookupTransform_GetResult_Response);
  rosidl_message_type_support_t *obj = enif_alloc_resource(rt_rosidl_message_type_support_t, sizeof(rosidl_message_type_support_t));
  *obj = *ts_p;
  ERL_NIF_TERM term = enif_make_resource(env, obj);
  enif_release_resource(obj);

  return term;
}

ERL_NIF_TERM nif_tf2_msgs_action_lookup_transform__get_result__response_create(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  ignore_unused(argv);

  if (argc != 0) return enif_make_badarg(env);

  tf2_msgs__action__LookupTransform_GetResult_Response *message_p = tf2_msgs__action__LookupTransform_GetResult_Response__create();
  if (message_p == NULL) return raise(env, __FILE__, __LINE__);

  void **obj = enif_alloc_resource(rt_ros_message, sizeof(void *));
  *obj = (void *)message_p;
  ERL_NIF_TERM term = enif_make_resource(env, obj);
  enif_release_resource(obj);

  return term;
}

ERL_NIF_TERM nif_tf2_msgs_action_lookup_transform__get_result__response_destroy(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 1) return enif_make_badarg(env);

  void **ros_message_pp;
  if (!enif_get_resource(env, argv[0], rt_ros_message, (void **)&ros_message_pp))
    return enif_make_badarg(env);

  tf2_msgs__action__LookupTransform_GetResult_Response *message_p = (tf2_msgs__action__LookupTransform_GetResult_Response *)*ros_message_pp;
  tf2_msgs__action__LookupTransform_GetResult_Response__destroy(message_p);

  return atom_ok;
}

ERL_NIF_TERM nif_tf2_msgs_action_lookup_transform__get_result__response_set(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 2) return enif_make_badarg(env);

  void **ros_message_pp;
  if (!enif_get_resource(env, argv[0], rt_ros_message, (void **)&ros_message_pp))
    return enif_make_badarg(env);

  tf2_msgs__action__LookupTransform_GetResult_Response *message_p = (tf2_msgs__action__LookupTransform_GetResult_Response *)*ros_message_pp;

  int arity;
  const ERL_NIF_TERM *tuple;
  if (!enif_get_tuple(env, argv[1], &arity, &tuple)) return enif_make_badarg(env);

  unsigned int status;
  if (!enif_get_uint(env, tuple[0], &status))
    return enif_make_badarg(env);
  message_p->status = status;

  int result_arity;
  const ERL_NIF_TERM *result_tuple;
  if (!enif_get_tuple(env, tuple[1], &result_arity, &result_tuple))
    return enif_make_badarg(env);

  int result_transform_arity;
  const ERL_NIF_TERM *result_transform_tuple;
  if (!enif_get_tuple(env, result_tuple[0], &result_transform_arity, &result_transform_tuple))
    return enif_make_badarg(env);

  int result_transform_header_arity;
  const ERL_NIF_TERM *result_transform_header_tuple;
  if (!enif_get_tuple(env, result_transform_tuple[0], &result_transform_header_arity, &result_transform_header_tuple))
    return enif_make_badarg(env);

  int result_transform_header_stamp_arity;
  const ERL_NIF_TERM *result_transform_header_stamp_tuple;
  if (!enif_get_tuple(env, result_transform_header_tuple[0], &result_transform_header_stamp_arity, &result_transform_header_stamp_tuple))
    return enif_make_badarg(env);

  int result_transform_header_stamp_sec;
  if (!enif_get_int(env, result_transform_header_stamp_tuple[0], &result_transform_header_stamp_sec))
    return enif_make_badarg(env);
  message_p->result.transform.header.stamp.sec = result_transform_header_stamp_sec;

  unsigned int result_transform_header_stamp_nanosec;
  if (!enif_get_uint(env, result_transform_header_stamp_tuple[1], &result_transform_header_stamp_nanosec))
    return enif_make_badarg(env);
  message_p->result.transform.header.stamp.nanosec = result_transform_header_stamp_nanosec;

  ErlNifBinary result_transform_header_frame_id_binary;
  if (!enif_inspect_binary(env, result_transform_header_tuple[1], &result_transform_header_frame_id_binary))
    return enif_make_badarg(env);

  if (!rosidl_runtime_c__String__assignn(&(message_p->result.transform.header.frame_id), (const char *)result_transform_header_frame_id_binary.data, result_transform_header_frame_id_binary.size))
    return raise(env, __FILE__, __LINE__);

  ErlNifBinary result_transform_child_frame_id_binary;
  if (!enif_inspect_binary(env, result_transform_tuple[1], &result_transform_child_frame_id_binary))
    return enif_make_badarg(env);

  if (!rosidl_runtime_c__String__assignn(&(message_p->result.transform.child_frame_id), (const char *)result_transform_child_frame_id_binary.data, result_transform_child_frame_id_binary.size))
    return raise(env, __FILE__, __LINE__);

  int result_transform_transform_arity;
  const ERL_NIF_TERM *result_transform_transform_tuple;
  if (!enif_get_tuple(env, result_transform_tuple[2], &result_transform_transform_arity, &result_transform_transform_tuple))
    return enif_make_badarg(env);

  int result_transform_transform_translation_arity;
  const ERL_NIF_TERM *result_transform_transform_translation_tuple;
  if (!enif_get_tuple(env, result_transform_transform_tuple[0], &result_transform_transform_translation_arity, &result_transform_transform_translation_tuple))
    return enif_make_badarg(env);

  double result_transform_transform_translation_x;
  if (!enif_get_double(env, result_transform_transform_translation_tuple[0], &result_transform_transform_translation_x))
    return enif_make_badarg(env);
  message_p->result.transform.transform.translation.x = result_transform_transform_translation_x;

  double result_transform_transform_translation_y;
  if (!enif_get_double(env, result_transform_transform_translation_tuple[1], &result_transform_transform_translation_y))
    return enif_make_badarg(env);
  message_p->result.transform.transform.translation.y = result_transform_transform_translation_y;

  double result_transform_transform_translation_z;
  if (!enif_get_double(env, result_transform_transform_translation_tuple[2], &result_transform_transform_translation_z))
    return enif_make_badarg(env);
  message_p->result.transform.transform.translation.z = result_transform_transform_translation_z;

  int result_transform_transform_rotation_arity;
  const ERL_NIF_TERM *result_transform_transform_rotation_tuple;
  if (!enif_get_tuple(env, result_transform_transform_tuple[1], &result_transform_transform_rotation_arity, &result_transform_transform_rotation_tuple))
    return enif_make_badarg(env);

  double result_transform_transform_rotation_x;
  if (!enif_get_double(env, result_transform_transform_rotation_tuple[0], &result_transform_transform_rotation_x))
    return enif_make_badarg(env);
  message_p->result.transform.transform.rotation.x = result_transform_transform_rotation_x;

  double result_transform_transform_rotation_y;
  if (!enif_get_double(env, result_transform_transform_rotation_tuple[1], &result_transform_transform_rotation_y))
    return enif_make_badarg(env);
  message_p->result.transform.transform.rotation.y = result_transform_transform_rotation_y;

  double result_transform_transform_rotation_z;
  if (!enif_get_double(env, result_transform_transform_rotation_tuple[2], &result_transform_transform_rotation_z))
    return enif_make_badarg(env);
  message_p->result.transform.transform.rotation.z = result_transform_transform_rotation_z;

  double result_transform_transform_rotation_w;
  if (!enif_get_double(env, result_transform_transform_rotation_tuple[3], &result_transform_transform_rotation_w))
    return enif_make_badarg(env);
  message_p->result.transform.transform.rotation.w = result_transform_transform_rotation_w;

  int result_error_arity;
  const ERL_NIF_TERM *result_error_tuple;
  if (!enif_get_tuple(env, result_tuple[1], &result_error_arity, &result_error_tuple))
    return enif_make_badarg(env);

  unsigned int result_error_error;
  if (!enif_get_uint(env, result_error_tuple[0], &result_error_error))
    return enif_make_badarg(env);
  message_p->result.error.error = result_error_error;

  ErlNifBinary result_error_error_string_binary;
  if (!enif_inspect_binary(env, result_error_tuple[1], &result_error_error_string_binary))
    return enif_make_badarg(env);

  if (!rosidl_runtime_c__String__assignn(&(message_p->result.error.error_string), (const char *)result_error_error_string_binary.data, result_error_error_string_binary.size))
    return raise(env, __FILE__, __LINE__);

  return atom_ok;
}

ERL_NIF_TERM nif_tf2_msgs_action_lookup_transform__get_result__response_get(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 1) return enif_make_badarg(env);

  void **ros_message_pp;
  if (!enif_get_resource(env, argv[0], rt_ros_message, (void **)&ros_message_pp))
    return enif_make_badarg(env);

  tf2_msgs__action__LookupTransform_GetResult_Response *message_p = (tf2_msgs__action__LookupTransform_GetResult_Response *)*ros_message_pp;

  ERL_NIF_TERM result_transform_header_frame_id_term = enif_make_binary_wrapper(env, message_p->result.transform.header.frame_id.data, message_p->result.transform.header.frame_id.size);
  if (enif_is_exception(env, result_transform_header_frame_id_term))
    return result_transform_header_frame_id_term;
  ERL_NIF_TERM result_transform_child_frame_id_term = enif_make_binary_wrapper(env, message_p->result.transform.child_frame_id.data, message_p->result.transform.child_frame_id.size);
  if (enif_is_exception(env, result_transform_child_frame_id_term))
    return result_transform_child_frame_id_term;
  ERL_NIF_TERM result_error_error_string_term = enif_make_binary_wrapper(env, message_p->result.error.error_string.data, message_p->result.error.error_string.size);
  if (enif_is_exception(env, result_error_error_string_term))
    return result_error_error_string_term;
  return enif_make_tuple(env, 2,
    enif_make_uint(env, message_p->status),
    enif_make_tuple(env, 2,
      enif_make_tuple(env, 3,
        enif_make_tuple(env, 2,
          enif_make_tuple(env, 2,
            enif_make_int(env, message_p->result.transform.header.stamp.sec),
            enif_make_uint(env, message_p->result.transform.header.stamp.nanosec)
          ),
          result_transform_header_frame_id_term
        ),
        result_transform_child_frame_id_term,
        enif_make_tuple(env, 2,
          enif_make_tuple(env, 3,
            enif_make_double(env, message_p->result.transform.transform.translation.x),
            enif_make_double(env, message_p->result.transform.transform.translation.y),
            enif_make_double(env, message_p->result.transform.transform.translation.z)
          ),
          enif_make_tuple(env, 4,
            enif_make_double(env, message_p->result.transform.transform.rotation.x),
            enif_make_double(env, message_p->result.transform.transform.rotation.y),
            enif_make_double(env, message_p->result.transform.transform.rotation.z),
            enif_make_double(env, message_p->result.transform.transform.rotation.w)
          )
        )
      ),
      enif_make_tuple(env, 2,
        enif_make_uint(env, message_p->result.error.error),
        result_error_error_string_term
      )
    )
  );
}
// clang-format on
