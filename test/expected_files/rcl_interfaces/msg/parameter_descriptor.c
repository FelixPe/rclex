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

#include <rcl_interfaces/msg/detail/floating_point_range__functions.h>
#include <rcl_interfaces/msg/detail/floating_point_range__struct.h>

#include <rcl_interfaces/msg/detail/integer_range__functions.h>
#include <rcl_interfaces/msg/detail/integer_range__struct.h>

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

  unsigned int read_only_length;
  if (!enif_get_atom_length(env, tuple[4], &read_only_length, ERL_NIF_LATIN1))
    return enif_make_badarg(env);

  char read_only[read_only_length + 1];
  if (enif_get_atom(env, tuple[4], read_only, read_only_length + 1, ERL_NIF_LATIN1) <= 0)
    return enif_make_badarg(env);

  message_p->read_only = (strncmp(read_only, "true", 4) == 0);

  unsigned int dynamic_typing_length;
  if (!enif_get_atom_length(env, tuple[5], &dynamic_typing_length, ERL_NIF_LATIN1))
    return enif_make_badarg(env);

  char dynamic_typing[dynamic_typing_length + 1];
  if (enif_get_atom(env, tuple[5], dynamic_typing, dynamic_typing_length + 1, ERL_NIF_LATIN1) <= 0)
    return enif_make_badarg(env);

  message_p->dynamic_typing = (strncmp(dynamic_typing, "true", 4) == 0);

  unsigned int floating_point_range_length;
  if (!enif_get_list_length(env, tuple[6], &floating_point_range_length))
    return enif_make_badarg(env);

  rcl_interfaces__msg__FloatingPointRange__Sequence *floating_point_range = rcl_interfaces__msg__FloatingPointRange__Sequence__create(floating_point_range_length);
  if (floating_point_range == NULL) return raise(env, __FILE__, __LINE__);
  message_p->floating_point_range = *floating_point_range;

  unsigned int floating_point_range_i;
  ERL_NIF_TERM floating_point_range_left, floating_point_range_head, floating_point_range_tail;
  for (floating_point_range_i = 0, floating_point_range_left = tuple[6]; floating_point_range_i < floating_point_range_length; ++floating_point_range_i, floating_point_range_left = floating_point_range_tail)
  {
    if (!enif_get_list_cell(env, floating_point_range_left, &floating_point_range_head, &floating_point_range_tail))
      return enif_make_badarg(env);

    int floating_point_range_i_arity;
    const ERL_NIF_TERM *floating_point_range_i_tuple;
    if (!enif_get_tuple(env, floating_point_range_head, &floating_point_range_i_arity, &floating_point_range_i_tuple))
      return enif_make_badarg(env);

    double floating_point_range_i_from_value;
    if (!enif_get_double(env, floating_point_range_i_tuple[0], &floating_point_range_i_from_value))
      return enif_make_badarg(env);
    message_p->floating_point_range.data[floating_point_range_i].from_value = floating_point_range_i_from_value;

    double floating_point_range_i_to_value;
    if (!enif_get_double(env, floating_point_range_i_tuple[1], &floating_point_range_i_to_value))
      return enif_make_badarg(env);
    message_p->floating_point_range.data[floating_point_range_i].to_value = floating_point_range_i_to_value;

    double floating_point_range_i_step;
    if (!enif_get_double(env, floating_point_range_i_tuple[2], &floating_point_range_i_step))
      return enif_make_badarg(env);
    message_p->floating_point_range.data[floating_point_range_i].step = floating_point_range_i_step;
  }

  unsigned int integer_range_length;
  if (!enif_get_list_length(env, tuple[7], &integer_range_length))
    return enif_make_badarg(env);

  rcl_interfaces__msg__IntegerRange__Sequence *integer_range = rcl_interfaces__msg__IntegerRange__Sequence__create(integer_range_length);
  if (integer_range == NULL) return raise(env, __FILE__, __LINE__);
  message_p->integer_range = *integer_range;

  unsigned int integer_range_i;
  ERL_NIF_TERM integer_range_left, integer_range_head, integer_range_tail;
  for (integer_range_i = 0, integer_range_left = tuple[7]; integer_range_i < integer_range_length; ++integer_range_i, integer_range_left = integer_range_tail)
  {
    if (!enif_get_list_cell(env, integer_range_left, &integer_range_head, &integer_range_tail))
      return enif_make_badarg(env);

    int integer_range_i_arity;
    const ERL_NIF_TERM *integer_range_i_tuple;
    if (!enif_get_tuple(env, integer_range_head, &integer_range_i_arity, &integer_range_i_tuple))
      return enif_make_badarg(env);

    int64_t integer_range_i_from_value;
    if (!enif_get_int64(env, integer_range_i_tuple[0], &integer_range_i_from_value))
      return enif_make_badarg(env);
    message_p->integer_range.data[integer_range_i].from_value = integer_range_i_from_value;

    int64_t integer_range_i_to_value;
    if (!enif_get_int64(env, integer_range_i_tuple[1], &integer_range_i_to_value))
      return enif_make_badarg(env);
    message_p->integer_range.data[integer_range_i].to_value = integer_range_i_to_value;

    uint64_t integer_range_i_step;
    if (!enif_get_uint64(env, integer_range_i_tuple[2], &integer_range_i_step))
      return enif_make_badarg(env);
    message_p->integer_range.data[integer_range_i].step = integer_range_i_step;
  }

  return atom_ok;
}

