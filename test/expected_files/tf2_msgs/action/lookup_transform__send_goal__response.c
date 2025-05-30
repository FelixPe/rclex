// clang-format off
#include "lookup_transform__send_goal__response.h"
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

#include <tf2_msgs/action/detail/lookup_transform__functions.h>
#include <tf2_msgs/action/detail/lookup_transform__struct.h>
#include <tf2_msgs/action/detail/lookup_transform__type_support.h>

#include <stddef.h>
#include <stdint.h>
#include <string.h>

ERL_NIF_TERM nif_tf2_msgs_action_lookup_transform__send_goal__response_type_support(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  ignore_unused(argv);

  if (argc != 0) return enif_make_badarg(env);

  const rosidl_message_type_support_t *ts_p = ROSIDL_GET_MSG_TYPE_SUPPORT(tf2_msgs, action, LookupTransform_SendGoal_Response);
  rosidl_message_type_support_t *obj = enif_alloc_resource(rt_rosidl_message_type_support_t, sizeof(rosidl_message_type_support_t));
  *obj = *ts_p;
  ERL_NIF_TERM term = enif_make_resource(env, obj);
  enif_release_resource(obj);

  return term;
}

ERL_NIF_TERM nif_tf2_msgs_action_lookup_transform__send_goal__response_create(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  ignore_unused(argv);

  if (argc != 0) return enif_make_badarg(env);

  tf2_msgs__action__LookupTransform_SendGoal_Response *message_p = tf2_msgs__action__LookupTransform_SendGoal_Response__create();
  if (message_p == NULL) return raise(env, __FILE__, __LINE__);

  void **obj = enif_alloc_resource(rt_ros_message, sizeof(void *));
  *obj = (void *)message_p;
  ERL_NIF_TERM term = enif_make_resource(env, obj);
  enif_release_resource(obj);

  return term;
}

ERL_NIF_TERM nif_tf2_msgs_action_lookup_transform__send_goal__response_destroy(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 1) return enif_make_badarg(env);

  void **ros_message_pp;
  if (!enif_get_resource(env, argv[0], rt_ros_message, (void **)&ros_message_pp))
    return enif_make_badarg(env);

  tf2_msgs__action__LookupTransform_SendGoal_Response *message_p = (tf2_msgs__action__LookupTransform_SendGoal_Response *)*ros_message_pp;
  tf2_msgs__action__LookupTransform_SendGoal_Response__destroy(message_p);

  return atom_ok;
}

ERL_NIF_TERM nif_tf2_msgs_action_lookup_transform__send_goal__response_set(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 2) return enif_make_badarg(env);

  void **ros_message_pp;
  if (!enif_get_resource(env, argv[0], rt_ros_message, (void **)&ros_message_pp))
    return enif_make_badarg(env);

  tf2_msgs__action__LookupTransform_SendGoal_Response *message_p = (tf2_msgs__action__LookupTransform_SendGoal_Response *)*ros_message_pp;

  int arity;
  const ERL_NIF_TERM *tuple;
  if (!enif_get_tuple(env, argv[1], &arity, &tuple)) return enif_make_badarg(env);

  unsigned int accepted_length;
  if (!enif_get_atom_length(env, tuple[0], &accepted_length, ERL_NIF_LATIN1))
    return enif_make_badarg(env);

  char accepted[accepted_length + 1];
  if (enif_get_atom(env, tuple[0], accepted, accepted_length + 1, ERL_NIF_LATIN1) <= 0)
    return enif_make_badarg(env);

  message_p->accepted = (strncmp(accepted, "true", 4) == 0);

  int stamp_arity;
  const ERL_NIF_TERM *stamp_tuple;
  if (!enif_get_tuple(env, tuple[1], &stamp_arity, &stamp_tuple))
    return enif_make_badarg(env);

  int stamp_sec;
  if (!enif_get_int(env, stamp_tuple[0], &stamp_sec))
    return enif_make_badarg(env);
  message_p->stamp.sec = stamp_sec;

  unsigned int stamp_nanosec;
  if (!enif_get_uint(env, stamp_tuple[1], &stamp_nanosec))
    return enif_make_badarg(env);
  message_p->stamp.nanosec = stamp_nanosec;

  return atom_ok;
}

ERL_NIF_TERM nif_tf2_msgs_action_lookup_transform__send_goal__response_get(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 1) return enif_make_badarg(env);

  void **ros_message_pp;
  if (!enif_get_resource(env, argv[0], rt_ros_message, (void **)&ros_message_pp))
    return enif_make_badarg(env);

  tf2_msgs__action__LookupTransform_SendGoal_Response *message_p = (tf2_msgs__action__LookupTransform_SendGoal_Response *)*ros_message_pp;

  return enif_make_tuple(env, 2,
    enif_make_atom(env, message_p->accepted ? "true" : "false"),
    enif_make_tuple(env, 2,
      enif_make_int(env, message_p->stamp.sec),
      enif_make_uint(env, message_p->stamp.nanosec)
    )
  );
}
// clang-format on
