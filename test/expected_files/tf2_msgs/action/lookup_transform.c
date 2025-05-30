// clang-format off
#include "lookup_transform.h"
#include "../../../macros.h"
#include "../../../resource_types.h"
#include "../../../terms.h"

#include <erl_nif.h>

#include <rosidl_runtime_c/action_type_support_struct.h>
#include <tf2_msgs/action/lookup_transform.h>

ERL_NIF_TERM nif_tf2_msgs_action_lookup_transform_type_support(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  ignore_unused(argv);

  if (argc != 0) return enif_make_badarg(env);

  const rosidl_action_type_support_t * ts_p = ROSIDL_GET_ACTION_TYPE_SUPPORT(tf2_msgs, LookupTransform);
  rosidl_action_type_support_t *obj = enif_alloc_resource(rt_rosidl_action_type_support_t, sizeof(rosidl_action_type_support_t));
  *obj = *ts_p;
  ERL_NIF_TERM term = enif_make_resource(env, obj);
  enif_release_resource(obj);

  return term;
}
