// clang-format off
#include "lookup_transform__get_result__request.h"
#ifndef ROS_DISTRO_humble
#include "../../../type_description.h"
#endif
#include "../../../macros.h"
#include "../../../resource_types.h"
#include "../../../terms.h"

#include <erl_nif.h>

#include <rosidl_runtime_c/message_type_support_struct.h>
#include <rosidl_runtime_c/primitives_sequence.h>
#include <rosidl_runtime_c/primitives_sequence_functions.h>
#include <rosidl_runtime_c/string.h>
#include <rosidl_runtime_c/string_functions.h>

#include <unique_identifier_msgs/msg/detail/uuid__functions.h>
#include <unique_identifier_msgs/msg/detail/uuid__struct.h>

#include <tf2_msgs/action/detail/lookup_transform__functions.h>
#include <tf2_msgs/action/detail/lookup_transform__struct.h>
#include <tf2_msgs/action/detail/lookup_transform__type_support.h>
#ifndef ROS_DISTRO_humble
#include <rosidl_runtime_c/type_description/type_description__struct.h>
#endif

#include <math.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

ERL_NIF_TERM nif_tf2_msgs_action_lookup_transform__get_result__request_type_support(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  ignore_unused(argv);

  if (argc != 0) return enif_make_badarg(env);

  const rosidl_message_type_support_t *ts_p = ROSIDL_GET_MSG_TYPE_SUPPORT(tf2_msgs, action, LookupTransform_GetResult_Request);
  rosidl_message_type_support_t *obj = enif_alloc_resource(rt_rosidl_message_type_support_t, sizeof(rosidl_message_type_support_t));
  *obj = *ts_p;
  ERL_NIF_TERM term = enif_make_resource(env, obj);
  enif_release_resource(obj);

  return term;
}

#ifndef ROS_DISTRO_humble
ERL_NIF_TERM nif_tf2_msgs_action_lookup_transform__get_result__request_type_description(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  ignore_unused(argv);

  if (argc != 0) return enif_make_badarg(env);

  const rosidl_message_type_support_t *ts_p = ROSIDL_GET_MSG_TYPE_SUPPORT(tf2_msgs, action, LookupTransform_GetResult_Request);
  const rosidl_runtime_c__type_description__TypeDescription *description =
      tf2_msgs__action__LookupTransform_GetResult_Request__get_type_description(ts_p);
  if (description == NULL) return raise(env, __FILE__, __LINE__);

  return make_type_description_term(env, description);
}

ERL_NIF_TERM nif_tf2_msgs_action_lookup_transform__get_result__request_type_description_sources(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  ignore_unused(argv);

  if (argc != 0) return enif_make_badarg(env);

  const rosidl_message_type_support_t *ts_p = ROSIDL_GET_MSG_TYPE_SUPPORT(tf2_msgs, action, LookupTransform_GetResult_Request);
  const rosidl_runtime_c__type_description__TypeSource__Sequence *sources =
      tf2_msgs__action__LookupTransform_GetResult_Request__get_type_description_sources(ts_p);
  if (sources == NULL) return raise(env, __FILE__, __LINE__);

  return make_type_sources_term(env, sources);
}

ERL_NIF_TERM nif_tf2_msgs_action_lookup_transform__get_result__request_type_hash(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  ignore_unused(argv);

  if (argc != 0) return enif_make_badarg(env);

  const rosidl_message_type_support_t *ts_p = ROSIDL_GET_MSG_TYPE_SUPPORT(tf2_msgs, action, LookupTransform_GetResult_Request);
  const rosidl_type_hash_t *hash = tf2_msgs__action__LookupTransform_GetResult_Request__get_type_hash(ts_p);
  if (hash == NULL) return raise(env, __FILE__, __LINE__);

  return make_type_hash_term(env, hash);
}
#endif

ERL_NIF_TERM nif_tf2_msgs_action_lookup_transform__get_result__request_create(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  ignore_unused(argv);

  if (argc != 0) return enif_make_badarg(env);

  tf2_msgs__action__LookupTransform_GetResult_Request *message_p = tf2_msgs__action__LookupTransform_GetResult_Request__create();
  if (message_p == NULL) return raise(env, __FILE__, __LINE__);

  void **obj = enif_alloc_resource(rt_ros_message, sizeof(void *));
  *obj = (void *)message_p;
  ERL_NIF_TERM term = enif_make_resource(env, obj);
  enif_release_resource(obj);

  return term;
}

ERL_NIF_TERM nif_tf2_msgs_action_lookup_transform__get_result__request_destroy(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 1) return enif_make_badarg(env);

  void **ros_message_pp;
  if (!enif_get_resource(env, argv[0], rt_ros_message, (void **)&ros_message_pp))
    return enif_make_badarg(env);

  tf2_msgs__action__LookupTransform_GetResult_Request *message_p = (tf2_msgs__action__LookupTransform_GetResult_Request *)*ros_message_pp;
  tf2_msgs__action__LookupTransform_GetResult_Request__destroy(message_p);

  return atom_ok;
}

ERL_NIF_TERM nif_tf2_msgs_action_lookup_transform__get_result__request_set(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 2) return enif_make_badarg(env);

  void **ros_message_pp;
  if (!enif_get_resource(env, argv[0], rt_ros_message, (void **)&ros_message_pp))
    return enif_make_badarg(env);

  tf2_msgs__action__LookupTransform_GetResult_Request *message_p = (tf2_msgs__action__LookupTransform_GetResult_Request *)*ros_message_pp;

  int arity;
  const ERL_NIF_TERM *tuple;
  if (!enif_get_tuple(env, argv[1], &arity, &tuple)) return enif_make_badarg(env);

  int goal_id_arity;
  const ERL_NIF_TERM *goal_id_tuple;
  if (!enif_get_tuple(env, tuple[0], &goal_id_arity, &goal_id_tuple))
    return enif_make_badarg(env);

  ErlNifBinary goal_id_uuid_bin;
  if(!enif_inspect_binary(env, goal_id_tuple[0], &goal_id_uuid_bin))
    return enif_make_badarg(env);

  unsigned int goal_id_uuid_length = goal_id_uuid_bin.size;
  if(goal_id_uuid_length > 16)
    return enif_make_badarg(env);

  memcpy(message_p->goal_id.uuid, goal_id_uuid_bin.data, goal_id_uuid_length);

  return atom_ok;
}

ERL_NIF_TERM nif_tf2_msgs_action_lookup_transform__get_result__request_get(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 1) return enif_make_badarg(env);

  void **ros_message_pp;
  if (!enif_get_resource(env, argv[0], rt_ros_message, (void **)&ros_message_pp))
    return enif_make_badarg(env);

  tf2_msgs__action__LookupTransform_GetResult_Request *message_p = (tf2_msgs__action__LookupTransform_GetResult_Request *)*ros_message_pp;

  ErlNifBinary goal_id_uuid_bin;
  if(!enif_alloc_binary(16, &goal_id_uuid_bin))
    return raise(env, __FILE__, __LINE__);

  memcpy(goal_id_uuid_bin.data, message_p->goal_id.uuid, 16);
  ERL_NIF_TERM goal_id_uuid = enif_make_binary(env, &goal_id_uuid_bin);

  return enif_make_tuple(env, 1,
    enif_make_tuple(env, 1,
      goal_id_uuid
    )
  );
}
// clang-format on
