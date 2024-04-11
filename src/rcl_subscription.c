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
  if (rc != RCL_RET_OK) return raise(env, __FILE__, __LINE__);

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
  rc = rcl_subscription_fini(subscription_p, node_p);
  if (rc != RCL_RET_OK) return raise(env, __FILE__, __LINE__);

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
  if (rc == RCL_RET_SUBSCRIPTION_TAKE_FAILED) return atom_error;
  return raise(env, __FILE__, __LINE__);
}

ERL_NIF_TERM nif_rcl_subscription_can_loan_messages(ErlNifEnv *env, int argc,
                                                    const ERL_NIF_TERM argv[]) {
  if (argc != 1) return enif_make_badarg(env);

  rcl_subscription_t *subscription_p;
  if (!enif_get_resource(env, argv[0], rt_rcl_subscription_t, (void **)&subscription_p))
    return enif_make_badarg(env);
  if (!rcl_subscription_is_valid(subscription_p)) return raise(env, __FILE__, __LINE__);

  if (rcl_subscription_can_loan_messages(subscription_p)) {
    return atom_true;
  } else {
    return atom_false;
  }
}

ERL_NIF_TERM nif_rcl_take_loaned_message(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 1) return enif_make_badarg(env);

  rcl_ret_t rc;

  rcl_subscription_t *subscription_p;
  if (!enif_get_resource(env, argv[0], rt_rcl_subscription_t, (void **)&subscription_p))
    return enif_make_badarg(env);
  if (!rcl_subscription_is_valid(subscription_p)) return raise(env, __FILE__, __LINE__);

  rmw_message_info_t message_info;
  void *ros_message_p;
  rc = rcl_take_loaned_message(subscription_p, &ros_message_p, &message_info, NULL);
  if (rc == RCL_RET_OK) {
    void **obj        = enif_alloc_resource(rt_ros_message, sizeof(void *));
    *obj              = (void *)ros_message_p;
    ERL_NIF_TERM term = enif_make_resource(env, obj);
    enif_release_resource(obj);
    return enif_make_tuple2(env, atom_ok, term);
  } else if (rc == RCL_RET_SUBSCRIPTION_TAKE_FAILED)
    return atom_error;
  else if (rc == RCL_RET_SUBSCRIPTION_INVALID) // if the passed subscription is invalid
    return raise_with_message(env, __FILE__, __LINE__, "passed subscription is invalid");
  else if (rc == RCL_RET_INVALID_ARGUMENT) // if any arguments are invalid
    return enif_make_badarg(env);
  else if (rc == RCL_RET_UNSUPPORTED)
    return raise_with_message(env, __FILE__, __LINE__, "middleware does not support that feature");
  else // (rc == RCL_RET_ERROR)
    return raise_with_message(env, __FILE__, __LINE__, "unspecified error");
}

ERL_NIF_TERM nif_rcl_return_loaned_message_from_subscription(ErlNifEnv *env, int argc,
                                                             const ERL_NIF_TERM argv[]) {
  if (argc != 2) return enif_make_badarg(env);

  rcl_ret_t rc;

  rcl_subscription_t *subscription_p;
  if (!enif_get_resource(env, argv[0], rt_rcl_subscription_t, (void **)&subscription_p))
    return enif_make_badarg(env);
  if (!rcl_subscription_is_valid(subscription_p)) return raise(env, __FILE__, __LINE__);

  void **ros_message_pp;
  if (!enif_get_resource(env, argv[1], rt_ros_message, (void **)&ros_message_pp))
    return enif_make_badarg(env);

  rc = rcl_return_loaned_message_from_subscription(subscription_p, *ros_message_pp);
  if (rc == RCL_RET_OK)
    return atom_ok;
  else if (rc == RCL_RET_SUBSCRIPTION_INVALID) // if the passed subscription is invalid
    return raise_with_message(env, __FILE__, __LINE__, "passed subscription is invalid");
  else if (rc == RCL_RET_INVALID_ARGUMENT) // if any arguments are invalid
    return enif_make_badarg(env);
  else if (rc == RCL_RET_UNSUPPORTED)
    return raise_with_message(env, __FILE__, __LINE__, "middleware does not support that feature");
  else // (rc == RCL_RET_ERROR)
    return raise_with_message(env, __FILE__, __LINE__, "unspecified error");
}