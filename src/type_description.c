#ifndef ROS_DISTRO_humble

#include "type_description.h"
#include "terms.h"

#include <stddef.h>
#include <stdio.h>

static ERL_NIF_TERM make_string_term(ErlNifEnv *env, const rosidl_runtime_c__String *string) {
  return enif_make_binary_wrapper(env, string->data, string->size);
}

static ERL_NIF_TERM
make_field_type_term(ErlNifEnv *env,
                     const rosidl_runtime_c__type_description__FieldType *field_type) {
  ERL_NIF_TERM nested_type_name = make_string_term(env, &field_type->nested_type_name);

  return enif_make_tuple4(env, enif_make_uint(env, field_type->type_id),
                          enif_make_uint64(env, field_type->capacity),
                          enif_make_uint64(env, field_type->string_capacity), nested_type_name);
}

static ERL_NIF_TERM make_field_term(ErlNifEnv *env,
                                    const rosidl_runtime_c__type_description__Field *field) {
  return enif_make_tuple3(env, make_string_term(env, &field->name),
                          make_field_type_term(env, &field->type),
                          make_string_term(env, &field->default_value));
}

static ERL_NIF_TERM make_individual_type_description_term(
    ErlNifEnv *env,
    const rosidl_runtime_c__type_description__IndividualTypeDescription *description) {
  ERL_NIF_TERM *fields = NULL;
  if (description->fields.size > 0) {
    fields = enif_alloc(sizeof(ERL_NIF_TERM) * description->fields.size);
    if (fields == NULL) return enif_make_badarg(env);

    for (size_t i = 0; i < description->fields.size; i++) {
      fields[i] = make_field_term(env, &description->fields.data[i]);
    }
  }

  ERL_NIF_TERM field_list = enif_make_list_from_array(env, fields, description->fields.size);
  if (fields != NULL) enif_free(fields);

  return enif_make_tuple2(env, make_string_term(env, &description->type_name), field_list);
}

ERL_NIF_TERM
make_type_description_term(ErlNifEnv *env,
                           const rosidl_runtime_c__type_description__TypeDescription *description) {
  ERL_NIF_TERM *referenced = NULL;
  if (description->referenced_type_descriptions.size > 0) {
    referenced = enif_alloc(sizeof(ERL_NIF_TERM) * description->referenced_type_descriptions.size);
    if (referenced == NULL) return enif_make_badarg(env);

    for (size_t i = 0; i < description->referenced_type_descriptions.size; i++) {
      referenced[i] = make_individual_type_description_term(
          env, &description->referenced_type_descriptions.data[i]);
    }
  }

  ERL_NIF_TERM referenced_list =
      enif_make_list_from_array(env, referenced, description->referenced_type_descriptions.size);
  if (referenced != NULL) enif_free(referenced);

  return enif_make_tuple2(
      env, make_individual_type_description_term(env, &description->type_description),
      referenced_list);
}

ERL_NIF_TERM
make_type_sources_term(ErlNifEnv *env,
                       const rosidl_runtime_c__type_description__TypeSource__Sequence *sources) {
  ERL_NIF_TERM *source_terms = NULL;
  if (sources->size > 0) {
    source_terms = enif_alloc(sizeof(ERL_NIF_TERM) * sources->size);
    if (source_terms == NULL) return enif_make_badarg(env);

    for (size_t i = 0; i < sources->size; i++) {
      const rosidl_runtime_c__type_description__TypeSource *source = &sources->data[i];
      source_terms[i] = enif_make_tuple3(env, make_string_term(env, &source->type_name),
                                         make_string_term(env, &source->encoding),
                                         make_string_term(env, &source->raw_file_contents));
    }
  }

  ERL_NIF_TERM source_list = enif_make_list_from_array(env, source_terms, sources->size);
  if (source_terms != NULL) enif_free(source_terms);
  return source_list;
}

ERL_NIF_TERM make_type_hash_term(ErlNifEnv *env, const rosidl_type_hash_t *hash) {
  char hash_string[8 + (ROSIDL_TYPE_HASH_SIZE * 2)];
  int written = snprintf(hash_string, sizeof(hash_string), "RIHS%02u_", hash->version);
  if (written < 0 || (size_t)written >= sizeof(hash_string)) return enif_make_badarg(env);

  for (size_t i = 0; i < ROSIDL_TYPE_HASH_SIZE; i++) {
    if (snprintf(hash_string + written + (i * 2), 3, "%02x", hash->value[i]) != 2)
      return enif_make_badarg(env);
  }

  return enif_make_string_len(env, hash_string, written + (ROSIDL_TYPE_HASH_SIZE * 2),
                              ERL_NIF_LATIN1);
}

#endif
