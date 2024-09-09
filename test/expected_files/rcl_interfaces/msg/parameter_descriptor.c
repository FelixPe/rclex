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

  unsigned int name_length;
#if (ERL_NIF_MAJOR_VERSION == 2 && ERL_NIF_MINOR_VERSION >= 17) // OTP-26 and later
  if (!enif_get_string_length(env, tuple[0], &name_length, ERL_NIF_LATIN1))
    return enif_make_badarg(env);
#else
  if (!enif_get_list_length(env, tuple[0], &name_length))
    return enif_make_badarg(env);
#endif

  char name[name_length + 1];
  if (enif_get_string(env, tuple[0], name, name_length + 1, ERL_NIF_LATIN1) <= 0)
    return enif_make_badarg(env);

  if (!rosidl_runtime_c__String__assign(&(message_p->name), name))
    return raise(env, __FILE__, __LINE__);

  unsigned int type;
  if (!enif_get_uint(env, tuple[1], &type))
    return enif_make_badarg(env);
  message_p->type = type;

  unsigned int description_length;
#if (ERL_NIF_MAJOR_VERSION == 2 && ERL_NIF_MINOR_VERSION >= 17) // OTP-26 and later
  if (!enif_get_string_length(env, tuple[2], &description_length, ERL_NIF_LATIN1))
    return enif_make_badarg(env);
#else
  if (!enif_get_list_length(env, tuple[2], &description_length))
    return enif_make_badarg(env);
#endif

  char description[description_length + 1];
  if (enif_get_string(env, tuple[2], description, description_length + 1, ERL_NIF_LATIN1) <= 0)
    return enif_make_badarg(env);

  if (!rosidl_runtime_c__String__assign(&(message_p->description), description))
    return raise(env, __FILE__, __LINE__);

  unsigned int additional_constraints_length;
#if (ERL_NIF_MAJOR_VERSION == 2 && ERL_NIF_MINOR_VERSION >= 17) // OTP-26 and later
  if (!enif_get_string_length(env, tuple[3], &additional_constraints_length, ERL_NIF_LATIN1))
    return enif_make_badarg(env);
#else
  if (!enif_get_list_length(env, tuple[3], &additional_constraints_length))
    return enif_make_badarg(env);
#endif

  char additional_constraints[additional_constraints_length + 1];
  if (enif_get_string(env, tuple[3], additional_constraints, additional_constraints_length + 1, ERL_NIF_LATIN1) <= 0)
    return enif_make_badarg(env);

  if (!rosidl_runtime_c__String__assign(&(message_p->additional_constraints), additional_constraints))
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
    enif_make_string(env, message_p->name.data, ERL_NIF_LATIN1),
    enif_make_uint(env, message_p->type),
    enif_make_string(env, message_p->description.data, ERL_NIF_LATIN1),
    enif_make_string(env, message_p->additional_constraints.data, ERL_NIF_LATIN1)
  );
}
// clang-format on
