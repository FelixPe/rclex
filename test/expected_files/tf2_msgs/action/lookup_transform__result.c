// clang-format off
#include "lookup_transform__result.h"
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

#include <tf2_msgs/msg/detail/tf2_error__functions.h>
#include <tf2_msgs/msg/detail/tf2_error__struct.h>

#include <tf2_msgs/action/detail/lookup_transform__functions.h>
#include <tf2_msgs/action/detail/lookup_transform__struct.h>
#include <tf2_msgs/action/detail/lookup_transform__type_support.h>

#include <stddef.h>
#include <stdint.h>
#include <string.h>

ERL_NIF_TERM nif_tf2_msgs_action_lookup_transform__result_type_support(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  ignore_unused(argv);

  if (argc != 0) return enif_make_badarg(env);

  const rosidl_message_type_support_t *ts_p = ROSIDL_GET_MSG_TYPE_SUPPORT(tf2_msgs, action, LookupTransform_Result);
  rosidl_message_type_support_t *obj = enif_alloc_resource(rt_rosidl_message_type_support_t, sizeof(rosidl_message_type_support_t));
  *obj = *ts_p;
  ERL_NIF_TERM term = enif_make_resource(env, obj);
  enif_release_resource(obj);

  return term;
}

ERL_NIF_TERM nif_tf2_msgs_action_lookup_transform__result_create(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  ignore_unused(argv);

  if (argc != 0) return enif_make_badarg(env);

  tf2_msgs__action__LookupTransform_Result *message_p = tf2_msgs__action__LookupTransform_Result__create();
  if (message_p == NULL) return raise(env, __FILE__, __LINE__);

  void **obj = enif_alloc_resource(rt_ros_message, sizeof(void *));
  *obj = (void *)message_p;
  ERL_NIF_TERM term = enif_make_resource(env, obj);
  enif_release_resource(obj);

  return term;
}

ERL_NIF_TERM nif_tf2_msgs_action_lookup_transform__result_destroy(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 1) return enif_make_badarg(env);

  void **ros_message_pp;
  if (!enif_get_resource(env, argv[0], rt_ros_message, (void **)&ros_message_pp))
    return enif_make_badarg(env);

  tf2_msgs__action__LookupTransform_Result *message_p = (tf2_msgs__action__LookupTransform_Result *)*ros_message_pp;
  tf2_msgs__action__LookupTransform_Result__destroy(message_p);

  return atom_ok;
}

