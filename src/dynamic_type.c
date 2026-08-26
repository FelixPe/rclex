#include "dynamic_type.h"
#include "resource_types.h"

#if defined(ROS_DISTRO_humble) || !defined(HAVE_ROSIDL_DYNAMIC_TYPESUPPORT)

void
make_dynamic_type_atoms(ErlNifEnv * env)
{
  (void)env;
}

int
dynamic_type_resource_init(ErlNifEnv * env)
{
  (void)env;
  return 0;
}

void
dynamic_type_fini(dynamic_type_t * dynamic_type)
{
  (void)dynamic_type;
}

ERL_NIF_TERM
nif_dynamic_type_from_description(
  ErlNifEnv * env,
  int argc,
  const ERL_NIF_TERM argv[])
{
  (void)argc;
  (void)argv;
  return enif_make_badarg(env);
}

ERL_NIF_TERM
nif_dynamic_type_fini(
  ErlNifEnv * env,
  int argc,
  const ERL_NIF_TERM argv[])
{
  (void)argc;
  (void)argv;
  return enif_make_badarg(env);
}

ERL_NIF_TERM
nif_dynamic_type_fill_message(
  ErlNifEnv * env,
  int argc,
  const ERL_NIF_TERM argv[])
{
  (void)argc;
  (void)argv;
  return enif_make_badarg(env);
}

ERL_NIF_TERM
nif_dynamic_message_destroy(
  ErlNifEnv * env,
  int argc,
  const ERL_NIF_TERM argv[])
{
  (void)argc;
  (void)argv;
  return enif_make_badarg(env);
}

bool
get_ros_message_data(
  ErlNifEnv * env,
  ERL_NIF_TERM message_term,
  void ** message_data_out)
{
  void ** ros_message_pp;

  if (message_data_out == NULL) {
    return false;
  }

  if (!enif_get_resource(env, message_term, rt_ros_message, (void **)&ros_message_pp)) {
    return false;
  }

  *message_data_out = *ros_message_pp;
  return true;
}

#else

#include "allocator.h"
#include "resource_types.h"
#include "terms.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include <rcl/error_handling.h>
#include <rcutils/error_handling.h>

#include <rmw/dynamic_message_type_support.h>
#include <rmw/ret_types.h>

#include <rosidl_dynamic_typesupport/api/dynamic_data.h>
#include <rosidl_dynamic_typesupport/api/dynamic_type.h>

#include <rosidl_runtime_c/string_functions.h>
#include <rosidl_runtime_c/type_description/field__functions.h>
#include <rosidl_runtime_c/type_description/field_type__struct.h>
#include <rosidl_runtime_c/type_description/individual_type_description__functions.h>
#include <rosidl_runtime_c/type_description/type_description__functions.h>
#include <rosidl_runtime_c/type_description_utils.h>

#define SERIALIZATION_LIBRARY_NAME "fastrtps"

static ERL_NIF_TERM atom_type_description;
static ERL_NIF_TERM atom_referenced_type_descriptions;
static ERL_NIF_TERM atom_type_name;
static ERL_NIF_TERM atom_fields;
static ERL_NIF_TERM atom_name;
static ERL_NIF_TERM atom_type;
static ERL_NIF_TERM atom_default_value;
static ERL_NIF_TERM atom_type_id;
static ERL_NIF_TERM atom_capacity;
static ERL_NIF_TERM atom_string_capacity;
static ERL_NIF_TERM atom_nested_type_name;

static ERL_NIF_TERM atom_invalid_dynamic_type;
static ERL_NIF_TERM atom_invalid_type_description;
static ERL_NIF_TERM atom_invalid_message_map;
static ERL_NIF_TERM atom_dynamic_type_support_init_failed;
static ERL_NIF_TERM atom_dynamic_data_init_failed;
static ERL_NIF_TERM atom_unsupported_field_type;

void
make_dynamic_type_atoms(ErlNifEnv * env)
{
  atom_type_description = enif_make_atom(env, "type_description");
  atom_referenced_type_descriptions =
    enif_make_atom(env, "referenced_type_descriptions");
  atom_type_name = enif_make_atom(env, "type_name");
  atom_fields = enif_make_atom(env, "fields");
  atom_name = enif_make_atom(env, "name");
  atom_type = enif_make_atom(env, "type");
  atom_default_value = enif_make_atom(env, "default_value");
  atom_type_id = enif_make_atom(env, "type_id");
  atom_capacity = enif_make_atom(env, "capacity");
  atom_string_capacity = enif_make_atom(env, "string_capacity");
  atom_nested_type_name = enif_make_atom(env, "nested_type_name");

  atom_invalid_dynamic_type = enif_make_atom(env, "invalid_dynamic_type");
  atom_invalid_type_description = enif_make_atom(env, "invalid_type_description");
  atom_invalid_message_map = enif_make_atom(env, "invalid_message_map");
  atom_dynamic_type_support_init_failed =
    enif_make_atom(env, "dynamic_type_support_init_failed");
  atom_dynamic_data_init_failed = enif_make_atom(env, "dynamic_data_init_failed");
  atom_unsupported_field_type = enif_make_atom(env, "unsupported_field_type");
}

