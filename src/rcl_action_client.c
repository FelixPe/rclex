#include "rcl_action_client.h"
#include "allocator.h"
#include "qos.h"
#include "resource_types.h"
#include "terms.h"
#include <erl_nif.h>
#include <rcl/node.h>
#include <rcl/types.h>
#include <rcl_action/rcl_action.h>
#include <rmw/ret_types.h>
#include <rmw/types.h>
#include <rmw/validate_full_topic_name.h>
#include <rosidl_runtime_c/message_type_support_struct.h>
#include <stddef.h>

ERL_NIF_TERM atom_action_client_take_failed;
ERL_NIF_TERM atom_new_cancel_response;
ERL_NIF_TERM atom_new_feedback;
ERL_NIF_TERM atom_new_goal_response;
ERL_NIF_TERM atom_new_result_response;
ERL_NIF_TERM atom_new_status;

typedef struct {
  ErlNifPid pid;
  int active;
  void *owner;
  int (*owner_is_valid)(const void *);
} callback_resource_t;

static int action_client_owner_is_valid(const void *owner) {
  return rcl_action_client_is_valid((const rcl_action_client_t *)owner);
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

void make_action_client_atoms(ErlNifEnv *env) {
  atom_new_cancel_response       = enif_make_atom(env, "new_cancel_response");
  atom_new_feedback              = enif_make_atom(env, "new_feedback");
  atom_new_goal_response         = enif_make_atom(env, "new_goal_response");
  atom_new_result_response       = enif_make_atom(env, "new_result_response");
  atom_new_status                = enif_make_atom(env, "new_status");
  atom_action_client_take_failed = enif_make_atom(env, "action_client_take_failed");
}

ERL_NIF_TERM nif_rcl_action_client_init(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 4) return enif_make_badarg(env);

  rcl_node_t *node_p;
  if (!enif_get_resource(env, argv[0], rt_rcl_node_t, (void **)&node_p))
    return enif_make_badarg(env);
  if (!rcl_node_is_valid(node_p)) return raise(env, __FILE__, __LINE__);

  rosidl_action_type_support_t *ts_p;
  if (!enif_get_resource(env, argv[1], rt_rosidl_action_type_support_t, (void **)&ts_p))
    return enif_make_badarg(env);

  rmw_ret_t rm;
  int validation_result;

  char action_name[256];
  if (enif_get_string(env, argv[2], action_name, sizeof(action_name), ERL_NIF_LATIN1) <= 0)
    return enif_make_badarg(env);
  rm = rmw_validate_full_topic_name(action_name, &validation_result, NULL);
  if (rm != RMW_RET_OK) return raise(env, __FILE__, __LINE__);
  if (validation_result != RMW_TOPIC_VALID) {
    const char *message = rmw_full_topic_name_validation_result_string(validation_result);
    return raise_with_message(env, __FILE__, __LINE__, message);
  }

  int arity;
  const ERL_NIF_TERM *qos_tuple;
  if (!enif_get_tuple(env, argv[3], &arity, &qos_tuple) || arity != 5) return enif_make_badarg(env);

  ERL_NIF_TERM goal_service_qos_map   = qos_tuple[0];
  ERL_NIF_TERM result_service_qos_map = qos_tuple[1];
  ERL_NIF_TERM cancel_service_qos_map = qos_tuple[2];
  ERL_NIF_TERM feedback_topic_qos_map = qos_tuple[3];
  ERL_NIF_TERM status_topic_qos_map   = qos_tuple[4];

  ERL_NIF_TERM ret;
  rmw_qos_profile_t goal_service_qos, result_service_qos, cancel_service_qos, feedback_topic_qos,
      status_topic_qos;

  ret = get_c_qos_profile(env, goal_service_qos_map, &goal_service_qos);
  if (enif_is_exception(env, ret)) return ret;

  ret = get_c_qos_profile(env, result_service_qos_map, &result_service_qos);
  if (enif_is_exception(env, ret)) return ret;

  ret = get_c_qos_profile(env, cancel_service_qos_map, &cancel_service_qos);
  if (enif_is_exception(env, ret)) return ret;

  ret = get_c_qos_profile(env, feedback_topic_qos_map, &feedback_topic_qos);
  if (enif_is_exception(env, ret)) return ret;

  ret = get_c_qos_profile(env, status_topic_qos_map, &status_topic_qos);
  if (enif_is_exception(env, ret)) return ret;

  rcl_ret_t rc;
  rcl_action_client_t action_client                 = rcl_action_get_zero_initialized_client();
  rcl_action_client_options_t action_client_options = rcl_action_client_get_default_options();
  action_client_options.allocator                   = get_nif_allocator();
  action_client_options.goal_service_qos   = goal_service_qos;   // rmw_qos_profile_services_default
  action_client_options.result_service_qos = result_service_qos; // rmw_qos_profile_services_default
  action_client_options.cancel_service_qos = cancel_service_qos; // rmw_qos_profile_services_default
  action_client_options.feedback_topic_qos = feedback_topic_qos; // rmw_qos_profile_default
  action_client_options.status_topic_qos =
      status_topic_qos; // rcl_action_qos_profile_status_default

  rc = rcl_action_client_init(&action_client, node_p, ts_p, action_name, &action_client_options);
  if (rc != RCL_RET_OK) return raise_with_safe_message(env, __FILE__, __LINE__, rc);

  rcl_action_client_t *obj =
      enif_alloc_resource(rt_rcl_action_client_t, sizeof(rcl_action_client_t));
  *obj              = action_client;
  ERL_NIF_TERM term = enif_make_resource(env, obj);
  enif_release_resource(obj);

  return term;
}

