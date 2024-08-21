// clang-format off
#include "rotate_absolute.h"
#include "../../../macros.h"
#include "../../../resource_types.h"
#include "../../../terms.h"

#include <erl_nif.h>

#include <rosidl_runtime_c/action_type_support_struct.h>
#include <turtlesim/action/rotate_absolute.h>

ERL_NIF_TERM nif_turtlesim_action_rotate_absolute_type_support(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  ignore_unused(argv);

  if (argc != 0) return enif_make_badarg(env);

  const rosidl_action_type_support_t * ts_p = ROSIDL_GET_ACTION_TYPE_SUPPORT(turtlesim, RotateAbsolute);
  rosidl_action_type_support_t *obj = enif_alloc_resource(rt_rosidl_action_type_support_t, sizeof(rosidl_action_type_support_t));
  *obj = *ts_p;
  ERL_NIF_TERM term = enif_make_resource(env, obj);
  enif_release_resource(obj);

  return term;
}