static bool
map_get(
  ErlNifEnv * env,
  ERL_NIF_TERM map,
  ERL_NIF_TERM key,
  ERL_NIF_TERM * value)
{
  if (!enif_is_map(env, map)) {
    return false;
  }

  return enif_get_map_value(env, map, key, value);
}

static bool
copy_binary_to_string(
  ErlNifEnv * env,
  ERL_NIF_TERM value,
  rosidl_runtime_c__String * out)
{
  ErlNifBinary binary;

  if (!enif_inspect_iolist_as_binary(env, value, &binary)) {
    return false;
  }

  return rosidl_runtime_c__String__assignn(
    out,
    (const char *)binary.data,
    binary.size);
}

static bool parse_field_type_map(
  ErlNifEnv * env,
  ERL_NIF_TERM field_type_term,
  rosidl_runtime_c__type_description__FieldType * out)
{
  if (out == NULL) {
    return false;
  }
  memset(out, 0, sizeof(*out));

  ERL_NIF_TERM type_id_term;
  ERL_NIF_TERM capacity_term;
  ERL_NIF_TERM string_capacity_term;
  ERL_NIF_TERM nested_type_name_term;

  unsigned int type_id;
  uint64_t capacity;
  uint64_t string_capacity;

  if (!map_get(env, field_type_term, atom_type_id, &type_id_term)) {
    return false;
  }

  if (!map_get(env, field_type_term, atom_capacity, &capacity_term)) {
    return false;
  }

  if (!map_get(env, field_type_term, atom_string_capacity, &string_capacity_term)) {
    return false;
  }

  if (!map_get(env, field_type_term, atom_nested_type_name, &nested_type_name_term)) {
    return false;
  }

  if (!enif_get_uint(env, type_id_term, &type_id)) {
    return false;
  }

  if (!enif_get_uint64(env, capacity_term, &capacity)) {
    return false;
  }

  if (!enif_get_uint64(env, string_capacity_term, &string_capacity)) {
    return false;
  }

  out->type_id = type_id;
  out->capacity = capacity;
  out->string_capacity = string_capacity;

  if (!copy_binary_to_string(env, nested_type_name_term, &out->nested_type_name)) {
    return false;
  }

  return true;
}

static bool parse_field_map(
  ErlNifEnv * env,
  ERL_NIF_TERM field_term,
  rosidl_runtime_c__type_description__Field * out)
{
  if (out == NULL) {
    return false;
  }
  memset(out, 0, sizeof(*out));

  ERL_NIF_TERM name_term;
  ERL_NIF_TERM type_term;
  ERL_NIF_TERM default_value_term;

  if (!map_get(env, field_term, atom_name, &name_term)) {
    return false;
  }

  if (!map_get(env, field_term, atom_type, &type_term)) {
    return false;
  }

  if (!map_get(env, field_term, atom_default_value, &default_value_term)) {
    return false;
  }

  if (!copy_binary_to_string(env, name_term, &out->name)) {
    return false;
  }

  if (!parse_field_type_map(env, type_term, &out->type)) {
    return false;
  }

  if (!copy_binary_to_string(env, default_value_term, &out->default_value)) {
    return false;
  }

  return true;
}

static bool parse_field_list(
  ErlNifEnv * env,
  ERL_NIF_TERM list_term,
  rosidl_runtime_c__type_description__Field__Sequence * out)
{
  unsigned int length;

  ERL_NIF_TERM head;
  ERL_NIF_TERM tail;

  if (!enif_get_list_length(env, list_term, &length)) {
    return false;
  }

  if (!rosidl_runtime_c__type_description__Field__Sequence__init(out, length)) {
    return false;
  }

  tail = list_term;

  for (unsigned int i = 0; i < length; i++) {
    if (!enif_get_list_cell(env, tail, &head, &tail)) {
      return false;
    }

    if (!parse_field_map(env, head, &out->data[i])) {
      return false;
    }
  }

  return true;
}

static bool parse_individual_type_description_map(
  ErlNifEnv * env,
  ERL_NIF_TERM individual_term,
  rosidl_runtime_c__type_description__IndividualTypeDescription * out)
{
  if (out == NULL) {
    return false;
  }
  memset(out, 0, sizeof(*out));

  ERL_NIF_TERM type_name_term;
  ERL_NIF_TERM fields_term;

  if (!map_get(env, individual_term, atom_type_name, &type_name_term)) {
    return false;
  }

  if (!map_get(env, individual_term, atom_fields, &fields_term)) {
    return false;
  }

  if (!copy_binary_to_string(env, type_name_term, &out->type_name)) {
    return false;
  }

  if (!parse_field_list(env, fields_term, &out->fields)) {
    return false;
  }

  return true;
}

static bool parse_referenced_type_descriptions(
  ErlNifEnv * env,
  ERL_NIF_TERM list_term,
  rosidl_runtime_c__type_description__IndividualTypeDescription__Sequence * out)
{
  unsigned int length;

  ERL_NIF_TERM head;
  ERL_NIF_TERM tail;

  if (!enif_get_list_length(env, list_term, &length)) {
    return false;
  }

  if (!rosidl_runtime_c__type_description__IndividualTypeDescription__Sequence__init(out, length)) {
    return false;
  }

  tail = list_term;

  for (unsigned int i = 0; i < length; i++) {
    if (!enif_get_list_cell(env, tail, &head, &tail)) {
      return false;
    }

    if (!parse_individual_type_description_map(env, head, &out->data[i])) {
      return false;
    }
  }

  return true;
}