ERL_NIF_TERM nif_rcl_action_client_fini(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 2) return enif_make_badarg(env);

  rcl_action_client_t *action_client_p;
  if (!enif_get_resource(env, argv[0], rt_rcl_action_client_t, (void **)&action_client_p))
    return enif_make_badarg(env);
  if (!rcl_action_client_is_valid(action_client_p)) return raise(env, __FILE__, __LINE__);

  rcl_node_t *node_p;
  if (!enif_get_resource(env, argv[1], rt_rcl_node_t, (void **)&node_p))
    return enif_make_badarg(env);
  if (!rcl_node_is_valid(node_p)) return raise(env, __FILE__, __LINE__);

  rcl_ret_t rc;
  rc = rcl_action_client_set_cancel_client_callback(action_client_p, NULL, NULL);
  if (rc != RCL_RET_OK) return raise_with_safe_message(env, __FILE__, __LINE__, rc);
  rc = rcl_action_client_set_feedback_subscription_callback(action_client_p, NULL, NULL);
  if (rc != RCL_RET_OK) return raise_with_safe_message(env, __FILE__, __LINE__, rc);
  rc = rcl_action_client_set_goal_client_callback(action_client_p, NULL, NULL);
  if (rc != RCL_RET_OK) return raise_with_safe_message(env, __FILE__, __LINE__, rc);
  rc = rcl_action_client_set_result_client_callback(action_client_p, NULL, NULL);
  if (rc != RCL_RET_OK) return raise_with_safe_message(env, __FILE__, __LINE__, rc);
  rc = rcl_action_client_set_status_subscription_callback(action_client_p, NULL, NULL);
  if (rc != RCL_RET_OK) return raise_with_safe_message(env, __FILE__, __LINE__, rc);

  rc = rcl_action_client_fini(action_client_p, node_p);
  if (rc != RCL_RET_OK) return raise_with_safe_message(env, __FILE__, __LINE__, rc);

  return atom_ok;
}

ERL_NIF_TERM nif_rcl_action_take_cancel_response(ErlNifEnv *env, int argc,
                                                 const ERL_NIF_TERM argv[]) {
  if (argc != 2) return enif_make_badarg(env);

  rcl_ret_t rc;
  rmw_request_id_t response_header;

  rcl_action_client_t *action_client_p;
  if (!enif_get_resource(env, argv[0], rt_rcl_action_client_t, (void **)&action_client_p))
    return enif_make_badarg(env);
  if (!rcl_action_client_is_valid(action_client_p)) return raise(env, __FILE__, __LINE__);

  void **ros_response_message_pp;
  if (!enif_get_resource(env, argv[1], rt_ros_message, (void **)&ros_response_message_pp))
    return enif_make_badarg(env);

  rc = rcl_action_take_cancel_response(action_client_p, &response_header, *ros_response_message_pp);
  int64_t sequence_number = response_header.sequence_number;

  if (rc == RCL_RET_OK)
    return enif_make_tuple2(env, atom_ok, enif_make_int64(env, sequence_number));
  if (rc == RCL_RET_ACTION_CLIENT_TAKE_FAILED) return atom_action_client_take_failed;
  return raise_with_safe_message(env, __FILE__, __LINE__, rc);
}

