#include "rcl_node.h"
#include "allocator.h"
#include "resource_types.h"
#include "terms.h"
#include <erl_nif.h>
#include <rcl/arguments.h>
#include <rcl/context.h>
#include <rcl/node.h>
#include <rcl/node_options.h>
#include <rcl/types.h>
#include <rcl/wait.h>
#include <rmw/ret_types.h>
#include <rmw/validate_namespace.h>
#include <rmw/validate_node_name.h>
#include <stddef.h>
#include <string.h>

static bool parse_ros_args(ErlNifEnv *env, ERL_NIF_TERM list_term, int *argc_out, char ***argv_out) {
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
      for (unsigned int j = 0; j < i; j++) enif_free(argv[j]);
      enif_free(argv);
      return false;
    }

    ErlNifBinary bin;
    if (!enif_inspect_iolist_as_binary(env, head, &bin)) {
      for (unsigned int j = 0; j < i; j++) enif_free(argv[j]);
      enif_free(argv);
      return false;
    }

    argv[i] = enif_alloc(bin.size + 1);
    if (argv[i] == NULL) {
      for (unsigned int j = 0; j < i; j++) enif_free(argv[j]);
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

ERL_NIF_TERM atom_new_graph_event;
ERL_NIF_TERM atom_exit;
ERL_NIF_TERM atom_adding_to_waitset_failed;

void make_node_atoms(ErlNifEnv *env) {
  atom_new_graph_event          = enif_make_atom(env, "new_graph_event");
  atom_adding_to_waitset_failed = enif_make_atom(env, "adding_to_waitset_failed");
}

ERL_NIF_TERM nif_rcl_node_init(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 3 && argc != 4) return enif_make_badarg(env);

  rcl_context_t *context_p;
  if (!enif_get_resource(env, argv[0], rt_rcl_context_t, (void **)&context_p))
    return enif_make_badarg(env);
  if (!rcl_context_is_valid(context_p)) return raise(env, __FILE__, __LINE__);

  rmw_ret_t rm;
  int validation_result;

  char name[256];
  if (enif_get_string(env, argv[1], name, sizeof(name), ERL_NIF_LATIN1) <= 0)
    return enif_make_badarg(env);
  rm = rmw_validate_node_name(name, &validation_result, NULL);
  if (rm != RMW_RET_OK) return raise(env, __FILE__, __LINE__);
  if (validation_result != RMW_NODE_NAME_VALID) {
    const char *message = rmw_node_name_validation_result_string(validation_result);
    return raise_with_message(env, __FILE__, __LINE__, message);
  }

  char namespace[256];
  if (enif_get_string(env, argv[2], namespace, sizeof(namespace), ERL_NIF_LATIN1) <= 0)
    return enif_make_badarg(env);
  rm = rmw_validate_namespace(namespace, &validation_result, NULL);
  if (rm != RMW_RET_OK) return raise(env, __FILE__, __LINE__);
  if (validation_result != RMW_NAMESPACE_VALID) {
    const char *message = rmw_namespace_validation_result_string(validation_result);
    return raise_with_message(env, __FILE__, __LINE__, message);
  }

  rcl_ret_t rc;
  rcl_node_t node                 = rcl_get_zero_initialized_node();
  rcl_node_options_t node_options = rcl_node_get_default_options();
  node_options.allocator          = get_nif_allocator();

  int ros_argc = 0;
  char **ros_argv = NULL;

  if (argc == 4 && !parse_ros_args(env, argv[3], &ros_argc, &ros_argv)) return enif_make_badarg(env);

  if (ros_argc > 0) {
    rc = rcl_parse_arguments(ros_argc, (const char *const *)ros_argv, node_options.allocator,
                             &node_options.arguments);
    free_ros_args(ros_argc, ros_argv);
    if (rc != RCL_RET_OK) {
      rcl_ret_t fini_rc = rcl_node_options_fini(&node_options);
      if (fini_rc != RCL_RET_OK) {
      }
      return raise(env, __FILE__, __LINE__);
    }
  }

  rc = rcl_node_init(&node, name, namespace, context_p, &node_options);
  if (rc != RCL_RET_OK) {
    rcl_ret_t fini_rc = rcl_node_options_fini(&node_options);
    if (fini_rc != RCL_RET_OK) {
    }
    return raise(env, __FILE__, __LINE__);
  }

  rc = rcl_node_options_fini(&node_options);
  if (rc != RCL_RET_OK) return raise(env, __FILE__, __LINE__);

  rcl_node_t *obj   = enif_alloc_resource(rt_rcl_node_t, sizeof(rcl_node_t));
  *obj              = node;
  ERL_NIF_TERM term = enif_make_resource(env, obj);
  enif_release_resource(obj);

  return term;
}