static bool
parse_type_description_struct(
  ErlNifEnv * env,
  ERL_NIF_TERM type_description_struct,
  rosidl_runtime_c__type_description__TypeDescription * out)
{
  ERL_NIF_TERM type_description_term;
  ERL_NIF_TERM referenced_type_descriptions_term;

  if (!rosidl_runtime_c__type_description__TypeDescription__init(out)) {
    return false;
  }

  if (!map_get(env, type_description_struct, atom_type_description, &type_description_term)) {
    return false;
  }

  if (!map_get(
      env,
      type_description_struct,
      atom_referenced_type_descriptions,
      &referenced_type_descriptions_term))
  {
    return false;
  }

  if (!parse_individual_type_description_map(
      env,
      type_description_term,
      &out->type_description))
  {
    return false;
  }

  if (!parse_referenced_type_descriptions(
      env,
      referenced_type_descriptions_term,
      &out->referenced_type_descriptions))
  {
    return false;
  }

  return true;
}

static ERL_NIF_TERM
make_rcl_error(
  ErlNifEnv * env,
  ERL_NIF_TERM reason)
{
  const rcl_error_string_t error_string = rcl_get_error_string();
  ERL_NIF_TERM message = enif_make_string(env, error_string.str, ERL_NIF_LATIN1);

  rcl_reset_error();

  return enif_make_tuple2(
    env,
    atom_error,
    enif_make_tuple2(env, reason, message));
}

static ERL_NIF_TERM
make_rcutils_error(
  ErlNifEnv * env,
  ERL_NIF_TERM reason)
{
  const rcutils_error_string_t error_string = rcutils_get_error_string();
  ERL_NIF_TERM message = enif_make_string(env, error_string.str, ERL_NIF_LATIN1);

  rcutils_reset_error();

  return enif_make_tuple2(
    env,
    atom_error,
    enif_make_tuple2(env, reason, message));
}

void
dynamic_type_fini(dynamic_type_t * dynamic_type)
{
  if (dynamic_type == NULL) {
    return;
  }

  if (dynamic_type->type_atoms != NULL) {
    for (size_t i = 0; i < dynamic_type->num_type_atoms; i++) {
      if (dynamic_type->type_atoms[i].type_name != NULL) {
        enif_free(dynamic_type->type_atoms[i].type_name);
      }
      if (dynamic_type->type_atoms[i].field_atoms != NULL) {
        enif_free(dynamic_type->type_atoms[i].field_atoms);
      }
      if (dynamic_type->type_atoms[i].own_nested_dynamic_type &&
          dynamic_type->type_atoms[i].nested_dynamic_type_ptr != NULL)
      {
        (void)rosidl_dynamic_typesupport_dynamic_type_fini(
          dynamic_type->type_atoms[i].nested_dynamic_type_ptr);
        enif_free(dynamic_type->type_atoms[i].nested_dynamic_type_ptr);
        rcutils_reset_error();
        dynamic_type->type_atoms[i].nested_dynamic_type_ptr = NULL;
        dynamic_type->type_atoms[i].own_nested_dynamic_type = false;
      }
    }
    enif_free(dynamic_type->type_atoms);
    dynamic_type->type_atoms = NULL;
    dynamic_type->num_type_atoms = 0;
  }

  if (dynamic_type->type_support_initialized) {
    rcl_ret_t ret =
      rcl_dynamic_message_type_support_handle_fini(&dynamic_type->type_support);
    if (ret != RCL_RET_OK) {
      rcl_reset_error();
    }
    dynamic_type->type_support_initialized = false;
  }

  if (dynamic_type->type_description_initialized) {
    rosidl_runtime_c__type_description__TypeDescription__fini(&dynamic_type->type_description);
    dynamic_type->type_description_initialized = false;
  }

  memset(&dynamic_type->type_support, 0, sizeof(dynamic_type->type_support));
  memset(&dynamic_type->type_hash, 0, sizeof(dynamic_type->type_hash));
  memset(&dynamic_type->type_description, 0, sizeof(dynamic_type->type_description));
}

static void
dynamic_type_dtor(ErlNifEnv * env, void * obj)
{
  (void)env;
  dynamic_type_fini((dynamic_type_t *)obj);
}

static void
dynamic_ros_message_fini(dynamic_ros_message_t * dynamic_message)
{
  if (dynamic_message == NULL) {
    return;
  }

  if (dynamic_message->dynamic_data_initialized) {
    (void)rosidl_dynamic_typesupport_dynamic_data_fini(&dynamic_message->dynamic_data);
    rcutils_reset_error();
    dynamic_message->dynamic_data_initialized = false;
  }

  if (dynamic_message->dynamic_type_res != NULL) {
    enif_release_resource(dynamic_message->dynamic_type_res);
    dynamic_message->dynamic_type_res = NULL;
  }

  memset(&dynamic_message->dynamic_data, 0, sizeof(dynamic_message->dynamic_data));
}