ERL_NIF_TERM nif_rcl_action_take_feedback(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 2) return enif_make_badarg(env);

  rcl_ret_t rc;

  rcl_action_client_t *action_client_p;
  if (!enif_get_resource(env, argv[0], rt_rcl_action_client_t, (void **)&action_client_p))
    return enif_make_badarg(env);
  if (!rcl_action_client_is_valid(action_client_p)) return raise(env, __FILE__, __LINE__);

  void **ros_response_message_pp;
  if (!enif_get_resource(env, argv[1], rt_ros_message, (void **)&ros_response_message_pp))
    return enif_make_badarg(env);

  rc = rcl_action_take_feedback(action_client_p, *ros_response_message_pp);

  if (rc == RCL_RET_OK) return atom_ok;
  if (rc == RCL_RET_ACTION_CLIENT_TAKE_FAILED) return atom_action_client_take_failed;
  return raise_with_safe_message(env, __FILE__, __LINE__, rc);
}

ERL_NIF_TERM nif_rcl_action_take_goal_response(ErlNifEnv *env, int argc,
                                               const ERL_NIF_TERM argv[]) {
  if (argc != 2) return enif_make_badarg(env);

  rcl_ret_t rc;
  rmw_request_id_t response_header;

  rcl_action_client_t *action_client_p;
  if (!enif_get_resource(env, argv[0], rt_rcl_action_client_t, (void **)&action_client_p))
    return enif_make_badarg(env);
  if (!rcl_action_client_is_valid(action_client_p)) return raise(env, __FILE__, __LINE__);

  void **ros_response_message_pp;
  if (!enif_get_resource(env, argv[1], rt_ros_message, (void **)&ros_response_message_pp))
    return enif_make_badarg(env);

  rc = rcl_action_take_goal_response(action_client_p, &response_header, *ros_response_message_pp);
  int64_t sequence_number = response_header.sequence_number;

  if (rc == RCL_RET_OK)
    return enif_make_tuple2(env, atom_ok, enif_make_int64(env, sequence_number));
  if (rc == RCL_RET_ACTION_CLIENT_TAKE_FAILED) return atom_action_client_take_failed;
  return raise_with_safe_message(env, __FILE__, __LINE__, rc);
}

ERL_NIF_TERM nif_rcl_action_take_result_response(ErlNifEnv *env, int argc,
                                                 const ERL_NIF_TERM argv[]) {
  if (argc != 2) return enif_make_badarg(env);

  rcl_ret_t rc;
  rmw_request_id_t response_header;

  rcl_action_client_t *action_client_p;
  if (!enif_get_resource(env, argv[0], rt_rcl_action_client_t, (void **)&action_client_p))
    return enif_make_badarg(env);
  if (!rcl_action_client_is_valid(action_client_p)) return raise(env, __FILE__, __LINE__);

  void **ros_response_message_pp;
  if (!enif_get_resource(env, argv[1], rt_ros_message, (void **)&ros_response_message_pp))
    return enif_make_badarg(env);

  rc = rcl_action_take_result_response(action_client_p, &response_header, *ros_response_message_pp);
  int64_t sequence_number = response_header.sequence_number;

  if (rc == RCL_RET_OK)
    return enif_make_tuple2(env, atom_ok, enif_make_int64(env, sequence_number));
  if (rc == RCL_RET_ACTION_CLIENT_TAKE_FAILED) return atom_action_client_take_failed;
  return raise_with_safe_message(env, __FILE__, __LINE__, rc);
}