ERL_NIF_TERM nif_rcl_interfaces_msg_parameter_descriptor_get(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 1) return enif_make_badarg(env);

  void **ros_message_pp;
  if (!enif_get_resource(env, argv[0], rt_ros_message, (void **)&ros_message_pp))
    return enif_make_badarg(env);

  rcl_interfaces__msg__ParameterDescriptor *message_p = (rcl_interfaces__msg__ParameterDescriptor *)*ros_message_pp;

  ERL_NIF_TERM floating_point_range[message_p->floating_point_range.size];

  for (size_t floating_point_range_i = 0; floating_point_range_i < message_p->floating_point_range.size; ++floating_point_range_i)
  {
    floating_point_range[floating_point_range_i] = enif_make_tuple(env, 3,
      enif_make_double(env, message_p->floating_point_range.data[floating_point_range_i].from_value),
      enif_make_double(env, message_p->floating_point_range.data[floating_point_range_i].to_value),
      enif_make_double(env, message_p->floating_point_range.data[floating_point_range_i].step)
    );
  }

  ERL_NIF_TERM integer_range[message_p->integer_range.size];

  for (size_t integer_range_i = 0; integer_range_i < message_p->integer_range.size; ++integer_range_i)
  {
    integer_range[integer_range_i] = enif_make_tuple(env, 3,
      enif_make_int64(env, message_p->integer_range.data[integer_range_i].from_value),
      enif_make_int64(env, message_p->integer_range.data[integer_range_i].to_value),
      enif_make_uint64(env, message_p->integer_range.data[integer_range_i].step)
    );
  }

  return enif_make_tuple(env, 8,
    enif_make_binary_wrapper(env, message_p->name.data, message_p->name.size),
    enif_make_uint(env, message_p->type),
    enif_make_binary_wrapper(env, message_p->description.data, message_p->description.size),
    enif_make_binary_wrapper(env, message_p->additional_constraints.data, message_p->additional_constraints.size),
    enif_make_atom(env, message_p->read_only ? "true" : "false"),
    enif_make_atom(env, message_p->dynamic_typing ? "true" : "false"),
    enif_make_list_from_array(env, floating_point_range, message_p->floating_point_range.size),
    enif_make_list_from_array(env, integer_range, message_p->integer_range.size)
  );
}
// clang-format on