static void
dynamic_ros_message_dtor(ErlNifEnv * env, void * obj)
{
  (void)env;
  dynamic_ros_message_fini((dynamic_ros_message_t *)obj);
}

bool
get_ros_message_data(
  ErlNifEnv * env,
  ERL_NIF_TERM message_term,
  void ** message_data_out)
{
  void ** ros_message_pp;
  dynamic_ros_message_t * dynamic_message;

  if (message_data_out == NULL) {
    return false;
  }

  if (enif_get_resource(env, message_term, rt_ros_message, (void **)&ros_message_pp)) {
    *message_data_out = *ros_message_pp;
    return true;
  }

  if (enif_get_resource(
      env,
      message_term,
      rt_dynamic_ros_message,
      (void **)&dynamic_message) && dynamic_message->dynamic_data_initialized)
  {
    *message_data_out = &dynamic_message->dynamic_data;
    return true;
  }

  return false;
}

static char *
nif_strdup(const char * str, size_t len)
{
  if (str == NULL) {
    return NULL;
  }

  char * copy = enif_alloc(len + 1);
  if (copy == NULL) {
    return NULL;
  }

  memcpy(copy, str, len);
  copy[len] = '\0';
  return copy;
}

static bool
atom_from_field_name(
  ErlNifEnv * env,
  const rosidl_runtime_c__String * field_name,
  ERL_NIF_TERM * atom)
{
  if (field_name == NULL || field_name->data == NULL || atom == NULL) {
    return false;
  }

  if (enif_make_existing_atom_len(
      env,
      field_name->data,
      field_name->size,
      atom,
      ERL_NIF_LATIN1))
  {
    return true;
  }

  *atom = enif_make_atom_len(env, field_name->data, field_name->size);
  return true;
}

static individual_type_atoms_t *
find_type_atoms(dynamic_type_t * dynamic_type, const char * type_name)
{
  if (dynamic_type == NULL || type_name == NULL) {
    return NULL;
  }

  for (size_t i = 0; i < dynamic_type->num_type_atoms; i++) {
    if (dynamic_type->type_atoms[i].type_name != NULL &&
        strcmp(dynamic_type->type_atoms[i].type_name, type_name) == 0)
    {
      return &dynamic_type->type_atoms[i];
    }
  }

  return NULL;
}

static bool
init_individual_type_atoms(
  ErlNifEnv * env,
  individual_type_atoms_t * type_info,
  const rosidl_runtime_c__type_description__IndividualTypeDescription * ind_type)
{
  if (type_info == NULL || ind_type == NULL) {
    return false;
  }

  type_info->type_name = nif_strdup(ind_type->type_name.data, ind_type->type_name.size);
  if (type_info->type_name == NULL && ind_type->type_name.size > 0) {
    return false;
  }

  type_info->num_field_atoms = ind_type->fields.size;
  if (type_info->num_field_atoms > 0) {
    type_info->field_atoms = enif_alloc(sizeof(ERL_NIF_TERM) * type_info->num_field_atoms);
    if (type_info->field_atoms == NULL) {
      return false;
    }

    for (size_t i = 0; i < type_info->num_field_atoms; i++) {
      const rosidl_runtime_c__type_description__Field * field = &ind_type->fields.data[i];
      if (!atom_from_field_name(env, &field->name, &type_info->field_atoms[i])) {
        return false;
      }
    }
  } else {
    type_info->field_atoms = NULL;
  }

  return true;
}

static const rosidl_runtime_c__type_description__IndividualTypeDescription *
find_individual_type_description(dynamic_type_t * dynamic_type, const char * type_name)
{
  if (dynamic_type == NULL || type_name == NULL) {
    return NULL;
  }

  const rosidl_runtime_c__type_description__TypeDescription * td = &dynamic_type->type_description;

  if (td->type_description.type_name.data != NULL &&
      strcmp(td->type_description.type_name.data, type_name) == 0)
  {
    return &td->type_description;
  }

  for (size_t i = 0; i < td->referenced_type_descriptions.size; i++) {
    const rosidl_runtime_c__type_description__IndividualTypeDescription * ind =
      &td->referenced_type_descriptions.data[i];
    if (ind->type_name.data != NULL && strcmp(ind->type_name.data, type_name) == 0) {
      return ind;
    }
  }

  return NULL;
}

static ERL_NIF_TERM
fill_dynamic_data(
  ErlNifEnv * env,
  dynamic_type_t * dynamic_type,
  const char * type_name,
  rosidl_dynamic_typesupport_dynamic_data_t * dynamic_data,
  ERL_NIF_TERM map_term);