ERL_NIF_TERM nif_rcl_action_take_status(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 2) return enif_make_badarg(env);

  rcl_ret_t rc;

  rcl_action_client_t *action_client_p;
  if (!enif_get_resource(env, argv[0], rt_rcl_action_client_t, (void **)&action_client_p))
    return enif_make_badarg(env);
  if (!rcl_action_client_is_valid(action_client_p)) return raise(env, __FILE__, __LINE__);

  void **ros_status_array_pp;
  if (!enif_get_resource(env, argv[1], rt_ros_message, (void **)&ros_status_array_pp))
    return enif_make_badarg(env);

  rc = rcl_action_take_status(action_client_p, *ros_status_array_pp);
  if (rc == RCL_RET_OK)
    return atom_ok;
  else if (rc == RCL_RET_ACTION_CLIENT_TAKE_FAILED)
    return atom_action_client_take_failed;
  else if (rc == RCL_RET_INVALID_ARGUMENT)
    return raise_with_safe_message(env, __FILE__, __LINE__, rc);
  else if (rc == RCL_RET_ACTION_CLIENT_INVALID)
    return raise_with_safe_message(env, __FILE__, __LINE__, rc);
  else if (rc == RCL_RET_BAD_ALLOC)
    return raise_with_safe_message(env, __FILE__, __LINE__, rc);
  else if (rc == RCL_RET_ERROR)
    return raise_with_safe_message(env, __FILE__, __LINE__, rc);
  else
    return raise_with_safe_message(env, __FILE__, __LINE__, rc);
}

ERL_NIF_TERM nif_rcl_action_send_cancel_request(ErlNifEnv *env, int argc,
                                                const ERL_NIF_TERM argv[]) {
  if (argc != 2) return enif_make_badarg(env);

  rcl_ret_t rc;
  int64_t sequence_number;

  rcl_action_client_t *action_client_p;
  if (!enif_get_resource(env, argv[0], rt_rcl_action_client_t, (void **)&action_client_p))
    return enif_make_badarg(env);
  if (!rcl_action_client_is_valid(action_client_p)) return raise(env, __FILE__, __LINE__);

  void **ros_request_message_pp;
  if (!enif_get_resource(env, argv[1], rt_ros_message, (void **)&ros_request_message_pp))
    return enif_make_badarg(env);

  rc = rcl_action_send_cancel_request(action_client_p, *ros_request_message_pp, &sequence_number);

  if (rc == RCL_RET_OK)
    return enif_make_tuple2(env, atom_ok, enif_make_int64(env, sequence_number));
  else if (rc == RCL_RET_INVALID_ARGUMENT)
    return enif_make_badarg(env);
  else
    return raise(env, __FILE__, __LINE__);
}

ERL_NIF_TERM nif_rcl_action_send_goal_request(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 2) return enif_make_badarg(env);

  rcl_ret_t rc;
  int64_t sequence_number;

  rcl_action_client_t *action_client_p;
  if (!enif_get_resource(env, argv[0], rt_rcl_action_client_t, (void **)&action_client_p))
    return enif_make_badarg(env);
  if (!rcl_action_client_is_valid(action_client_p)) return raise(env, __FILE__, __LINE__);

  void **ros_request_message_pp;
  if (!enif_get_resource(env, argv[1], rt_ros_message, (void **)&ros_request_message_pp))
    return enif_make_badarg(env);

  rc = rcl_action_send_goal_request(action_client_p, *ros_request_message_pp, &sequence_number);
  if (rc == RCL_RET_OK)
    return enif_make_tuple2(env, atom_ok, enif_make_int64(env, sequence_number));
  else if (rc == RCL_RET_INVALID_ARGUMENT)
    return enif_make_badarg(env);
  else
    return raise(env, __FILE__, __LINE__);
}

