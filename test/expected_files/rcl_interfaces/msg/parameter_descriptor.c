// clang-format off
#include "parameter_descriptor.h"
#include "../../../macros.h"
#include "../../../resource_types.h"
#include "../../../terms.h"

#include <erl_nif.h>

#include <rosidl_runtime_c/message_type_support_struct.h>
#include <rosidl_runtime_c/primitives_sequence.h>
#include <rosidl_runtime_c/primitives_sequence_functions.h>
#include <rosidl_runtime_c/string.h>
#include <rosidl_runtime_c/string_functions.h>

#include <rcl_interfaces/msg/detail/parameter_descriptor__functions.h>
#include <rcl_interfaces/msg/detail/parameter_descriptor__struct.h>
#include <rcl_interfaces/msg/detail/parameter_descriptor__type_support.h>

#include <stddef.h>
#include <stdint.h>
#include <string.h>

ERL_NIF_TERM nif_rcl_interfaces_msg_parameter_descriptor_type_support(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  ignore_unused(argv);

  if (argc != 0) return enif_make_badarg(env);

  const rosidl_message_type_support_t *ts_p = ROSIDL_GET_MSG_TYPE_SUPPORT(rcl_interfaces, msg, ParameterDescriptor);
  rosidl_message_type_support_t *obj = enif_alloc_resource(rt_rosidl_message_type_support_t, sizeof(rosidl_message_type_support_t));
  *obj = *ts_p;
  ERL_NIF_TERM term = enif_make_resource(env, obj);
  enif_release_resource(obj);

  return term;
}

ERL_NIF_TERM nif_rcl_interfaces_msg_parameter_descriptor_create(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  ignore_unused(argv);

  if (argc != 0) return enif_make_badarg(env);

  rcl_interfaces__msg__ParameterDescriptor *message_p = rcl_interfaces__msg__ParameterDescriptor__create();
  if (message_p == NULL) return raise(env, __FILE__, __LINE__);

  void **obj = enif_alloc_resource(rt_ros_message, sizeof(void *));
  *obj = (void *)message_p;
  ERL_NIF_TERM term = enif_make_resource(env, obj);
  enif_release_resource(obj);

  return term;
}

ERL_NIF_TERM nif_rcl_interfaces_msg_parameter_descriptor_destroy(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 1) return enif_make_badarg(env);

  void **ros_message_pp;
  if (!enif_get_resource(env, argv[0], rt_ros_message, (void **)&ros_message_pp))
    return enif_make_badarg(env);

  rcl_interfaces__msg__ParameterDescriptor *message_p = (rcl_interfaces__msg__ParameterDescriptor *)*ros_message_pp;
  rcl_interfaces__msg__ParameterDescriptor__destroy(message_p);

  return atom_ok;
}

ERL_NIF_TERM nif_rcl_interfaces_msg_parameter_descriptor_set(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 2) return enif_make_badarg(env);

  void **ros_message_pp;
  if (!enif_get_resource(env, argv[0], rt_ros_message, (void **)&ros_message_pp))
    return enif_make_badarg(env);

  rcl_interfaces__msg__ParameterDescriptor *message_p = (rcl_interfaces__msg__ParameterDescriptor *)*ros_message_pp;

  int arity;
  const ERL_NIF_TERM *tuple;
  if (!enif_get_tuple(env, argv[1], &arity, &tuple)) return enif_make_badarg(env);

  ErlNifBinary name_binary;
  if (!enif_inspect_binary(env, tuple[0], &name_binary))
    return enif_make_badarg(env);

  if (!rosidl_runtime_c__String__assignn(&(message_p->name), (const char *)name_binary.data, name_binary.size))
    return raise(env, __FILE__, __LINE__);

  unsigned int type;
  if (!enif_get_uint(env, tuple[1], &type))
    return enif_make_badarg(env);
  message_p->type = type;

  ErlNifBinary description_binary;
  if (!enif_inspect_binary(env, tuple[2], &description_binary))
    return enif_make_badarg(env);

  if (!rosidl_runtime_c__String__assignn(&(message_p->description), (const char *)description_binary.data, description_binary.size))
    return raise(env, __FILE__, __LINE__);

  ErlNifBinary additional_constraints_binary;
  if (!enif_inspect_binary(env, tuple[3], &additional_constraints_binary))
    return enif_make_badarg(env);

  if (!rosidl_runtime_c__String__assignn(&(message_p->additional_constraints), (const char *)additional_constraints_binary.data, additional_constraints_binary.size))
    return raise(env, __FILE__, __LINE__);

  return atom_ok;
}

ERL_NIF_TERM nif_rcl_interfaces_msg_parameter_descriptor_get(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 1) return enif_make_badarg(env);

  void **ros_message_pp;
  if (!enif_get_resource(env, argv[0], rt_ros_message, (void **)&ros_message_pp))
    return enif_make_badarg(env);

  rcl_interfaces__msg__ParameterDescriptor *message_p = (rcl_interfaces__msg__ParameterDescriptor *)*ros_message_pp;

  return enif_make_tuple(env, 4,
    enif_make_binary_wrapper(env, message_p->name.data, message_p->name.size),
    enif_make_uint(env, message_p->type),
    enif_make_binary_wrapper(env, message_p->description.data, message_p->description.size),
    enif_make_binary_wrapper(env, message_p->additional_constraints.data, message_p->additional_constraints.size)
  );
}
// clang-format on