static ERL_NIF_TERM
set_dynamic_field_value(
  ErlNifEnv * env,
  rosidl_dynamic_typesupport_dynamic_data_t * dynamic_data,
  const rosidl_runtime_c__type_description__Field * field,
  ERL_NIF_TERM value_term)
{
  rcutils_ret_t rc;
  rosidl_dynamic_typesupport_member_id_t member_id;

  if (field->name.data == NULL) {
    return enif_make_tuple2(env, atom_error, atom_invalid_message_map);
  }

  rc = rosidl_dynamic_typesupport_dynamic_data_get_member_id_by_name(
    dynamic_data,
    field->name.data,
    field->name.size,
    &member_id);

  if (rc != RCUTILS_RET_OK) {
    return make_rcutils_error(env, atom_invalid_message_map);
  }

  switch (field->type.type_id) {
    case rosidl_runtime_c__type_description__FieldType__FIELD_TYPE_BOOLEAN: {
      bool bool_value;

      if (enif_is_identical(value_term, atom_true)) {
        bool_value = true;
      } else if (enif_is_identical(value_term, atom_false)) {
        bool_value = false;
      } else {
        return enif_make_badarg(env);
      }

      rc = rosidl_dynamic_typesupport_dynamic_data_set_bool_value(
        dynamic_data,
        member_id,
        bool_value);
      break;
    }

    case rosidl_runtime_c__type_description__FieldType__FIELD_TYPE_INT8: {
      int int_value;

      if (!enif_get_int(env, value_term, &int_value)) {
        return enif_make_badarg(env);
      }

      rc = rosidl_dynamic_typesupport_dynamic_data_set_int8_value(
        dynamic_data,
        member_id,
        (int8_t)int_value);
      break;
    }

    case rosidl_runtime_c__type_description__FieldType__FIELD_TYPE_UINT8:
    case rosidl_runtime_c__type_description__FieldType__FIELD_TYPE_BYTE:
    case rosidl_runtime_c__type_description__FieldType__FIELD_TYPE_CHAR: {
      unsigned int uint_value;

      if (!enif_get_uint(env, value_term, &uint_value)) {
        return enif_make_badarg(env);
      }

      rc = rosidl_dynamic_typesupport_dynamic_data_set_uint8_value(
        dynamic_data,
        member_id,
        (uint8_t)uint_value);
      break;
    }

    case rosidl_runtime_c__type_description__FieldType__FIELD_TYPE_INT16: {
      int int_value;

      if (!enif_get_int(env, value_term, &int_value)) {
        return enif_make_badarg(env);
      }

      rc = rosidl_dynamic_typesupport_dynamic_data_set_int16_value(
        dynamic_data,
        member_id,
        (int16_t)int_value);
      break;
    }

    case rosidl_runtime_c__type_description__FieldType__FIELD_TYPE_UINT16: {
      unsigned int uint_value;

      if (!enif_get_uint(env, value_term, &uint_value)) {
        return enif_make_badarg(env);
      }

      rc = rosidl_dynamic_typesupport_dynamic_data_set_uint16_value(
        dynamic_data,
        member_id,
        (uint16_t)uint_value);
      break;
    }

    case rosidl_runtime_c__type_description__FieldType__FIELD_TYPE_INT32: {
      int int_value;

      if (!enif_get_int(env, value_term, &int_value)) {
        return enif_make_badarg(env);
      }

      rc = rosidl_dynamic_typesupport_dynamic_data_set_int32_value(
        dynamic_data,
        member_id,
        (int32_t)int_value);
      break;
    }

    case rosidl_runtime_c__type_description__FieldType__FIELD_TYPE_UINT32: {
      unsigned int uint_value;

      if (!enif_get_uint(env, value_term, &uint_value)) {
        return enif_make_badarg(env);
      }

      rc = rosidl_dynamic_typesupport_dynamic_data_set_uint32_value(
        dynamic_data,
        member_id,
        (uint32_t)uint_value);
      break;
    }

    case rosidl_runtime_c__type_description__FieldType__FIELD_TYPE_INT64: {
      int64_t int64_value;

      if (!enif_get_int64(env, value_term, &int64_value)) {
        return enif_make_badarg(env);
      }

      rc = rosidl_dynamic_typesupport_dynamic_data_set_int64_value(
        dynamic_data,
        member_id,
        int64_value);
      break;
    }

    case rosidl_runtime_c__type_description__FieldType__FIELD_TYPE_UINT64: {
      uint64_t uint64_value;

      if (!enif_get_uint64(env, value_term, &uint64_value)) {
        return enif_make_badarg(env);
      }

      rc = rosidl_dynamic_typesupport_dynamic_data_set_uint64_value(
        dynamic_data,
        member_id,
        uint64_value);
      break;
    }

    case rosidl_runtime_c__type_description__FieldType__FIELD_TYPE_FLOAT: {
      double double_value;

      if (!enif_get_double(env, value_term, &double_value)) {
        return enif_make_badarg(env);
      }

      rc = rosidl_dynamic_typesupport_dynamic_data_set_float32_value(
        dynamic_data,
        member_id,
        (float)double_value);
      break;
    }

    case rosidl_runtime_c__type_description__FieldType__FIELD_TYPE_DOUBLE:
    case rosidl_runtime_c__type_description__FieldType__FIELD_TYPE_LONG_DOUBLE: {
      double double_value;

      if (!enif_get_double(env, value_term, &double_value)) {
        return enif_make_badarg(env);
      }

      rc = rosidl_dynamic_typesupport_dynamic_data_set_float64_value(
        dynamic_data,
        member_id,
        double_value);
      break;
    }

    case rosidl_runtime_c__type_description__FieldType__FIELD_TYPE_STRING:
    case rosidl_runtime_c__type_description__FieldType__FIELD_TYPE_FIXED_STRING:
    case rosidl_runtime_c__type_description__FieldType__FIELD_TYPE_BOUNDED_STRING: {
      ErlNifBinary binary;

      if (!enif_inspect_iolist_as_binary(env, value_term, &binary)) {
        return enif_make_badarg(env);
      }

      char * str_buf = enif_alloc(binary.size + 1);
      if (str_buf == NULL) {
        return enif_make_tuple2(env, atom_error, enif_make_atom(env, "out_of_memory"));
      }

      memcpy(str_buf, binary.data, binary.size);
      str_buf[binary.size] = '\0';

      rc = rosidl_dynamic_typesupport_dynamic_data_set_string_value(
        dynamic_data,
        member_id,
        str_buf,
        binary.size);

      enif_free(str_buf);
      break;
    }

    case rosidl_runtime_c__type_description__FieldType__FIELD_TYPE_NOT_SET:
    case rosidl_runtime_c__type_description__FieldType__FIELD_TYPE_NESTED_TYPE:
    case rosidl_runtime_c__type_description__FieldType__FIELD_TYPE_WCHAR:
    case rosidl_runtime_c__type_description__FieldType__FIELD_TYPE_WSTRING:
    case rosidl_runtime_c__type_description__FieldType__FIELD_TYPE_FIXED_WSTRING:
    case rosidl_runtime_c__type_description__FieldType__FIELD_TYPE_BOUNDED_WSTRING:
    default:
      return enif_make_tuple2(env, atom_error, atom_unsupported_field_type);
  }

  if (rc != RCUTILS_RET_OK) {
    return make_rcutils_error(env, atom_dynamic_data_init_failed);
  }

  return atom_ok;
}