ERL_NIF_TERM nif_rcl_action_send_result_request(ErlNifEnv *env, int argc,
                                                const ERL_NIF_TERM argv[]) {
  if (argc != 2) return enif_make_badarg(env);

  rcl_ret_t rc;
  int64_t sequence_number;

  rcl_action_client_t *action_client_p;
  if (!enif_get_resource(env, argv[0], rt_rcl_action_client_t, (void **)&action_client_p))
    return enif_make_badarg(env);
  if (!rcl_action_client_is_valid(action_client_p)) return raise(env, __FILE__, __LINE__);

  void **ros_request_message_pp;
  if (!enif_get_resource(env, argv[1], rt_ros_message, (void **)&ros_request_message_pp))
    return enif_make_badarg(env);

  rc = rcl_action_send_result_request(action_client_p, *ros_request_message_pp, &sequence_number);
  if (rc == RCL_RET_OK)
    return enif_make_tuple2(env, atom_ok, enif_make_int64(env, sequence_number));
  else if (rc == RCL_RET_INVALID_ARGUMENT)
    return enif_make_badarg(env);
  else
    return raise(env, __FILE__, __LINE__);
}

static void new_cancel_response_callback(const void *user_data, size_t number_of_events) {
  callback_resource_t *callback_resource = (callback_resource_t *)user_data;
  if (callback_resource_should_drop(callback_resource)) return;

  ErlNifEnv *env = enif_alloc_env();
  enif_send(
      env, &callback_resource->pid, env,
      enif_make_tuple(env, 2, atom_new_cancel_response, enif_make_int(env, number_of_events)));
  enif_free_env(env);
}

static void new_feedback_message_callback(const void *user_data, size_t number_of_events) {
  callback_resource_t *callback_resource = (callback_resource_t *)user_data;
  if (callback_resource_should_drop(callback_resource)) return;

  ErlNifEnv *env = enif_alloc_env();
  enif_send(env, &callback_resource->pid, env,
            enif_make_tuple(env, 2, atom_new_feedback, enif_make_int(env, number_of_events)));
  enif_free_env(env);
}

static void new_goal_response_callback(const void *user_data, size_t number_of_events) {
  callback_resource_t *callback_resource = (callback_resource_t *)user_data;
  if (callback_resource_should_drop(callback_resource)) return;

  ErlNifEnv *env = enif_alloc_env();
  enif_send(env, &callback_resource->pid, env,
            enif_make_tuple(env, 2, atom_new_goal_response, enif_make_int(env, number_of_events)));
  enif_free_env(env);
}

static void new_result_response_callback(const void *user_data, size_t number_of_events) {
  callback_resource_t *callback_resource = (callback_resource_t *)user_data;
  if (callback_resource_should_drop(callback_resource)) return;

  ErlNifEnv *env = enif_alloc_env();
  enif_send(
      env, &callback_resource->pid, env,
      enif_make_tuple(env, 2, atom_new_result_response, enif_make_int(env, number_of_events)));
  enif_free_env(env);
}

static void new_status_message_callback(const void *user_data, size_t number_of_events) {
  callback_resource_t *callback_resource = (callback_resource_t *)user_data;
  if (callback_resource_should_drop(callback_resource)) return;

  ErlNifEnv *env = enif_alloc_env();
  enif_send(env, &callback_resource->pid, env,
            enif_make_tuple(env, 2, atom_new_status, enif_make_int(env, number_of_events)));
  enif_free_env(env);
}

extern ErlNifResourceType *rt_action_client_cancel_client_callback_resource;
extern ErlNifResourceType *rt_action_client_feedback_subscription_callback_resource;
extern ErlNifResourceType *rt_action_client_goal_client_callback_resource;
extern ErlNifResourceType *rt_action_client_result_client_callback_resource;
extern ErlNifResourceType *rt_action_client_status_subscription_callback_resource;

ERL_NIF_TERM nif_rcl_action_client_set_cancel_client_callback(ErlNifEnv *env, int argc,
                                                              const ERL_NIF_TERM argv[]) {
  if (argc != 1) return enif_make_badarg(env);

  rcl_action_client_t *action_client_p;
  if (!enif_get_resource(env, argv[0], rt_rcl_action_client_t, (void **)&action_client_p))
    return enif_make_badarg(env);
  if (!rcl_action_client_is_valid(action_client_p)) return raise(env, __FILE__, __LINE__);

  callback_resource_t *callback_resource = (callback_resource_t *)enif_alloc_resource(
      rt_action_client_cancel_client_callback_resource, sizeof(callback_resource_t));
  if (enif_self(env, &callback_resource->pid) == NULL) return raise(env, __FILE__, __LINE__);
  callback_resource->active         = 1;
  callback_resource->owner          = action_client_p;
  callback_resource->owner_is_valid = action_client_owner_is_valid;
  enif_keep_resource(callback_resource);

  rcl_ret_t rc;
  rc = rcl_action_client_set_cancel_client_callback(action_client_p, new_cancel_response_callback,
                                                    (const void *)callback_resource);
  if (rc != RCL_RET_OK) return raise(env, __FILE__, __LINE__);

  return enif_make_resource(env, callback_resource);
}