ERL_NIF_TERM nif_tf2_msgs_action_lookup_transform__result_set(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 2) return enif_make_badarg(env);

  void **ros_message_pp;
  if (!enif_get_resource(env, argv[0], rt_ros_message, (void **)&ros_message_pp))
    return enif_make_badarg(env);

  tf2_msgs__action__LookupTransform_Result *message_p = (tf2_msgs__action__LookupTransform_Result *)*ros_message_pp;

  int arity;
  const ERL_NIF_TERM *tuple;
  if (!enif_get_tuple(env, argv[1], &arity, &tuple)) return enif_make_badarg(env);

  int transform_arity;
  const ERL_NIF_TERM *transform_tuple;
  if (!enif_get_tuple(env, tuple[0], &transform_arity, &transform_tuple))
    return enif_make_badarg(env);

  int transform_header_arity;
  const ERL_NIF_TERM *transform_header_tuple;
  if (!enif_get_tuple(env, transform_tuple[0], &transform_header_arity, &transform_header_tuple))
    return enif_make_badarg(env);

  int transform_header_stamp_arity;
  const ERL_NIF_TERM *transform_header_stamp_tuple;
  if (!enif_get_tuple(env, transform_header_tuple[0], &transform_header_stamp_arity, &transform_header_stamp_tuple))
    return enif_make_badarg(env);

  int transform_header_stamp_sec;
  if (!enif_get_int(env, transform_header_stamp_tuple[0], &transform_header_stamp_sec))
    return enif_make_badarg(env);
  message_p->transform.header.stamp.sec = transform_header_stamp_sec;

  unsigned int transform_header_stamp_nanosec;
  if (!enif_get_uint(env, transform_header_stamp_tuple[1], &transform_header_stamp_nanosec))
    return enif_make_badarg(env);
  message_p->transform.header.stamp.nanosec = transform_header_stamp_nanosec;

  ErlNifBinary transform_header_frame_id_binary;
  if (!enif_inspect_binary(env, transform_header_tuple[1], &transform_header_frame_id_binary))
    return enif_make_badarg(env);

  if (!rosidl_runtime_c__String__assignn(&(message_p->transform.header.frame_id), (const char *)transform_header_frame_id_binary.data, transform_header_frame_id_binary.size))
    return raise(env, __FILE__, __LINE__);

  ErlNifBinary transform_child_frame_id_binary;
  if (!enif_inspect_binary(env, transform_tuple[1], &transform_child_frame_id_binary))
    return enif_make_badarg(env);

  if (!rosidl_runtime_c__String__assignn(&(message_p->transform.child_frame_id), (const char *)transform_child_frame_id_binary.data, transform_child_frame_id_binary.size))
    return raise(env, __FILE__, __LINE__);

  int transform_transform_arity;
  const ERL_NIF_TERM *transform_transform_tuple;
  if (!enif_get_tuple(env, transform_tuple[2], &transform_transform_arity, &transform_transform_tuple))
    return enif_make_badarg(env);

  int transform_transform_translation_arity;
  const ERL_NIF_TERM *transform_transform_translation_tuple;
  if (!enif_get_tuple(env, transform_transform_tuple[0], &transform_transform_translation_arity, &transform_transform_translation_tuple))
    return enif_make_badarg(env);

  double transform_transform_translation_x;
  if (!enif_get_double(env, transform_transform_translation_tuple[0], &transform_transform_translation_x))
    return enif_make_badarg(env);
  message_p->transform.transform.translation.x = transform_transform_translation_x;

  double transform_transform_translation_y;
  if (!enif_get_double(env, transform_transform_translation_tuple[1], &transform_transform_translation_y))
    return enif_make_badarg(env);
  message_p->transform.transform.translation.y = transform_transform_translation_y;

  double transform_transform_translation_z;
  if (!enif_get_double(env, transform_transform_translation_tuple[2], &transform_transform_translation_z))
    return enif_make_badarg(env);
  message_p->transform.transform.translation.z = transform_transform_translation_z;

  int transform_transform_rotation_arity;
  const ERL_NIF_TERM *transform_transform_rotation_tuple;
  if (!enif_get_tuple(env, transform_transform_tuple[1], &transform_transform_rotation_arity, &transform_transform_rotation_tuple))
    return enif_make_badarg(env);

  double transform_transform_rotation_x;
  if (!enif_get_double(env, transform_transform_rotation_tuple[0], &transform_transform_rotation_x))
    return enif_make_badarg(env);
  message_p->transform.transform.rotation.x = transform_transform_rotation_x;

  double transform_transform_rotation_y;
  if (!enif_get_double(env, transform_transform_rotation_tuple[1], &transform_transform_rotation_y))
    return enif_make_badarg(env);
  message_p->transform.transform.rotation.y = transform_transform_rotation_y;

  double transform_transform_rotation_z;
  if (!enif_get_double(env, transform_transform_rotation_tuple[2], &transform_transform_rotation_z))
    return enif_make_badarg(env);
  message_p->transform.transform.rotation.z = transform_transform_rotation_z;

  double transform_transform_rotation_w;
  if (!enif_get_double(env, transform_transform_rotation_tuple[3], &transform_transform_rotation_w))
    return enif_make_badarg(env);
  message_p->transform.transform.rotation.w = transform_transform_rotation_w;

  int error_arity;
  const ERL_NIF_TERM *error_tuple;
  if (!enif_get_tuple(env, tuple[1], &error_arity, &error_tuple))
    return enif_make_badarg(env);

  unsigned int error_error;
  if (!enif_get_uint(env, error_tuple[0], &error_error))
    return enif_make_badarg(env);
  message_p->error.error = error_error;

  ErlNifBinary error_error_string_binary;
  if (!enif_inspect_binary(env, error_tuple[1], &error_error_string_binary))
    return enif_make_badarg(env);

  if (!rosidl_runtime_c__String__assignn(&(message_p->error.error_string), (const char *)error_error_string_binary.data, error_error_string_binary.size))
    return raise(env, __FILE__, __LINE__);

  return atom_ok;
}

ERL_NIF_TERM nif_tf2_msgs_action_lookup_transform__result_get(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 1) return enif_make_badarg(env);

  void **ros_message_pp;
  if (!enif_get_resource(env, argv[0], rt_ros_message, (void **)&ros_message_pp))
    return enif_make_badarg(env);

  tf2_msgs__action__LookupTransform_Result *message_p = (tf2_msgs__action__LookupTransform_Result *)*ros_message_pp;

  return enif_make_tuple(env, 2,
    enif_make_tuple(env, 3,
      enif_make_tuple(env, 2,
        enif_make_tuple(env, 2,
          enif_make_int(env, message_p->transform.header.stamp.sec),
          enif_make_uint(env, message_p->transform.header.stamp.nanosec)
        ),
        enif_make_binary_wrapper(env, message_p->transform.header.frame_id.data, message_p->transform.header.frame_id.size)
      ),
      enif_make_binary_wrapper(env, message_p->transform.child_frame_id.data, message_p->transform.child_frame_id.size),
      enif_make_tuple(env, 2,
        enif_make_tuple(env, 3,
          enif_make_double(env, message_p->transform.transform.translation.x),
          enif_make_double(env, message_p->transform.transform.translation.y),
          enif_make_double(env, message_p->transform.transform.translation.z)
        ),
        enif_make_tuple(env, 4,
          enif_make_double(env, message_p->transform.transform.rotation.x),
          enif_make_double(env, message_p->transform.transform.rotation.y),
          enif_make_double(env, message_p->transform.transform.rotation.z),
          enif_make_double(env, message_p->transform.transform.rotation.w)
        )
      )
    ),
    enif_make_tuple(env, 2,
      enif_make_uint(env, message_p->error.error),
      enif_make_binary_wrapper(env, message_p->error.error_string.data, message_p->error.error_string.size)
    )
  );
}
// clang-format on