static ERL_NIF_TERM
fill_dynamic_data(
  ErlNifEnv * env,
  dynamic_type_t * dynamic_type,
  const char * type_name,
  rosidl_dynamic_typesupport_dynamic_data_t * dynamic_data,
  ERL_NIF_TERM map_term)
{
  if (!enif_is_map(env, map_term)) {
    return enif_make_tuple2(env, atom_error, atom_invalid_message_map);
  }

  const rosidl_runtime_c__type_description__IndividualTypeDescription * ind_type =
    find_individual_type_description(dynamic_type, type_name);

  individual_type_atoms_t * type_info =
    find_type_atoms(dynamic_type, type_name);

  if (ind_type == NULL || type_info == NULL) {
    return enif_make_tuple2(env, atom_error, atom_unsupported_field_type);
  }

  for (size_t i = 0; i < ind_type->fields.size; i++) {
    const rosidl_runtime_c__type_description__Field * field = &ind_type->fields.data[i];

    if (i >= type_info->num_field_atoms) {
      return enif_make_tuple2(env, atom_error, atom_invalid_message_map);
    }

    ERL_NIF_TERM field_key = type_info->field_atoms[i];
    ERL_NIF_TERM field_value;

    if (!enif_get_map_value(env, map_term, field_key, &field_value)) {
      return enif_make_tuple2(env, atom_error, atom_invalid_message_map);
    }

    rosidl_dynamic_typesupport_member_id_t member_id;
    rcutils_ret_t rc_id = rosidl_dynamic_typesupport_dynamic_data_get_member_id_by_name(
      dynamic_data,
      field->name.data,
      field->name.size,
      &member_id);

    if (rc_id != RCUTILS_RET_OK) {
      return make_rcutils_error(env, atom_invalid_message_map);
    }

    if (field->type.type_id == rosidl_runtime_c__type_description__FieldType__FIELD_TYPE_NESTED_TYPE) {
      if (field->type.nested_type_name.data == NULL) {
        return enif_make_tuple2(env, atom_error, atom_unsupported_field_type);
      }

      rosidl_dynamic_typesupport_dynamic_data_t nested_data;
      memset(&nested_data, 0, sizeof(nested_data));
      rcl_allocator_t allocator = get_nif_allocator();

      rcutils_ret_t rc = rosidl_dynamic_typesupport_dynamic_data_get_complex_value(
        dynamic_data,
        member_id,
        &allocator,
        &nested_data);

      if (rc != RCUTILS_RET_OK) {
        return make_rcutils_error(env, atom_dynamic_data_init_failed);
      }

      ERL_NIF_TERM ret = fill_dynamic_data(
        env,
        dynamic_type,
        field->type.nested_type_name.data,
        &nested_data,
        field_value);

      if (!enif_is_identical(ret, atom_ok)) {
        (void)rosidl_dynamic_typesupport_dynamic_data_fini(&nested_data);
        rcutils_reset_error();
        return ret;
      }

      rc = rosidl_dynamic_typesupport_dynamic_data_set_complex_value(
        dynamic_data,
        member_id,
        &nested_data);

      (void)rosidl_dynamic_typesupport_dynamic_data_fini(&nested_data);
      rcutils_reset_error();

      if (rc != RCUTILS_RET_OK) {
        return make_rcutils_error(env, atom_dynamic_data_init_failed);
      }
    } else {
      ERL_NIF_TERM ret =
        set_dynamic_field_value(env, dynamic_data, field, field_value);

      if (!enif_is_identical(ret, atom_ok)) {
        return ret;
      }
    }
  }

  return atom_ok;
}