ERL_NIF_TERM nif_rcl_node_fini(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 1) return enif_make_badarg(env);

  rcl_node_t *node_p;
  if (!enif_get_resource(env, argv[0], rt_rcl_node_t, (void **)&node_p))
    return enif_make_badarg(env);
  if (!rcl_node_is_valid(node_p)) return raise(env, __FILE__, __LINE__);

  rcl_ret_t rc;

  rc = rcl_node_fini(node_p);
  if (rc != RCL_RET_OK) return raise(env, __FILE__, __LINE__);

  return atom_ok;
}

ERL_NIF_TERM nif_rcl_node_get_domain_id(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 1) return enif_make_badarg(env);

  rcl_node_t *node_p;
  if (!enif_get_resource(env, argv[0], rt_rcl_node_t, (void **)&node_p))
    return enif_make_badarg(env);
  if (!rcl_node_is_valid(node_p))
    return raise_with_safe_message(env, __FILE__, __LINE__, RCL_RET_INVALID_ARGUMENT);

  rcl_ret_t rc;
  size_t domain_id;
  rc = rcl_node_get_domain_id(node_p, &domain_id);
  if (rc != RCL_RET_OK) return raise_with_safe_message(env, __FILE__, __LINE__, rc);

  return enif_make_uint(env, domain_id);
}

ERL_NIF_TERM nif_rcl_node_get_graph_guard_condition(ErlNifEnv *env, int argc,
                                                    const ERL_NIF_TERM argv[]) {
  if (argc != 1) return enif_make_badarg(env);

  rcl_node_t *node_p;
  if (!enif_get_resource(env, argv[0], rt_rcl_node_t, (void **)&node_p))
    return enif_make_badarg(env);
  if (!rcl_node_is_valid(node_p))
    return raise_with_safe_message(env, __FILE__, __LINE__, RCL_RET_INVALID_ARGUMENT);

  const rcl_guard_condition_t *guard_condition_p = rcl_node_get_graph_guard_condition(node_p);
  if (guard_condition_p == NULL)
    return raise_with_safe_message(env, __FILE__, __LINE__, RCL_RET_ERROR);

  rcl_guard_condition_t *obj =
      enif_alloc_resource(rt_rcl_guard_condition_t, sizeof(rcl_guard_condition_t));

  *obj              = *guard_condition_p;
  ERL_NIF_TERM term = enif_make_resource(env, obj);
  enif_release_resource(obj);
  return term;
}

static void *graph_guard_waiter(void *arg) {
  thread_ctx_t *ctx_p = (thread_ctx_t *)arg;
  ERL_NIF_TERM msg;
  rcl_ret_t rc;
  ErlNifEnv *env          = enif_alloc_env();
  rcl_wait_set_t wait_set = rcl_get_zero_initialized_wait_set();
  rc = rcl_wait_set_init(&wait_set, 0, 2, 0, 0, 0, 0, &ctx_p->context, rcl_get_default_allocator());
  if (rc != RCL_RET_OK) {
    msg = enif_make_tuple(env, 2, atom_error, atom_new_graph_event);
    enif_send(NULL, &ctx_p->pid, env, msg);
    enif_free_env(env);
    return NULL;
  }

  size_t index_event;
  size_t index_exit;
  bool got_exit_signal = false;
  while (!got_exit_signal) {
    rc = rcl_wait_set_clear(&wait_set);

    rc = rcl_wait_set_add_guard_condition(&wait_set, &ctx_p->wait_condition, &index_event);
    if (rc != RCL_RET_OK) {
      msg = enif_make_tuple(env, 2, atom_error, atom_adding_to_waitset_failed);
      enif_send(NULL, &ctx_p->pid, env, msg);
      enif_clear_env(env);
    }

    rc = rcl_wait_set_add_guard_condition(&wait_set, &ctx_p->exit_condition, &index_exit);
    if (rc != RCL_RET_OK) {
      msg = enif_make_tuple(env, 2, atom_error, atom_adding_to_waitset_failed);
      enif_send(NULL, &ctx_p->pid, env, msg);
      enif_clear_env(env);
    }

    rc = rcl_wait(&wait_set, RCL_MS_TO_NS(10000)); // 10000ms == 10s, passed as ns
    if (rc == RCL_RET_TIMEOUT) {
      continue;
    }

    if (wait_set.guard_conditions[index_exit]) {
      got_exit_signal = true;
    }

    if (wait_set.guard_conditions[index_event]) {
      msg = enif_make_tuple(env, 2, atom_new_graph_event, enif_make_uint(env, index_event));
      enif_send(NULL, &ctx_p->pid, env, msg);
      enif_clear_env(env);
    }
  }

  rc = rcl_wait_set_fini(&wait_set);
  if (rc != RCL_RET_OK) {
    msg = enif_make_tuple(env, 2, atom_error, atom_new_graph_event);
    enif_send(NULL, &ctx_p->pid, env, msg);
    enif_clear_env(env);
  }

  enif_free_env(env);
  return NULL;
}

