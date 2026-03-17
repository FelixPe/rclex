// clang-format off
#include "lookup_transform__goal.h"
#include "../../../macros.h"
#include "../../../resource_types.h"
#include "../../../terms.h"

#include <erl_nif.h>

#include <rosidl_runtime_c/message_type_support_struct.h>
#include <rosidl_runtime_c/primitives_sequence.h>
#include <rosidl_runtime_c/primitives_sequence_functions.h>
#include <rosidl_runtime_c/string.h>
#include <rosidl_runtime_c/string_functions.h>

#include <builtin_interfaces/msg/detail/duration__functions.h>
#include <builtin_interfaces/msg/detail/duration__struct.h>

#include <builtin_interfaces/msg/detail/time__functions.h>
#include <builtin_interfaces/msg/detail/time__struct.h>

#include <tf2_msgs/action/detail/lookup_transform__functions.h>
#include <tf2_msgs/action/detail/lookup_transform__struct.h>
#include <tf2_msgs/action/detail/lookup_transform__type_support.h>

#include <math.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

ERL_NIF_TERM nif_tf2_msgs_action_lookup_transform__goal_type_support(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  ignore_unused(argv);

  if (argc != 0) return enif_make_badarg(env);

  const rosidl_message_type_support_t *ts_p = ROSIDL_GET_MSG_TYPE_SUPPORT(tf2_msgs, action, LookupTransform_Goal);
  rosidl_message_type_support_t *obj = enif_alloc_resource(rt_rosidl_message_type_support_t, sizeof(rosidl_message_type_support_t));
  *obj = *ts_p;
  ERL_NIF_TERM term = enif_make_resource(env, obj);
  enif_release_resource(obj);

  return term;
}

ERL_NIF_TERM nif_tf2_msgs_action_lookup_transform__goal_create(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  ignore_unused(argv);

  if (argc != 0) return enif_make_badarg(env);

  tf2_msgs__action__LookupTransform_Goal *message_p = tf2_msgs__action__LookupTransform_Goal__create();
  if (message_p == NULL) return raise(env, __FILE__, __LINE__);

  void **obj = enif_alloc_resource(rt_ros_message, sizeof(void *));
  *obj = (void *)message_p;
  ERL_NIF_TERM term = enif_make_resource(env, obj);
  enif_release_resource(obj);

  return term;
}

ERL_NIF_TERM nif_tf2_msgs_action_lookup_transform__goal_destroy(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 1) return enif_make_badarg(env);

  void **ros_message_pp;
  if (!enif_get_resource(env, argv[0], rt_ros_message, (void **)&ros_message_pp))
    return enif_make_badarg(env);

  tf2_msgs__action__LookupTransform_Goal *message_p = (tf2_msgs__action__LookupTransform_Goal *)*ros_message_pp;
  tf2_msgs__action__LookupTransform_Goal__destroy(message_p);

  return atom_ok;
}

