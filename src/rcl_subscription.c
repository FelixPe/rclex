#include "rcl_subscription.h"
#include "allocator.h"
#include "qos.h"
#include "resource_types.h"
#include "terms.h"
#include <erl_nif.h>
#include <rcl/node.h>
#include <rcl/subscription.h>
#include <rcl/types.h>
#include <rmw/ret_types.h>
#include <rmw/types.h>
#include <rmw/validate_full_topic_name.h>
#include <rosidl_runtime_c/message_type_support_struct.h>
#include <stddef.h>

ERL_NIF_TERM subscription_take_failed;
ERL_NIF_TERM new_message;

typedef struct {
  ErlNifPid pid;
  int active;
  void *owner;
  int (*owner_is_valid)(const void *);
} callback_resource_t;

static int subscription_owner_is_valid(const void *owner) {
  return rcl_subscription_is_valid((const rcl_subscription_t *)owner);
}

static int callback_resource_should_drop(const callback_resource_t *callback_resource) {
  if (callback_resource == NULL || !callback_resource->active) return 1;
  if (!enif_is_process_alive(NULL, &((callback_resource_t *)callback_resource)->pid)) {
    ((callback_resource_t *)callback_resource)->active = 0;
    return 1;
  }
  if (callback_resource->owner != NULL && callback_resource->owner_is_valid != NULL &&
      !callback_resource->owner_is_valid(callback_resource->owner)) {
    ((callback_resource_t *)callback_resource)->active = 0;
    return 1;
  }
  return 0;
}

void make_subscription_atoms(ErlNifEnv *env) {
  subscription_take_failed = enif_make_atom(env, "subscription_take_failed");
  new_message              = enif_make_atom(env, "new_message");
}

ERL_NIF_TERM nif_rcl_subscription_init(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 4) return enif_make_badarg(env);

  rcl_node_t *node_p;
  if (!enif_get_resource(env, argv[0], rt_rcl_node_t, (void **)&node_p))
    return enif_make_badarg(env);
  if (!rcl_node_is_valid(node_p)) return raise(env, __FILE__, __LINE__);

  rosidl_message_type_support_t *ts_p;
  if (!enif_get_resource(env, argv[1], rt_rosidl_message_type_support_t, (void **)&ts_p))
    return enif_make_badarg(env);

  rmw_ret_t rm;
  int validation_result;

  char topic_name[256];
  if (enif_get_string(env, argv[2], topic_name, sizeof(topic_name), ERL_NIF_LATIN1) <= 0)
    return enif_make_badarg(env);
  rm = rmw_validate_full_topic_name(topic_name, &validation_result, NULL);
  if (rm != RMW_RET_OK) return raise(env, __FILE__, __LINE__);
  if (validation_result != RMW_TOPIC_VALID) {
    const char *message = rmw_full_topic_name_validation_result_string(validation_result);
    return raise_with_message(env, __FILE__, __LINE__, message);
  }

  ERL_NIF_TERM qos_map = argv[3];
  rmw_qos_profile_t qos;
  ERL_NIF_TERM ret = get_c_qos_profile(env, qos_map, &qos);
  if (enif_is_exception(env, ret)) return ret;

  rcl_ret_t rc;
  rcl_subscription_t subscription                 = rcl_get_zero_initialized_subscription();
  rcl_subscription_options_t subscription_options = rcl_subscription_get_default_options();
  subscription_options.allocator                  = get_nif_allocator();
  subscription_options.qos                        = qos;

  rc = rcl_subscription_init(&subscription, node_p, ts_p, topic_name, &subscription_options);
  if (rc != RCL_RET_OK) return raise_with_safe_message(env, __FILE__, __LINE__, rc);

  rcl_subscription_t *obj = enif_alloc_resource(rt_rcl_subscription_t, sizeof(rcl_subscription_t));
  *obj                    = subscription;
  ERL_NIF_TERM term       = enif_make_resource(env, obj);
  enif_release_resource(obj);

  return term;
}

ERL_NIF_TERM nif_rcl_subscription_fini(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 2) return enif_make_badarg(env);

  rcl_subscription_t *subscription_p;
  if (!enif_get_resource(env, argv[0], rt_rcl_subscription_t, (void **)&subscription_p))
    return enif_make_badarg(env);
  if (!rcl_subscription_is_valid(subscription_p)) return raise(env, __FILE__, __LINE__);

  rcl_node_t *node_p;
  if (!enif_get_resource(env, argv[1], rt_rcl_node_t, (void **)&node_p))
    return enif_make_badarg(env);
  if (!rcl_node_is_valid(node_p)) return raise(env, __FILE__, __LINE__);

  rcl_ret_t rc;
  rc = rcl_subscription_set_on_new_message_callback(subscription_p, NULL, NULL);
  if (rc != RCL_RET_OK) return raise_with_safe_message(env, __FILE__, __LINE__, rc);

  rc = rcl_subscription_fini(subscription_p, node_p);
  if (rc != RCL_RET_OK) return raise_with_safe_message(env, __FILE__, __LINE__, rc);

  return atom_ok;
}

ERL_NIF_TERM nif_rcl_take(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 2) return enif_make_badarg(env);

  rcl_ret_t rc;

  rcl_subscription_t *subscription_p;
  if (!enif_get_resource(env, argv[0], rt_rcl_subscription_t, (void **)&subscription_p))
    return enif_make_badarg(env);
  if (!rcl_subscription_is_valid(subscription_p)) return raise(env, __FILE__, __LINE__);

  void **ros_message_pp;
  if (!enif_get_resource(env, argv[1], rt_ros_message, (void **)&ros_message_pp))
    return enif_make_badarg(env);

  rc = rcl_take(subscription_p, *ros_message_pp, NULL, NULL);
  if (rc == RCL_RET_OK) return atom_ok;
  if (rc == RCL_RET_SUBSCRIPTION_TAKE_FAILED) return subscription_take_failed;
  return raise(env, __FILE__, __LINE__);
}