ERL_NIF_TERM
nif_dynamic_type_from_description(
  ErlNifEnv * env,
  int argc,
  const ERL_NIF_TERM argv[])
{
  if (argc != 1) {
    return enif_make_badarg(env);
  }

  dynamic_type_t * dynamic_type =
    enif_alloc_resource(rt_dynamic_type, sizeof(dynamic_type_t));

  if (dynamic_type == NULL) {
    return enif_make_tuple2(env, atom_error, enif_make_atom(env, "out_of_memory"));
  }

  memset(dynamic_type, 0, sizeof(*dynamic_type));

  if (!parse_type_description_struct(env, argv[0], &dynamic_type->type_description)) {
    enif_release_resource(dynamic_type);
    return enif_make_tuple2(env, atom_error, atom_invalid_type_description);
  }

  rcutils_ret_t coerce_rc =
    rosidl_runtime_c_type_description_utils_coerce_to_valid_type_description_in_place(
      &dynamic_type->type_description);

  if (coerce_rc != RCUTILS_RET_OK) {
    dynamic_type_fini(dynamic_type);
    enif_release_resource(dynamic_type);
    return enif_make_tuple2(env, atom_error, atom_invalid_type_description);
  }

  dynamic_type->type_description_initialized = true;

  rcl_allocator_t allocator = get_nif_allocator();

  rcl_ret_t ret = rcl_dynamic_message_type_support_handle_init(
    SERIALIZATION_LIBRARY_NAME,
    &dynamic_type->type_description,
    &allocator,
    &dynamic_type->type_support);

  if (ret != RCL_RET_OK) {
    dynamic_type_fini(dynamic_type);
    enif_release_resource(dynamic_type);
    return make_rcl_error(env, atom_dynamic_type_support_init_failed);
  }

  dynamic_type->type_support_initialized = true;

  rosidl_dynamic_message_type_support_impl_t * ts_impl =
    (rosidl_dynamic_message_type_support_impl_t *) dynamic_type->type_support.data;

  const rosidl_runtime_c__type_description__TypeDescription * td = &dynamic_type->type_description;
  size_t num_referenced = td->referenced_type_descriptions.size;
  dynamic_type->num_type_atoms = 1 + num_referenced;
  dynamic_type->type_atoms = enif_alloc(sizeof(individual_type_atoms_t) * dynamic_type->num_type_atoms);

  if (dynamic_type->type_atoms == NULL) {
    dynamic_type_fini(dynamic_type);
    enif_release_resource(dynamic_type);
    return enif_make_tuple2(env, atom_error, enif_make_atom(env, "out_of_memory"));
  }

  memset(dynamic_type->type_atoms, 0, sizeof(individual_type_atoms_t) * dynamic_type->num_type_atoms);

  if (!init_individual_type_atoms(env, &dynamic_type->type_atoms[0], &td->type_description)) {
    dynamic_type_fini(dynamic_type);
    enif_release_resource(dynamic_type);
    return enif_make_tuple2(env, atom_error, atom_invalid_type_description);
  }

  if (ts_impl != NULL && ts_impl->dynamic_message_type != NULL) {
    dynamic_type->type_atoms[0].nested_dynamic_type_ptr = ts_impl->dynamic_message_type;
    dynamic_type->type_atoms[0].own_nested_dynamic_type = false;
  }

  for (size_t i = 0; i < num_referenced; i++) {
    const rosidl_runtime_c__type_description__IndividualTypeDescription * indiv_desc =
      &td->referenced_type_descriptions.data[i];

    if (!init_individual_type_atoms(env, &dynamic_type->type_atoms[i + 1], indiv_desc)) {
      dynamic_type_fini(dynamic_type);
      enif_release_resource(dynamic_type);
      return enif_make_tuple2(env, atom_error, atom_invalid_type_description);
    }

    rosidl_runtime_c__type_description__TypeDescription * sub_td = NULL;
    rcutils_ret_t rc_sub =
      rosidl_runtime_c_type_description_utils_get_referenced_type_description_as_type_description(
        &td->referenced_type_descriptions,
        indiv_desc,
        &sub_td,
        true);

    if (rc_sub == RCUTILS_RET_OK && sub_td != NULL && ts_impl != NULL) {
      rosidl_dynamic_typesupport_dynamic_type_t * sub_dt =
        enif_alloc(sizeof(rosidl_dynamic_typesupport_dynamic_type_t));

      if (sub_dt != NULL) {
        memset(sub_dt, 0, sizeof(*sub_dt));
        rcutils_ret_t rc_dt = rosidl_dynamic_typesupport_dynamic_type_init_from_description(
          &ts_impl->serialization_support,
          sub_td,
          &allocator,
          sub_dt);

        if (rc_dt == RCUTILS_RET_OK) {
          dynamic_type->type_atoms[i + 1].nested_dynamic_type_ptr = sub_dt;
          dynamic_type->type_atoms[i + 1].own_nested_dynamic_type = true;
        } else {
          enif_free(sub_dt);
        }
      }
    }
  }

  ERL_NIF_TERM term = enif_make_resource(env, dynamic_type);
  enif_release_resource(dynamic_type);

  return enif_make_tuple2(env, atom_ok, term);
}

