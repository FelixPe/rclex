// clang-format off
#include "rotate_absolute__get_result__response.h"
#include "../../../macros.h"
#include "../../../resource_types.h"
#include "../../../terms.h"

#include <erl_nif.h>

#include <rosidl_runtime_c/message_type_support_struct.h>
#include <rosidl_runtime_c/primitives_sequence.h>
#include <rosidl_runtime_c/primitives_sequence_functions.h>
#include <rosidl_runtime_c/string.h>
#include <rosidl_runtime_c/string_functions.h>

#include <turtlesim/action/detail/rotate_absolute__functions.h>
#include <turtlesim/action/detail/rotate_absolute__struct.h>

#include <turtlesim/action/detail/rotate_absolute__functions.h>
#include <turtlesim/action/detail/rotate_absolute__struct.h>
#include <turtlesim/action/detail/rotate_absolute__type_support.h>

#include <stddef.h>
#include <stdint.h>
#include <string.h>

ERL_NIF_TERM nif_turtlesim_action_rotate_absolute__get_result__response_type_support(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  ignore_unused(argv);

  if (argc != 0) return enif_make_badarg(env);

  const rosidl_message_type_support_t *ts_p = ROSIDL_GET_MSG_TYPE_SUPPORT(turtlesim, action, RotateAbsolute_GetResult_Response);
  rosidl_message_type_support_t *obj = enif_alloc_resource(rt_rosidl_message_type_support_t, sizeof(rosidl_message_type_support_t));
  *obj = *ts_p;
  ERL_NIF_TERM term = enif_make_resource(env, obj);
  enif_release_resource(obj);

  return term;
}

ERL_NIF_TERM nif_turtlesim_action_rotate_absolute__get_result__response_create(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  ignore_unused(argv);

  if (argc != 0) return enif_make_badarg(env);

  turtlesim__action__RotateAbsolute_GetResult_Response *message_p = turtlesim__action__RotateAbsolute_GetResult_Response__create();
  if (message_p == NULL) return raise(env, __FILE__, __LINE__);

  void **obj = enif_alloc_resource(rt_ros_message, sizeof(void *));
  *obj = (void *)message_p;
  ERL_NIF_TERM term = enif_make_resource(env, obj);
  enif_release_resource(obj);

  return term;
}

ERL_NIF_TERM nif_turtlesim_action_rotate_absolute__get_result__response_destroy(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 1) return enif_make_badarg(env);

  void **ros_message_pp;
  if (!enif_get_resource(env, argv[0], rt_ros_message, (void **)&ros_message_pp))
    return enif_make_badarg(env);

  turtlesim__action__RotateAbsolute_GetResult_Response *message_p = (turtlesim__action__RotateAbsolute_GetResult_Response *)*ros_message_pp;
  turtlesim__action__RotateAbsolute_GetResult_Response__destroy(message_p);

  return atom_ok;
}

ERL_NIF_TERM nif_turtlesim_action_rotate_absolute__get_result__response_set(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 2) return enif_make_badarg(env);

  void **ros_message_pp;
  if (!enif_get_resource(env, argv[0], rt_ros_message, (void **)&ros_message_pp))
    return enif_make_badarg(env);

  turtlesim__action__RotateAbsolute_GetResult_Response *message_p = (turtlesim__action__RotateAbsolute_GetResult_Response *)*ros_message_pp;

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

  double result_delta;
  if (!enif_get_double(env, result_tuple[0], &result_delta))
    return enif_make_badarg(env);
  message_p->result.delta = (float)result_delta;

  return atom_ok;
}

ERL_NIF_TERM nif_turtlesim_action_rotate_absolute__get_result__response_get(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 1) return enif_make_badarg(env);

  void **ros_message_pp;
  if (!enif_get_resource(env, argv[0], rt_ros_message, (void **)&ros_message_pp))
    return enif_make_badarg(env);

  turtlesim__action__RotateAbsolute_GetResult_Response *message_p = (turtlesim__action__RotateAbsolute_GetResult_Response *)*ros_message_pp;

  return enif_make_tuple(env, 2,
    enif_make_uint(env, message_p->status),
    enif_make_tuple(env, 1,
      enif_make_double(env, message_p->result.delta)
    )
  );
}
// clang-format on