ERL_NIF_TERM nif_tf2_msgs_action_lookup_transform__goal_set(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 2) return enif_make_badarg(env);

  void **ros_message_pp;
  if (!enif_get_resource(env, argv[0], rt_ros_message, (void **)&ros_message_pp))
    return enif_make_badarg(env);

  tf2_msgs__action__LookupTransform_Goal *message_p = (tf2_msgs__action__LookupTransform_Goal *)*ros_message_pp;

  int arity;
  const ERL_NIF_TERM *tuple;
  if (!enif_get_tuple(env, argv[1], &arity, &tuple)) return enif_make_badarg(env);

  ErlNifBinary target_frame_binary;
  if (!enif_inspect_binary(env, tuple[0], &target_frame_binary))
    return enif_make_badarg(env);

  if (!rosidl_runtime_c__String__assignn(&(message_p->target_frame), (const char *)target_frame_binary.data, target_frame_binary.size))
    return raise(env, __FILE__, __LINE__);

  ErlNifBinary source_frame_binary;
  if (!enif_inspect_binary(env, tuple[1], &source_frame_binary))
    return enif_make_badarg(env);

  if (!rosidl_runtime_c__String__assignn(&(message_p->source_frame), (const char *)source_frame_binary.data, source_frame_binary.size))
    return raise(env, __FILE__, __LINE__);

  int source_time_arity;
  const ERL_NIF_TERM *source_time_tuple;
  if (!enif_get_tuple(env, tuple[2], &source_time_arity, &source_time_tuple))
    return enif_make_badarg(env);

  int source_time_sec;
  if (!enif_get_int(env, source_time_tuple[0], &source_time_sec))
    return enif_make_badarg(env);
  message_p->source_time.sec = source_time_sec;

  unsigned int source_time_nanosec;
  if (!enif_get_uint(env, source_time_tuple[1], &source_time_nanosec))
    return enif_make_badarg(env);
  message_p->source_time.nanosec = source_time_nanosec;

  int timeout_arity;
  const ERL_NIF_TERM *timeout_tuple;
  if (!enif_get_tuple(env, tuple[3], &timeout_arity, &timeout_tuple))
    return enif_make_badarg(env);

  int timeout_sec;
  if (!enif_get_int(env, timeout_tuple[0], &timeout_sec))
    return enif_make_badarg(env);
  message_p->timeout.sec = timeout_sec;

  unsigned int timeout_nanosec;
  if (!enif_get_uint(env, timeout_tuple[1], &timeout_nanosec))
    return enif_make_badarg(env);
  message_p->timeout.nanosec = timeout_nanosec;

  int target_time_arity;
  const ERL_NIF_TERM *target_time_tuple;
  if (!enif_get_tuple(env, tuple[4], &target_time_arity, &target_time_tuple))
    return enif_make_badarg(env);

  int target_time_sec;
  if (!enif_get_int(env, target_time_tuple[0], &target_time_sec))
    return enif_make_badarg(env);
  message_p->target_time.sec = target_time_sec;

  unsigned int target_time_nanosec;
  if (!enif_get_uint(env, target_time_tuple[1], &target_time_nanosec))
    return enif_make_badarg(env);
  message_p->target_time.nanosec = target_time_nanosec;

  ErlNifBinary fixed_frame_binary;
  if (!enif_inspect_binary(env, tuple[5], &fixed_frame_binary))
    return enif_make_badarg(env);

  if (!rosidl_runtime_c__String__assignn(&(message_p->fixed_frame), (const char *)fixed_frame_binary.data, fixed_frame_binary.size))
    return raise(env, __FILE__, __LINE__);

  unsigned int advanced_length;
  if (!enif_get_atom_length(env, tuple[6], &advanced_length, ERL_NIF_LATIN1))
    return enif_make_badarg(env);

  char advanced[advanced_length + 1];
  if (enif_get_atom(env, tuple[6], advanced, advanced_length + 1, ERL_NIF_LATIN1) <= 0)
    return enif_make_badarg(env);

  message_p->advanced = (strncmp(advanced, "true", 4) == 0);

  return atom_ok;
}

ERL_NIF_TERM nif_tf2_msgs_action_lookup_transform__goal_get(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 1) return enif_make_badarg(env);

  void **ros_message_pp;
  if (!enif_get_resource(env, argv[0], rt_ros_message, (void **)&ros_message_pp))
    return enif_make_badarg(env);

  tf2_msgs__action__LookupTransform_Goal *message_p = (tf2_msgs__action__LookupTransform_Goal *)*ros_message_pp;

  ERL_NIF_TERM target_frame_term = enif_make_binary_wrapper(env, message_p->target_frame.data, message_p->target_frame.size);
  if (enif_is_exception(env, target_frame_term))
    return target_frame_term;
  ERL_NIF_TERM source_frame_term = enif_make_binary_wrapper(env, message_p->source_frame.data, message_p->source_frame.size);
  if (enif_is_exception(env, source_frame_term))
    return source_frame_term;
  ERL_NIF_TERM fixed_frame_term = enif_make_binary_wrapper(env, message_p->fixed_frame.data, message_p->fixed_frame.size);
  if (enif_is_exception(env, fixed_frame_term))
    return fixed_frame_term;
  return enif_make_tuple(env, 7,
    target_frame_term,
    source_frame_term,
    enif_make_tuple(env, 2,
      enif_make_int(env, message_p->source_time.sec),
      enif_make_uint(env, message_p->source_time.nanosec)
    ),
    enif_make_tuple(env, 2,
      enif_make_int(env, message_p->timeout.sec),
      enif_make_uint(env, message_p->timeout.nanosec)
    ),
    enif_make_tuple(env, 2,
      enif_make_int(env, message_p->target_time.sec),
      enif_make_uint(env, message_p->target_time.nanosec)
    ),
    fixed_frame_term,
    enif_make_atom(env, message_p->advanced ? "true" : "false")
  );
}
// clang-format on
