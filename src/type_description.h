#include <erl_nif.h>
#include <rosidl_runtime_c/type_description/type_description__struct.h>
#include <rosidl_runtime_c/type_description/type_source__struct.h>
#include <rosidl_runtime_c/type_hash.h>

ERL_NIF_TERM
make_type_description_term(ErlNifEnv *env,
                           const rosidl_runtime_c__type_description__TypeDescription *description);

ERL_NIF_TERM
make_type_sources_term(ErlNifEnv *env,
                       const rosidl_runtime_c__type_description__TypeSource__Sequence *sources);

ERL_NIF_TERM make_type_hash_term(ErlNifEnv *env, const rosidl_type_hash_t *hash);