ERL_NIF_TERM nif_node_start_waitset_thread(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {

  if (argc != 2) return enif_make_badarg(env);

  rcl_context_t *context_p;
  if (!enif_get_resource(env, argv[0], rt_rcl_context_t, (void **)&context_p))
    return enif_make_badarg(env);
  if (!rcl_context_is_valid(context_p)) return raise(env, __FILE__, __LINE__);

  rcl_guard_condition_t *guard_condition_p;
  if (!enif_get_resource(env, argv[1], rt_rcl_guard_condition_t, (void **)&guard_condition_p))
    return enif_make_badarg(env);

  thread_ctx_t *ctx_p = (thread_ctx_t *)enif_alloc_resource(rt_thread_ctx_t, sizeof(thread_ctx_t));
  if (ctx_p == NULL) return raise_with_safe_message(env, __FILE__, __LINE__, RCL_RET_BAD_ALLOC);

  if (!enif_self(env, &ctx_p->pid)) return raise(env, __FILE__, __LINE__);

  ctx_p->opts_p  = enif_thread_opts_create("node_guard_thread_options");
  ctx_p->context = *context_p;

  ctx_p->exit_condition = rcl_get_zero_initialized_guard_condition();
  rcl_guard_condition_options_t guard_condition_options = rcl_guard_condition_get_default_options();
  guard_condition_options.allocator                     = get_nif_allocator();

  rcl_ret_t rc;

  rc = rcl_guard_condition_init(&ctx_p->exit_condition, context_p, guard_condition_options);
  if (rc != RCL_RET_OK) return raise_with_safe_message(env, __FILE__, __LINE__, rc);

  ctx_p->wait_condition = *guard_condition_p;

  int errno = enif_thread_create("node_guard_thread", &(ctx_p->tid), &graph_guard_waiter, ctx_p,
                                 ctx_p->opts_p);
  if (errno != 0) return raise(env, __FILE__, __LINE__);

  ERL_NIF_TERM term = enif_make_resource(env, ctx_p);
  enif_release_resource(ctx_p);

  return term;
}

ERL_NIF_TERM nif_node_stop_waitset_thread(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {

  if (argc != 1) return enif_make_badarg(env);

  thread_ctx_t *ctx_p;
  if (!enif_get_resource(env, argv[0], rt_thread_ctx_t, (void **)&ctx_p))
    return enif_make_badarg(env);

  rcl_ret_t rc;

  rc = rcl_trigger_guard_condition(&ctx_p->exit_condition);
  if (rc != RCL_RET_OK) return raise_with_safe_message(env, __FILE__, __LINE__, rc);

  void *exit_value;
  int errno = enif_thread_join(ctx_p->tid, &exit_value);

  enif_thread_opts_destroy(ctx_p->opts_p);

  rc = rcl_guard_condition_fini(&ctx_p->exit_condition);
  if (rc != RCL_RET_OK) return raise_with_safe_message(env, __FILE__, __LINE__, rc);

  if (errno != 0) {
    return raise_with_message(env, __FILE__, __LINE__, "joining thread failed");
  }

  return atom_ok;
}
