// clang-format off
#include "get_parameter_types__response.h"
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

#include <rcl_interfaces/srv/detail/get_parameter_types__functions.h>
#include <rcl_interfaces/srv/detail/get_parameter_types__struct.h>
#include <rcl_interfaces/srv/detail/get_parameter_types__type_support.h>
#ifndef ROS_DISTRO_humble
#include <rosidl_runtime_c/type_description/type_description__struct.h>
#endif

#include <math.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

ERL_NIF_TERM nif_rcl_interfaces_srv_get_parameter_types__response_type_support(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  ignore_unused(argv);

  if (argc != 0) return enif_make_badarg(env);

  const rosidl_message_type_support_t *ts_p = ROSIDL_GET_MSG_TYPE_SUPPORT(rcl_interfaces, srv, GetParameterTypes_Response);
  rosidl_message_type_support_t *obj = enif_alloc_resource(rt_rosidl_message_type_support_t, sizeof(rosidl_message_type_support_t));
  *obj = *ts_p;
  ERL_NIF_TERM term = enif_make_resource(env, obj);
  enif_release_resource(obj);

  return term;
}

#ifndef ROS_DISTRO_humble
ERL_NIF_TERM nif_rcl_interfaces_srv_get_parameter_types__response_type_description(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  ignore_unused(argv);

  if (argc != 0) return enif_make_badarg(env);

  const rosidl_message_type_support_t *ts_p = ROSIDL_GET_MSG_TYPE_SUPPORT(rcl_interfaces, srv, GetParameterTypes_Response);
  const rosidl_runtime_c__type_description__TypeDescription *description =
      rcl_interfaces__srv__GetParameterTypes_Response__get_type_description(ts_p);
  if (description == NULL) return raise(env, __FILE__, __LINE__);

  return make_type_description_term(env, description);
}

ERL_NIF_TERM nif_rcl_interfaces_srv_get_parameter_types__response_type_description_sources(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  ignore_unused(argv);

  if (argc != 0) return enif_make_badarg(env);

  const rosidl_message_type_support_t *ts_p = ROSIDL_GET_MSG_TYPE_SUPPORT(rcl_interfaces, srv, GetParameterTypes_Response);
  const rosidl_runtime_c__type_description__TypeSource__Sequence *sources =
      rcl_interfaces__srv__GetParameterTypes_Response__get_type_description_sources(ts_p);
  if (sources == NULL) return raise(env, __FILE__, __LINE__);

  return make_type_sources_term(env, sources);
}

ERL_NIF_TERM nif_rcl_interfaces_srv_get_parameter_types__response_type_hash(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  ignore_unused(argv);

  if (argc != 0) return enif_make_badarg(env);

  const rosidl_message_type_support_t *ts_p = ROSIDL_GET_MSG_TYPE_SUPPORT(rcl_interfaces, srv, GetParameterTypes_Response);
  const rosidl_type_hash_t *hash = rcl_interfaces__srv__GetParameterTypes_Response__get_type_hash(ts_p);
  if (hash == NULL) return raise(env, __FILE__, __LINE__);

  return make_type_hash_term(env, hash);
}
#endif

ERL_NIF_TERM nif_rcl_interfaces_srv_get_parameter_types__response_create(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  ignore_unused(argv);

  if (argc != 0) return enif_make_badarg(env);

  rcl_interfaces__srv__GetParameterTypes_Response *message_p = rcl_interfaces__srv__GetParameterTypes_Response__create();
  if (message_p == NULL) return raise(env, __FILE__, __LINE__);

  void **obj = enif_alloc_resource(rt_ros_message, sizeof(void *));
  *obj = (void *)message_p;
  ERL_NIF_TERM term = enif_make_resource(env, obj);
  enif_release_resource(obj);

  return term;
}

ERL_NIF_TERM nif_rcl_interfaces_srv_get_parameter_types__response_destroy(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 1) return enif_make_badarg(env);

  void **ros_message_pp;
  if (!enif_get_resource(env, argv[0], rt_ros_message, (void **)&ros_message_pp))
    return enif_make_badarg(env);

  rcl_interfaces__srv__GetParameterTypes_Response *message_p = (rcl_interfaces__srv__GetParameterTypes_Response *)*ros_message_pp;
  rcl_interfaces__srv__GetParameterTypes_Response__destroy(message_p);

  return atom_ok;
}

ERL_NIF_TERM nif_rcl_interfaces_srv_get_parameter_types__response_set(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 2) return enif_make_badarg(env);

  void **ros_message_pp;
  if (!enif_get_resource(env, argv[0], rt_ros_message, (void **)&ros_message_pp))
    return enif_make_badarg(env);

  rcl_interfaces__srv__GetParameterTypes_Response *message_p = (rcl_interfaces__srv__GetParameterTypes_Response *)*ros_message_pp;

  int arity;
  const ERL_NIF_TERM *tuple;
  if (!enif_get_tuple(env, argv[1], &arity, &tuple)) return enif_make_badarg(env);

  ErlNifBinary types_bin;
  if(!enif_inspect_binary(env, tuple[0], &types_bin))
    return enif_make_badarg(env);

  unsigned int types_length = types_bin.size;
  rosidl_runtime_c__uint8__Sequence types;
  if(!rosidl_runtime_c__uint8__Sequence__init(&types, types_length))
    return enif_make_badarg(env);
  message_p->types = types;
  memcpy(message_p->types.data, types_bin.data, types_length);

  return atom_ok;
}

ERL_NIF_TERM nif_rcl_interfaces_srv_get_parameter_types__response_get(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 1) return enif_make_badarg(env);

  void **ros_message_pp;
  if (!enif_get_resource(env, argv[0], rt_ros_message, (void **)&ros_message_pp))
    return enif_make_badarg(env);

  rcl_interfaces__srv__GetParameterTypes_Response *message_p = (rcl_interfaces__srv__GetParameterTypes_Response *)*ros_message_pp;

  if (message_p->types.size > message_p->types.capacity)
    return raise_with_message(env, __FILE__, __LINE__, "invalid sequence size/capacity");

  if (message_p->types.size > 0 && message_p->types.data == NULL)
    return raise_with_message(env, __FILE__, __LINE__, "NULL sequence data with non-zero size");

  ErlNifBinary types_bin;
  if(!enif_alloc_binary(message_p->types.size, &types_bin))
    return raise(env, __FILE__, __LINE__);

  memcpy(types_bin.data, message_p->types.data, message_p->types.size);
  ERL_NIF_TERM types = enif_make_binary(env, &types_bin);

  return enif_make_tuple(env, 1,
    types
  );
}
// clang-format on
