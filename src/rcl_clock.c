#include "rcl_clock.h"
#include "allocator.h"
#include "macros.h"
#include "resource_types.h"
#include "terms.h"
#include <erl_nif.h>
#include <rcl/allocator.h>
#include <rcl/time.h>
#include <rcl/types.h>

ERL_NIF_TERM nif_rcl_clock_init(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  rcl_ret_t rc;
  rcl_clock_t clock;
  rcl_allocator_t allocator       = get_nif_allocator();
  rcl_clock_type_t rcl_clock_type = RCL_STEADY_TIME;

  ERL_NIF_TERM clock_type = argv[0];
  if (argc == 1) {
    if (!enif_is_atom(env, clock_type)) {
      return enif_make_badarg(env);
    }

    if (enif_compare(clock_type, atom_steady_time) == 0) {
      rcl_clock_type = RCL_STEADY_TIME;
    } else if (enif_compare(clock_type, atom_system_time) == 0) {
      rcl_clock_type = RCL_SYSTEM_TIME;
    } else if (enif_compare(clock_type, atom_ros_time) == 0) {
      rcl_clock_type = RCL_ROS_TIME;
    }
  }

  rc = rcl_clock_init(rcl_clock_type, &clock, &allocator);
  if (rc != RCL_RET_OK) return enif_make_badarg(env);

  rcl_clock_t *obj  = enif_alloc_resource(rt_rcl_clock_t, sizeof(rcl_clock_t));
  *obj              = clock;
  ERL_NIF_TERM term = enif_make_resource(env, obj);
  enif_release_resource(obj);

  return term;
}

ERL_NIF_TERM nif_rcl_clock_get_now(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 1) return enif_make_badarg(env);

  rcl_clock_t *clock_p;
  if (!enif_get_resource(env, argv[0], rt_rcl_clock_t, (void **)&clock_p))
    return enif_make_badarg(env);

  rcl_ret_t rc;
  rcl_time_point_value_t time_point_value;
  rc = rcl_clock_get_now(clock_p, &time_point_value);
  if (rc != RCL_RET_OK) return enif_make_badarg(env);
  ERL_NIF_TERM term = enif_make_uint64(env, time_point_value);

  return term;
}

ERL_NIF_TERM nif_rcl_clock_fini(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 1) return enif_make_badarg(env);

  rcl_clock_t *clock_p;
  if (!enif_get_resource(env, argv[0], rt_rcl_clock_t, (void **)&clock_p))
    return enif_make_badarg(env);

  rcl_ret_t rc;
  rc = rcl_clock_fini(clock_p);
  if (rc != RCL_RET_OK) return enif_make_badarg(env);

  return atom_ok;
}