ERL_NIF_TERM nif_rcl_action_client_set_feedback_subscription_callback(ErlNifEnv *env, int argc,
                                                                      const ERL_NIF_TERM argv[]) {
  if (argc != 1) return enif_make_badarg(env);

  rcl_action_client_t *action_client_p;
  if (!enif_get_resource(env, argv[0], rt_rcl_action_client_t, (void **)&action_client_p))
    return enif_make_badarg(env);
  if (!rcl_action_client_is_valid(action_client_p)) return raise(env, __FILE__, __LINE__);

  callback_resource_t *callback_resource = (callback_resource_t *)enif_alloc_resource(
      rt_action_client_feedback_subscription_callback_resource, sizeof(callback_resource_t));
  if (enif_self(env, &callback_resource->pid) == NULL) return raise(env, __FILE__, __LINE__);
  callback_resource->active         = 1;
  callback_resource->owner          = action_client_p;
  callback_resource->owner_is_valid = action_client_owner_is_valid;
  enif_keep_resource(callback_resource);

  rcl_ret_t rc;
  rc = rcl_action_client_set_feedback_subscription_callback(
      action_client_p, new_feedback_message_callback, (const void *)callback_resource);
  if (rc != RCL_RET_OK) return raise(env, __FILE__, __LINE__);

  return enif_make_resource(env, callback_resource);
}

ERL_NIF_TERM nif_rcl_action_client_set_goal_client_callback(ErlNifEnv *env, int argc,
                                                            const ERL_NIF_TERM argv[]) {
  if (argc != 1) return enif_make_badarg(env);

  rcl_action_client_t *action_client_p;
  if (!enif_get_resource(env, argv[0], rt_rcl_action_client_t, (void **)&action_client_p))
    return enif_make_badarg(env);
  if (!rcl_action_client_is_valid(action_client_p)) return raise(env, __FILE__, __LINE__);

  callback_resource_t *callback_resource = (callback_resource_t *)enif_alloc_resource(
      rt_action_client_goal_client_callback_resource, sizeof(callback_resource_t));
  if (enif_self(env, &callback_resource->pid) == NULL) return raise(env, __FILE__, __LINE__);
  callback_resource->active         = 1;
  callback_resource->owner          = action_client_p;
  callback_resource->owner_is_valid = action_client_owner_is_valid;
  enif_keep_resource(callback_resource);

  rcl_ret_t rc;
  rc = rcl_action_client_set_goal_client_callback(action_client_p, new_goal_response_callback,
                                                  (const void *)callback_resource);
  if (rc != RCL_RET_OK) return raise(env, __FILE__, __LINE__);

  return enif_make_resource(env, callback_resource);
}

ERL_NIF_TERM nif_rcl_action_client_set_result_client_callback(ErlNifEnv *env, int argc,
                                                              const ERL_NIF_TERM argv[]) {
  if (argc != 1) return enif_make_badarg(env);

  rcl_action_client_t *action_client_p;
  if (!enif_get_resource(env, argv[0], rt_rcl_action_client_t, (void **)&action_client_p))
    return enif_make_badarg(env);
  if (!rcl_action_client_is_valid(action_client_p)) return raise(env, __FILE__, __LINE__);

  callback_resource_t *callback_resource = (callback_resource_t *)enif_alloc_resource(
      rt_action_client_result_client_callback_resource, sizeof(callback_resource_t));
  if (enif_self(env, &callback_resource->pid) == NULL) return raise(env, __FILE__, __LINE__);
  callback_resource->active         = 1;
  callback_resource->owner          = action_client_p;
  callback_resource->owner_is_valid = action_client_owner_is_valid;
  enif_keep_resource(callback_resource);

  rcl_ret_t rc;
  rc = rcl_action_client_set_result_client_callback(action_client_p, new_result_response_callback,
                                                    (const void *)callback_resource);
  if (rc != RCL_RET_OK) return raise(env, __FILE__, __LINE__);

  return enif_make_resource(env, callback_resource);
}

