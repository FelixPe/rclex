#ifndef RCLEX_DYNAMIC_TYPE_H
#define RCLEX_DYNAMIC_TYPE_H

#include <stdbool.h>

#include <erl_nif.h>

#if !defined(ROS_DISTRO_humble) && defined(HAVE_ROSIDL_DYNAMIC_TYPESUPPORT)
#include <rcl/dynamic_message_type_support.h>
#include <rcl/type_hash.h>

#include <rosidl_dynamic_typesupport/api/dynamic_data.h>
#include <rosidl_dynamic_typesupport/api/dynamic_type.h>
#include <rosidl_dynamic_typesupport/api/serialization_support.h>
#include <rosidl_dynamic_typesupport/dynamic_message_type_support_struct.h>

#include <rosidl_runtime_c/message_type_support_struct.h>
#include <rosidl_runtime_c/type_description/type_description__struct.h>
#endif

extern ErlNifResourceType *rt_dynamic_type;
extern ErlNifResourceType *rt_dynamic_ros_message;

#if !defined(ROS_DISTRO_humble) && defined(HAVE_ROSIDL_DYNAMIC_TYPESUPPORT)
typedef struct individual_type_atoms_s
{
  char * type_name;
  rosidl_dynamic_typesupport_dynamic_type_t * nested_dynamic_type_ptr;
  bool own_nested_dynamic_type;
  ERL_NIF_TERM * field_atoms;
  size_t num_field_atoms;
} individual_type_atoms_t;

typedef struct dynamic_type_s
{
  rosidl_runtime_c__type_description__TypeDescription type_description;
  rosidl_type_hash_t type_hash;
  rosidl_message_type_support_t type_support;

  individual_type_atoms_t * type_atoms;
  size_t num_type_atoms;

  bool type_description_initialized;
  bool type_support_initialized;
} dynamic_type_t;

typedef struct dynamic_ros_message_s
{
  dynamic_type_t * dynamic_type_res;
  rosidl_dynamic_typesupport_dynamic_data_t dynamic_data;

  bool dynamic_data_initialized;
} dynamic_ros_message_t;
#else
typedef struct dynamic_type_s
{
  bool unsupported_on_humble;
} dynamic_type_t;

typedef struct dynamic_ros_message_s
{
  bool unsupported_on_humble;
} dynamic_ros_message_t;
#endif

void make_dynamic_type_atoms(ErlNifEnv * env);

ERL_NIF_TERM nif_dynamic_type_from_description(
  ErlNifEnv * env,
  int argc,
  const ERL_NIF_TERM argv[]);

ERL_NIF_TERM nif_dynamic_type_fini(
  ErlNifEnv * env,
  int argc,
  const ERL_NIF_TERM argv[]);

ERL_NIF_TERM nif_dynamic_type_fill_message(
  ErlNifEnv * env,
  int argc,
  const ERL_NIF_TERM argv[]);

ERL_NIF_TERM nif_dynamic_message_destroy(
  ErlNifEnv * env,
  int argc,
  const ERL_NIF_TERM argv[]);

int dynamic_type_resource_init(ErlNifEnv *env);

void dynamic_type_fini(dynamic_type_t *dynamic_type);

bool get_ros_message_data(
  ErlNifEnv * env,
  ERL_NIF_TERM message_term,
  void ** message_data_out);


#endif