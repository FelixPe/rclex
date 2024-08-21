// clang-format off
#include "get_parameter_types__request.h"
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

#include <stddef.h>
#include <stdint.h>
#include <string.h>

ERL_NIF_TERM nif_rcl_interfaces_srv_get_parameter_types__request_type_support(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  ignore_unused(argv);

  if (argc != 0) return enif_make_badarg(env);

  const rosidl_message_type_support_t *ts_p = ROSIDL_GET_MSG_TYPE_SUPPORT(rcl_interfaces, srv, GetParameterTypes_Request);
  rosidl_message_type_support_t *obj = enif_alloc_resource(rt_rosidl_message_type_support_t, sizeof(rosidl_message_type_support_t));
  *obj = *ts_p;
  ERL_NIF_TERM term = enif_make_resource(env, obj);
  enif_release_resource(obj);

  return term;
}

ERL_NIF_TERM nif_rcl_interfaces_srv_get_parameter_types__request_create(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  ignore_unused(argv);

  if (argc != 0) return enif_make_badarg(env);

  rcl_interfaces__srv__GetParameterTypes_Request *message_p = rcl_interfaces__srv__GetParameterTypes_Request__create();
  if (message_p == NULL) return raise(env, __FILE__, __LINE__);

  void **obj = enif_alloc_resource(rt_ros_message, sizeof(void *));
  *obj = (void *)message_p;
  ERL_NIF_TERM term = enif_make_resource(env, obj);
  enif_release_resource(obj);

  return term;
}

ERL_NIF_TERM nif_rcl_interfaces_srv_get_parameter_types__request_destroy(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 1) return enif_make_badarg(env);

  void **ros_message_pp;
  if (!enif_get_resource(env, argv[0], rt_ros_message, (void **)&ros_message_pp))
    return enif_make_badarg(env);

  rcl_interfaces__srv__GetParameterTypes_Request *message_p = (rcl_interfaces__srv__GetParameterTypes_Request *)*ros_message_pp;
  rcl_interfaces__srv__GetParameterTypes_Request__destroy(message_p);

  return atom_ok;
}

ERL_NIF_TERM nif_rcl_interfaces_srv_get_parameter_types__request_set(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 2) return enif_make_badarg(env);

  void **ros_message_pp;
  if (!enif_get_resource(env, argv[0], rt_ros_message, (void **)&ros_message_pp))
    return enif_make_badarg(env);

  rcl_interfaces__srv__GetParameterTypes_Request *message_p = (rcl_interfaces__srv__GetParameterTypes_Request *)*ros_message_pp;

  int arity;
  const ERL_NIF_TERM *tuple;
  if (!enif_get_tuple(env, argv[1], &arity, &tuple)) return enif_make_badarg(env);

  unsigned int names_length;
  if (!enif_get_list_length(env, tuple[0], &names_length))
    return enif_make_badarg(env);

  rosidl_runtime_c__String__Sequence names;
  if(!rosidl_runtime_c__String__Sequence__init(&names, names_length))
    return enif_make_badarg(env);
  message_p->names = names;

  unsigned int names_i;
  ERL_NIF_TERM names_left, names_head, names_tail;
  for (names_i = 0, names_left = tuple[0]; names_i < names_length; ++names_i, names_left = names_tail)
  {
    if (!enif_get_list_cell(env, names_left, &names_head, &names_tail))
      return enif_make_badarg(env);

    unsigned int names_string_length;
#if (ERL_NIF_MAJOR_VERSION == 2 && ERL_NIF_MINOR_VERSION >= 17) // OTP-26 and later
    if (!enif_get_string_length(env, names_head, &names_string_length, ERL_NIF_LATIN1))
      return enif_make_badarg(env);
#else
    if (!enif_get_list_length(env, names_head, &names_string_length))
      return enif_make_badarg(env);
#endif

    char names_string[names_string_length + 1];
    if (enif_get_string(env, names_head, names_string, names_string_length + 1, ERL_NIF_LATIN1) <= 0)
      return enif_make_badarg(env);

    if (!rosidl_runtime_c__String__assign(&(message_p->names.data[names_i]), names_string))
      return raise(env, __FILE__, __LINE__);
  }

  return atom_ok;
}

ERL_NIF_TERM nif_rcl_interfaces_srv_get_parameter_types__request_get(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 1) return enif_make_badarg(env);

  void **ros_message_pp;
  if (!enif_get_resource(env, argv[0], rt_ros_message, (void **)&ros_message_pp))
    return enif_make_badarg(env);

  rcl_interfaces__srv__GetParameterTypes_Request *message_p = (rcl_interfaces__srv__GetParameterTypes_Request *)*ros_message_pp;

  ERL_NIF_TERM names[message_p->names.size];

  for (size_t names_i = 0; names_i < message_p->names.size; ++names_i)
  {
    names[names_i] = enif_make_string(env, message_p->names.data[names_i].data, ERL_NIF_LATIN1);
  }

  return enif_make_tuple(env, 1,
    enif_make_list_from_array(env, names, message_p->names.size)
  );
}
// clang-format on