ERL_NIF_TERM nif_rcl_action_client_set_status_subscription_callback(ErlNifEnv *env, int argc,
                                                                    const ERL_NIF_TERM argv[]) {
  if (argc != 1) return enif_make_badarg(env);

  rcl_action_client_t *action_client_p;
  if (!enif_get_resource(env, argv[0], rt_rcl_action_client_t, (void **)&action_client_p))
    return enif_make_badarg(env);
  if (!rcl_action_client_is_valid(action_client_p)) return raise(env, __FILE__, __LINE__);

  callback_resource_t *callback_resource = (callback_resource_t *)enif_alloc_resource(
      rt_action_client_status_subscription_callback_resource, sizeof(callback_resource_t));
  if (enif_self(env, &callback_resource->pid) == NULL) return raise(env, __FILE__, __LINE__);
  callback_resource->active         = 1;
  callback_resource->owner          = action_client_p;
  callback_resource->owner_is_valid = action_client_owner_is_valid;
  enif_keep_resource(callback_resource);

  rcl_ret_t rc;
  rc = rcl_action_client_set_status_subscription_callback(
      action_client_p, new_status_message_callback, (const void *)callback_resource);
  if (rc != RCL_RET_OK) return raise(env, __FILE__, __LINE__);

  return enif_make_resource(env, callback_resource);
}

ERL_NIF_TERM nif_rcl_action_client_clear_cancel_client_callback(ErlNifEnv *env, int argc,
                                                                const ERL_NIF_TERM argv[]) {
  if (argc != 2) return enif_make_badarg(env);

  rcl_action_client_t *action_client_p;
  if (!enif_get_resource(env, argv[0], rt_rcl_action_client_t, (void **)&action_client_p))
    return enif_make_badarg(env);
  if (!rcl_action_client_is_valid(action_client_p)) return raise(env, __FILE__, __LINE__);

  callback_resource_t *callback_resource = NULL;
  if (!enif_get_resource(env, argv[1], rt_action_client_cancel_client_callback_resource,
                         (void **)&callback_resource))
    return enif_make_badarg(env);

  callback_resource->active = 0;

  rcl_ret_t rc;
  rc = rcl_action_client_set_cancel_client_callback(action_client_p, NULL, NULL);
  if (rc != RCL_RET_OK) return raise(env, __FILE__, __LINE__);

  enif_release_resource(callback_resource);

  return atom_ok;
}

ERL_NIF_TERM nif_rcl_action_client_clear_feedback_subscription_callback(ErlNifEnv *env, int argc,
                                                                        const ERL_NIF_TERM argv[]) {
  if (argc != 2) return enif_make_badarg(env);

  rcl_action_client_t *action_client_p;
  if (!enif_get_resource(env, argv[0], rt_rcl_action_client_t, (void **)&action_client_p))
    return enif_make_badarg(env);
  if (!rcl_action_client_is_valid(action_client_p)) return raise(env, __FILE__, __LINE__);

  callback_resource_t *callback_resource = NULL;
  if (!enif_get_resource(env, argv[1], rt_action_client_feedback_subscription_callback_resource,
                         (void **)&callback_resource))
    return enif_make_badarg(env);

  callback_resource->active = 0;

  rcl_ret_t rc;
  rc = rcl_action_client_set_feedback_subscription_callback(action_client_p, NULL, NULL);
  if (rc != RCL_RET_OK) return raise(env, __FILE__, __LINE__);

  enif_release_resource(callback_resource);

  return atom_ok;
}