ERL_NIF_TERM nif_rcl_take_with_info(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 2) return enif_make_badarg(env);

  rcl_ret_t rc;

  rcl_subscription_t *subscription_p;
  if (!enif_get_resource(env, argv[0], rt_rcl_subscription_t, (void **)&subscription_p))
    return enif_make_badarg(env);
  if (!rcl_subscription_is_valid(subscription_p)) return raise(env, __FILE__, __LINE__);

  void **ros_message_pp;
  if (!enif_get_resource(env, argv[1], rt_ros_message, (void **)&ros_message_pp))
    return enif_make_badarg(env);

  rmw_message_info_t info = rmw_get_zero_initialized_message_info();
  rc                      = rcl_take(subscription_p, *ros_message_pp, &info, NULL);
  if (rc == RCL_RET_SUBSCRIPTION_TAKE_FAILED) return subscription_take_failed;
  if (rc != RCL_RET_OK) return raise_with_safe_message(env, __FILE__, __LINE__, rc);

  ERL_NIF_TERM gid_bin;
  unsigned char *gid_data = enif_make_new_binary(env, RMW_GID_STORAGE_SIZE, &gid_bin);
  for (size_t i = 0; i < RMW_GID_STORAGE_SIZE; ++i) {
    gid_data[i] = info.publisher_gid.data[i];
  }

  ERL_NIF_TERM keys[6] = {
      enif_make_atom(env, "source_timestamp"),
      enif_make_atom(env, "received_timestamp"),
      enif_make_atom(env, "publication_sequence_number"),
      enif_make_atom(env, "reception_sequence_number"),
      enif_make_atom(env, "publisher_gid"),
      enif_make_atom(env, "from_intra_process"),
  };
  ERL_NIF_TERM values[6] = {
      enif_make_int64(env, info.source_timestamp),
      enif_make_int64(env, info.received_timestamp),
      enif_make_uint64(env, info.publication_sequence_number),
      enif_make_uint64(env, info.reception_sequence_number),
      gid_bin,
      info.from_intra_process ? atom_true : atom_false,
  };

  ERL_NIF_TERM info_map;
  if (!enif_make_map_from_arrays(env, keys, values, 6, &info_map))
    return raise(env, __FILE__, __LINE__);

  return enif_make_tuple2(env, atom_ok, info_map);
}

static void new_message_callback(const void *user_data, size_t number_of_events) {
  callback_resource_t *callback_resource = (callback_resource_t *)user_data;
  if (callback_resource_should_drop(callback_resource)) return;

  ErlNifEnv *env = enif_alloc_env();
  enif_send(env, &callback_resource->pid, env,
            enif_make_tuple(env, 2, new_message, enif_make_int(env, number_of_events)));
  enif_free_env(env);
}

ERL_NIF_TERM nif_rcl_subscription_set_on_new_message_callback(ErlNifEnv *env, int argc,
                                                              const ERL_NIF_TERM argv[]) {
  if (argc != 1) return enif_make_badarg(env);

  rcl_subscription_t *subscription_p;
  if (!enif_get_resource(env, argv[0], rt_rcl_subscription_t, (void **)&subscription_p))
    return enif_make_badarg(env);
  if (!rcl_subscription_is_valid(subscription_p)) return raise(env, __FILE__, __LINE__);

  callback_resource_t *callback_resource = (callback_resource_t *)enif_alloc_resource(
      rt_subscription_callback_resource, sizeof(callback_resource_t));
  if (enif_self(env, &callback_resource->pid) == NULL) return raise(env, __FILE__, __LINE__);
  callback_resource->active         = 1;
  callback_resource->owner          = subscription_p;
  callback_resource->owner_is_valid = subscription_owner_is_valid;
  enif_keep_resource(callback_resource);

  rcl_ret_t rc;
  rc = rcl_subscription_set_on_new_message_callback(subscription_p, new_message_callback,
                                                    (const void *)callback_resource);
  if (rc != RCL_RET_OK) return raise_with_safe_message(env, __FILE__, __LINE__, rc);

  return enif_make_resource(env, callback_resource);
}

ERL_NIF_TERM nif_rcl_subscription_clear_message_callback(ErlNifEnv *env, int argc,
                                                         const ERL_NIF_TERM argv[]) {
  if (argc != 2) return enif_make_badarg(env);

  rcl_subscription_t *subscription_p;
  if (!enif_get_resource(env, argv[0], rt_rcl_subscription_t, (void **)&subscription_p))
    return enif_make_badarg(env);
  if (!rcl_subscription_is_valid(subscription_p)) return raise(env, __FILE__, __LINE__);

  callback_resource_t *callback_resource = NULL;
  if (!enif_get_resource(env, argv[1], rt_subscription_callback_resource,
                         (void **)&callback_resource))
    return enif_make_badarg(env);

  callback_resource->active = 0;

  rcl_ret_t rc;
  rc = rcl_subscription_set_on_new_message_callback(subscription_p, NULL, NULL);
  if (rc != RCL_RET_OK) return raise_with_safe_message(env, __FILE__, __LINE__, rc);

  enif_release_resource(callback_resource);

  return atom_ok;
}
