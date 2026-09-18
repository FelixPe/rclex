#include "rmw_serialization.h"
#include "allocator.h"
#include "resource_types.h"
#include "terms.h"
#include <erl_nif.h>
#include <rmw/rmw.h>
#include <rmw/serialized_message.h>
#include <rmw/types.h>
#include <rosidl_runtime_c/message_type_support_struct.h>
#include <stddef.h>

// Generic (type-agnostic) CDR (de)serialization, exposed so benchmarks can
// measure rclex message handling with the same CDR step that rclpy bundles
// into serialize_message/deserialize_message, for an apples-to-apples
// comparison. Not used by the normal publish/subscribe path: rcl_publish
// and rcl_take already do this internally via rmw.

ERL_NIF_TERM nif_rmw_serialize(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 2) return enif_make_badarg(env);

  rosidl_message_type_support_t *ts_p;
  if (!enif_get_resource(env, argv[0], rt_rosidl_message_type_support_t, (void **)&ts_p))
    return enif_make_badarg(env);

  void **ros_message_pp;
  if (!enif_get_resource(env, argv[1], rt_ros_message, (void **)&ros_message_pp))
    return enif_make_badarg(env);

  rmw_serialized_message_t serialized_msg = rmw_get_zero_initialized_serialized_message();
  rcutils_allocator_t allocator            = get_nif_allocator();
  if (rmw_serialized_message_init(&serialized_msg, 0u, &allocator) != RCUTILS_RET_OK)
    return raise_with_message(env, __FILE__, __LINE__, "failed to initialize serialized message");

  rmw_ret_t rc = rmw_serialize(*ros_message_pp, ts_p, &serialized_msg);
  if (rc != RMW_RET_OK) {
    rmw_serialized_message_fini(&serialized_msg);
    return raise_with_message(env, __FILE__, __LINE__, "rmw_serialize failed");
  }

  ERL_NIF_TERM term = enif_make_binary_wrapper(env, (const char *)serialized_msg.buffer, serialized_msg.buffer_length);
  rmw_serialized_message_fini(&serialized_msg);
  if (enif_is_exception(env, term)) return term;

  return term;
}

ERL_NIF_TERM nif_rmw_deserialize(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 3) return enif_make_badarg(env);

  ErlNifBinary payload;
  if (!enif_inspect_binary(env, argv[0], &payload)) return enif_make_badarg(env);

  rosidl_message_type_support_t *ts_p;
  if (!enif_get_resource(env, argv[1], rt_rosidl_message_type_support_t, (void **)&ts_p))
    return enif_make_badarg(env);

  void **ros_message_pp;
  if (!enif_get_resource(env, argv[2], rt_ros_message, (void **)&ros_message_pp))
    return enif_make_badarg(env);

  rmw_serialized_message_t serialized_msg = rmw_get_zero_initialized_serialized_message();
  serialized_msg.buffer_capacity           = payload.size;
  serialized_msg.buffer_length             = payload.size;
  serialized_msg.buffer                    = (uint8_t *)payload.data;
  serialized_msg.allocator                 = get_nif_allocator();

  rmw_ret_t rc = rmw_deserialize(&serialized_msg, ts_p, *ros_message_pp);
  if (rc != RMW_RET_OK) return raise_with_message(env, __FILE__, __LINE__, "rmw_deserialize failed");

  return atom_ok;
}