ERL_NIF_TERM nif_rcl_action_client_clear_goal_client_callback(ErlNifEnv *env, int argc,
                                                              const ERL_NIF_TERM argv[]) {
  if (argc != 2) return enif_make_badarg(env);

  rcl_action_client_t *action_client_p;
  if (!enif_get_resource(env, argv[0], rt_rcl_action_client_t, (void **)&action_client_p))
    return enif_make_badarg(env);
  if (!rcl_action_client_is_valid(action_client_p)) return raise(env, __FILE__, __LINE__);

  callback_resource_t *callback_resource = NULL;
  if (!enif_get_resource(env, argv[1], rt_action_client_goal_client_callback_resource,
                         (void **)&callback_resource))
    return enif_make_badarg(env);

  callback_resource->active = 0;

  rcl_ret_t rc;
  rc = rcl_action_client_set_goal_client_callback(action_client_p, NULL, NULL);
  if (rc != RCL_RET_OK) return raise(env, __FILE__, __LINE__);

  enif_release_resource(callback_resource);

  return atom_ok;
}

ERL_NIF_TERM nif_rcl_action_client_clear_result_client_callback(ErlNifEnv *env, int argc,
                                                                const ERL_NIF_TERM argv[]) {
  if (argc != 2) return enif_make_badarg(env);

  rcl_action_client_t *action_client_p;
  if (!enif_get_resource(env, argv[0], rt_rcl_action_client_t, (void **)&action_client_p))
    return enif_make_badarg(env);
  if (!rcl_action_client_is_valid(action_client_p)) return raise(env, __FILE__, __LINE__);

  callback_resource_t *callback_resource = NULL;
  if (!enif_get_resource(env, argv[1], rt_action_client_result_client_callback_resource,
                         (void **)&callback_resource))
    return enif_make_badarg(env);

  callback_resource->active = 0;

  rcl_ret_t rc;
  rc = rcl_action_client_set_result_client_callback(action_client_p, NULL, NULL);
  if (rc != RCL_RET_OK) return raise(env, __FILE__, __LINE__);

  enif_release_resource(callback_resource);

  return atom_ok;
}

ERL_NIF_TERM nif_rcl_action_client_clear_status_subscription_callback(ErlNifEnv *env, int argc,
                                                                      const ERL_NIF_TERM argv[]) {
  if (argc != 2) return enif_make_badarg(env);

  rcl_action_client_t *action_client_p;
  if (!enif_get_resource(env, argv[0], rt_rcl_action_client_t, (void **)&action_client_p))
    return enif_make_badarg(env);
  if (!rcl_action_client_is_valid(action_client_p)) return raise(env, __FILE__, __LINE__);

  callback_resource_t *callback_resource = NULL;
  if (!enif_get_resource(env, argv[1], rt_action_client_status_subscription_callback_resource,
                         (void **)&callback_resource))
    return enif_make_badarg(env);

  callback_resource->active = 0;

  rcl_ret_t rc;
  rc = rcl_action_client_set_status_subscription_callback(action_client_p, NULL, NULL);
  if (rc != RCL_RET_OK) return raise(env, __FILE__, __LINE__);

  enif_release_resource(callback_resource);

  return atom_ok;
}

ERL_NIF_TERM nif_rcl_action_server_is_available(ErlNifEnv *env, int argc,
                                                const ERL_NIF_TERM argv[]) {
  if (argc != 2) return enif_make_badarg(env);

  rcl_node_t *node_p;
  if (!enif_get_resource(env, argv[0], rt_rcl_node_t, (void **)&node_p))
    return enif_make_badarg(env);
  if (!rcl_node_is_valid(node_p)) return raise(env, __FILE__, __LINE__);

  rcl_action_client_t *action_client_p;
  if (!enif_get_resource(env, argv[1], rt_rcl_action_client_t, (void **)&action_client_p))
    return enif_make_badarg(env);
  if (!rcl_action_client_is_valid(action_client_p)) return raise(env, __FILE__, __LINE__);

  rcl_ret_t rc;
  bool is_available;
  rc = rcl_action_server_is_available(node_p, action_client_p, &is_available);
  if (rc != RCL_RET_OK) return raise_with_safe_message(env, __FILE__, __LINE__, rc);

  if (is_available)
    return atom_true;
  else
    return atom_false;
}
