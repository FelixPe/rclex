#include "rcl_init.h"
#include "allocator.h"
#include "macros.h"
#include "resource_types.h"
#include "terms.h"
#include <erl_nif.h>
#include <rcl/allocator.h>
#include <rcl/context.h>
#include <rcl/init.h>
#include <rcl/init_options.h>
#include <rcl/types.h>
#include <stddef.h>
#include <string.h>

static bool parse_ros_args(ErlNifEnv *env, ERL_NIF_TERM list_term, int *argc_out,
                           char ***argv_out) {
  unsigned int length;
  if (!enif_get_list_length(env, list_term, &length)) return false;

  if (length == 0) {
    *argc_out = 0;
    *argv_out = NULL;
    return true;
  }

  char **argv = enif_alloc(sizeof(char *) * length);
  if (argv == NULL) return false;

  ERL_NIF_TERM head;
  ERL_NIF_TERM tail = list_term;

  for (unsigned int i = 0; i < length; i++) {
    if (!enif_get_list_cell(env, tail, &head, &tail)) {
      for (unsigned int j = 0; j < i; j++)
        enif_free(argv[j]);
      enif_free(argv);
      return false;
    }

    ErlNifBinary bin;
    if (!enif_inspect_iolist_as_binary(env, head, &bin)) {
      for (unsigned int j = 0; j < i; j++)
        enif_free(argv[j]);
      enif_free(argv);
      return false;
    }

    argv[i] = enif_alloc(bin.size + 1);
    if (argv[i] == NULL) {
      for (unsigned int j = 0; j < i; j++)
        enif_free(argv[j]);
      enif_free(argv);
      return false;
    }

    memcpy(argv[i], bin.data, bin.size);
    argv[i][bin.size] = '\0';
  }

  *argc_out = (int)length;
  *argv_out = argv;
  return true;
}

static void free_ros_args(int argc, char **argv) {
  if (argv == NULL) return;
  for (int i = 0; i < argc; i++) {
    enif_free(argv[i]);
  }
  enif_free(argv);
}

ERL_NIF_TERM nif_rcl_init(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 0 && argc != 1) return enif_make_badarg(env);

  int ros_argc    = 0;
  char **ros_argv = NULL;

  if (argc == 1 && !parse_ros_args(env, argv[0], &ros_argc, &ros_argv))
    return enif_make_badarg(env);

  rcl_ret_t rc;
  rcl_init_options_t init_options = rcl_get_zero_initialized_init_options();
  rcl_allocator_t allocator       = get_nif_allocator();
  rcl_context_t context           = rcl_get_zero_initialized_context();

  rc = rcl_init_options_init(&init_options, allocator);
  if (rc != RCL_RET_OK) return raise(env, __FILE__, __LINE__);

  rc = rcl_init(ros_argc, (const char *const *)ros_argv, &init_options, &context);
  free_ros_args(ros_argc, ros_argv);
  if (rc != RCL_RET_OK) return raise(env, __FILE__, __LINE__);

  rc = rcl_init_options_fini(&init_options);
  if (rc != RCL_RET_OK) return raise(env, __FILE__, __LINE__);

  rcl_context_t *obj = enif_alloc_resource(rt_rcl_context_t, sizeof(rcl_context_t));
  *obj               = context;
  ERL_NIF_TERM term  = enif_make_resource(env, obj);
  enif_release_resource(obj);

  return term;
}

ERL_NIF_TERM nif_rcl_fini(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 1) return enif_make_badarg(env);

  rcl_ret_t rc;
  rcl_context_t *context_p;

  if (!enif_get_resource(env, argv[0], rt_rcl_context_t, (void **)&context_p))
    return enif_make_badarg(env);
  if (!rcl_context_is_valid(context_p)) return raise(env, __FILE__, __LINE__);

  rc = rcl_shutdown(context_p);
  if (rc != RCL_RET_OK) return raise(env, __FILE__, __LINE__);

  rc = rcl_context_fini(context_p);
  if (rc != RCL_RET_OK) return raise(env, __FILE__, __LINE__);

  return atom_ok;
}