ERL_NIF_TERM
nif_dynamic_type_fini(
  ErlNifEnv * env,
  int argc,
  const ERL_NIF_TERM argv[])
{
  if (argc != 1) {
    return enif_make_badarg(env);
  }

  dynamic_type_t * dynamic_type;

  if (!enif_get_resource(env, argv[0], rt_dynamic_type, (void **)&dynamic_type)) {
    return enif_make_badarg(env);
  }

  return atom_ok;
}

ERL_NIF_TERM
nif_dynamic_type_fill_message(
  ErlNifEnv * env,
  int argc,
  const ERL_NIF_TERM argv[])
{
  if (argc != 2) {
    return enif_make_badarg(env);
  }

  dynamic_type_t * dynamic_type;

  if (!enif_get_resource(env, argv[0], rt_dynamic_type, (void **)&dynamic_type)) {
    return enif_make_badarg(env);
  }

  if (!dynamic_type->type_support_initialized) {
    return enif_make_tuple2(env, atom_error, atom_invalid_dynamic_type);
  }

  rosidl_dynamic_message_type_support_impl_t * ts_impl =
    (rosidl_dynamic_message_type_support_impl_t *) dynamic_type->type_support.data;

  if (ts_impl == NULL || ts_impl->dynamic_message_type == NULL) {
    return enif_make_tuple2(env, atom_error, atom_invalid_dynamic_type);
  }

  if (!enif_is_map(env, argv[1])) {
    return enif_make_tuple2(env, atom_error, atom_invalid_message_map);
  }

  dynamic_ros_message_t * dynamic_message =
    enif_alloc_resource(rt_dynamic_ros_message, sizeof(dynamic_ros_message_t));

  if (dynamic_message == NULL) {
    return enif_make_tuple2(env, atom_error, enif_make_atom(env, "out_of_memory"));
  }

  memset(dynamic_message, 0, sizeof(*dynamic_message));

  dynamic_message->dynamic_type_res = dynamic_type;
  enif_keep_resource(dynamic_type);

  rcl_allocator_t allocator = get_nif_allocator();

  rcutils_ret_t rcutils_rc = rosidl_dynamic_typesupport_dynamic_data_init_from_dynamic_type(
    ts_impl->dynamic_message_type,
    &allocator,
    &dynamic_message->dynamic_data);

  if (rcutils_rc != RCUTILS_RET_OK) {
    dynamic_ros_message_fini(dynamic_message);
    enif_release_resource(dynamic_message);
    return make_rcutils_error(env, atom_dynamic_data_init_failed);
  }

  dynamic_message->dynamic_data_initialized = true;

  if (dynamic_type->num_type_atoms == 0 || dynamic_type->type_atoms == NULL) {
    dynamic_ros_message_fini(dynamic_message);
    enif_release_resource(dynamic_message);
    return enif_make_tuple2(env, atom_error, atom_invalid_dynamic_type);
  }

  ERL_NIF_TERM ret = fill_dynamic_data(
    env,
    dynamic_type,
    dynamic_type->type_atoms[0].type_name,
    &dynamic_message->dynamic_data,
    argv[1]);

  if (!enif_is_identical(ret, atom_ok)) {
    dynamic_ros_message_fini(dynamic_message);
    enif_release_resource(dynamic_message);
    return ret;
  }

  ERL_NIF_TERM message_term = enif_make_resource(env, dynamic_message);
  enif_release_resource(dynamic_message);

  return enif_make_tuple2(env, atom_ok, message_term);
}

ERL_NIF_TERM
nif_dynamic_message_destroy(
  ErlNifEnv * env,
  int argc,
  const ERL_NIF_TERM argv[])
{
  if (argc != 1) {
    return enif_make_badarg(env);
  }

  dynamic_ros_message_t * dynamic_message;

  if (!enif_get_resource(env, argv[0], rt_dynamic_ros_message, (void **)&dynamic_message)) {
    return enif_make_badarg(env);
  }

  dynamic_ros_message_fini(dynamic_message);

  return atom_ok;
}

int
dynamic_type_resource_init(ErlNifEnv * env)
{
  ErlNifResourceFlags flags = ERL_NIF_RT_CREATE | ERL_NIF_RT_TAKEOVER;

  rt_dynamic_type = enif_open_resource_type(
    env,
    NULL,
    "dynamic_type",
    dynamic_type_dtor,
    flags,
    NULL);

  if (rt_dynamic_type == NULL) {
    return 1;
  }

  rt_dynamic_ros_message = enif_open_resource_type(
    env,
    NULL,
    "dynamic_ros_message",
    dynamic_ros_message_dtor,
    flags,
    NULL);

  if (rt_dynamic_ros_message == NULL) {
    return 1;
  }

  return 0;
}

#endif
