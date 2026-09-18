// PROTOTYPE: struct-in-NIF for sensor_msgs/PointCloud only.
//
// Purpose: measure whether decoding an Elixir struct (a map) directly in the
// NIF - instead of struct -> to_tuple/1 -> tuple -> NIF, and NIF -> tuple ->
// to_struct/1 -> struct on the way back - is actually faster, before
// investing in generalizing this into the msg_c.ex/msg_ex.ex code generator.
//
// GENERALIZATION NOTES (read before turning this into a generator):
//   1. Field-name atoms (atom_header, atom_x, ...) are hand-declared and
//      initialized once in make_prototype_struct_atoms/1. A generator would
//      need a global, deduplicated atom table keyed by field name (many
//      names repeat across message types - x/y/z/name/data/frame_id/...),
//      populated once at NIF load time, analogous to the existing
//      atom_nan/atom_infinity/atom_neg_infinity pattern in terms.c/h.
//   2. Struct-tag atoms (atom_module_point_cloud, ...) identify the
//      `__struct__` key of each Elixir struct/map. A generator would need
//      one such atom per generated message type (there is already a
//      precedent: type_support resources cache one value per type at
//      load time).
//   3. Nested messages (Header, Time) and sequences of nested messages
//      (points :: list(Point32), channels :: list(ChannelFloat32)) are
//      hand-unrolled here. A generator would need to recurse using the same
//      per-type field/atom metadata it already has for tuple-based codegen
//      (see msg_c.ex `get_fields/2`), just swapping enif_get_tuple/
//      enif_make_tuple for enif_get_map_value/enif_make_map_put.
//   4. NaN/Infinity handling for float32 fields is preserved as-is (copied
//      from the generated tuple-based nif_sensor_msgs_msg_point_cloud_set/
//      get in point_cloud.c) - this part does not change between tuple and
//      map representations.
#include "prototype_point_cloud_struct.h"
#include "macros.h"
#include "resource_types.h"
#include "terms.h"

#include <erl_nif.h>

#include <rosidl_runtime_c/primitives_sequence_functions.h>
#include <rosidl_runtime_c/string.h>
#include <rosidl_runtime_c/string_functions.h>

#include <builtin_interfaces/msg/detail/time__struct.h>
#include <geometry_msgs/msg/detail/point32__functions.h>
#include <geometry_msgs/msg/detail/point32__struct.h>
#include <sensor_msgs/msg/detail/channel_float32__functions.h>
#include <sensor_msgs/msg/detail/channel_float32__struct.h>
#include <sensor_msgs/msg/detail/point_cloud__struct.h>
#include <std_msgs/msg/detail/header__struct.h>

#include <math.h>
#include <stddef.h>

// --- field-name atoms (see generalization note 1) ---
static ERL_NIF_TERM atom_struct_key;
static ERL_NIF_TERM atom_header;
static ERL_NIF_TERM atom_points;
static ERL_NIF_TERM atom_channels;
static ERL_NIF_TERM atom_frame_id;
static ERL_NIF_TERM atom_stamp;
static ERL_NIF_TERM atom_sec;
static ERL_NIF_TERM atom_nanosec;
static ERL_NIF_TERM atom_x;
static ERL_NIF_TERM atom_y;
static ERL_NIF_TERM atom_z;
static ERL_NIF_TERM atom_name;
static ERL_NIF_TERM atom_values;

// --- struct-tag atoms (see generalization note 2) ---
static ERL_NIF_TERM atom_module_point_cloud;
static ERL_NIF_TERM atom_module_header;
static ERL_NIF_TERM atom_module_time;
static ERL_NIF_TERM atom_module_point32;
static ERL_NIF_TERM atom_module_channel_float32;

void make_prototype_point_cloud_struct_atoms(ErlNifEnv *env) {
  atom_struct_key = enif_make_atom(env, "__struct__");
  atom_header     = enif_make_atom(env, "header");
  atom_points     = enif_make_atom(env, "points");
  atom_channels   = enif_make_atom(env, "channels");
  atom_frame_id   = enif_make_atom(env, "frame_id");
  atom_stamp      = enif_make_atom(env, "stamp");
  atom_sec        = enif_make_atom(env, "sec");
  atom_nanosec    = enif_make_atom(env, "nanosec");
  atom_x          = enif_make_atom(env, "x");
  atom_y          = enif_make_atom(env, "y");
  atom_z          = enif_make_atom(env, "z");
  atom_name       = enif_make_atom(env, "name");
  atom_values     = enif_make_atom(env, "values");

  atom_module_point_cloud     = enif_make_atom(env, "Elixir.Rclex.Pkgs.SensorMsgs.Msg.PointCloud");
  atom_module_header          = enif_make_atom(env, "Elixir.Rclex.Pkgs.StdMsgs.Msg.Header");
  atom_module_time            = enif_make_atom(env, "Elixir.Rclex.Pkgs.BuiltinInterfaces.Msg.Time");
  atom_module_point32         = enif_make_atom(env, "Elixir.Rclex.Pkgs.GeometryMsgs.Msg.Point32");
  atom_module_channel_float32 = enif_make_atom(env, "Elixir.Rclex.Pkgs.SensorMsgs.Msg.ChannelFloat32");
}

static int get_map_field(ErlNifEnv *env, ERL_NIF_TERM map, ERL_NIF_TERM key, ERL_NIF_TERM *out) {
  return enif_get_map_value(env, map, key, out);
}

static ERL_NIF_TERM get_float32_term(ErlNifEnv *env, double *out, ERL_NIF_TERM term) {
  if (enif_is_identical(term, atom_nan)) {
    *out = NAN;
  } else if (enif_is_identical(term, atom_infinity)) {
    *out = INFINITY;
  } else if (enif_is_identical(term, atom_neg_infinity)) {
    *out = -INFINITY;
  } else if (!enif_get_double(env, term, out)) {
    return enif_make_badarg(env);
  }
  return atom_ok;
}

static ERL_NIF_TERM make_float32_term(ErlNifEnv *env, float value) {
  if (isnan(value)) return atom_nan;
  if (isinf(value) > 0) return atom_infinity;
  if (isinf(value) < 0) return atom_neg_infinity;
  return enif_make_double(env, value);
}

ERL_NIF_TERM nif_sensor_msgs_msg_point_cloud_set_struct(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 2) return enif_make_badarg(env);

  void **ros_message_pp;
  if (!enif_get_resource(env, argv[0], rt_ros_message, (void **)&ros_message_pp))
    return enif_make_badarg(env);
  sensor_msgs__msg__PointCloud *message_p = (sensor_msgs__msg__PointCloud *)*ros_message_pp;

  ERL_NIF_TERM struct_term = argv[1];

  ERL_NIF_TERM header_term;
  if (!get_map_field(env, struct_term, atom_header, &header_term)) return enif_make_badarg(env);

  ERL_NIF_TERM stamp_term;
  if (!get_map_field(env, header_term, atom_stamp, &stamp_term)) return enif_make_badarg(env);

  int stamp_sec;
  ERL_NIF_TERM sec_term;
  if (!get_map_field(env, stamp_term, atom_sec, &sec_term)) return enif_make_badarg(env);
  if (!enif_get_int(env, sec_term, &stamp_sec)) return enif_make_badarg(env);
  message_p->header.stamp.sec = stamp_sec;

  unsigned int stamp_nanosec;
  ERL_NIF_TERM nanosec_term;
  if (!get_map_field(env, stamp_term, atom_nanosec, &nanosec_term)) return enif_make_badarg(env);
  if (!enif_get_uint(env, nanosec_term, &stamp_nanosec)) return enif_make_badarg(env);
  message_p->header.stamp.nanosec = stamp_nanosec;

  ERL_NIF_TERM frame_id_term;
  if (!get_map_field(env, header_term, atom_frame_id, &frame_id_term)) return enif_make_badarg(env);
  ErlNifBinary frame_id_binary;
  if (!enif_inspect_binary(env, frame_id_term, &frame_id_binary)) return enif_make_badarg(env);
  if (!rosidl_runtime_c__String__assignn(&(message_p->header.frame_id), (const char *)frame_id_binary.data, frame_id_binary.size))
    return raise(env, __FILE__, __LINE__);

  ERL_NIF_TERM points_term;
  if (!get_map_field(env, struct_term, atom_points, &points_term)) return enif_make_badarg(env);

  unsigned int points_length;
  if (!enif_get_list_length(env, points_term, &points_length)) return enif_make_badarg(env);

  geometry_msgs__msg__Point32__Sequence *points = geometry_msgs__msg__Point32__Sequence__create(points_length);
  if (points == NULL) return raise(env, __FILE__, __LINE__);
  message_p->points = *points;

  ERL_NIF_TERM points_left = points_term, points_head, points_tail;
  for (unsigned int i = 0; i < points_length; ++i, points_left = points_tail) {
    if (!enif_get_list_cell(env, points_left, &points_head, &points_tail)) return enif_make_badarg(env);

    ERL_NIF_TERM x_term, y_term, z_term;
    if (!get_map_field(env, points_head, atom_x, &x_term)) return enif_make_badarg(env);
    if (!get_map_field(env, points_head, atom_y, &y_term)) return enif_make_badarg(env);
    if (!get_map_field(env, points_head, atom_z, &z_term)) return enif_make_badarg(env);

    double x, y, z;
    ERL_NIF_TERM err;
    if (enif_is_exception(env, err = get_float32_term(env, &x, x_term))) return err;
    if (enif_is_exception(env, err = get_float32_term(env, &y, y_term))) return err;
    if (enif_is_exception(env, err = get_float32_term(env, &z, z_term))) return err;

    message_p->points.data[i].x = (float)x;
    message_p->points.data[i].y = (float)y;
    message_p->points.data[i].z = (float)z;
  }

  ERL_NIF_TERM channels_term;
  if (!get_map_field(env, struct_term, atom_channels, &channels_term)) return enif_make_badarg(env);

  unsigned int channels_length;
  if (!enif_get_list_length(env, channels_term, &channels_length)) return enif_make_badarg(env);

  sensor_msgs__msg__ChannelFloat32__Sequence *channels = sensor_msgs__msg__ChannelFloat32__Sequence__create(channels_length);
  if (channels == NULL) return raise(env, __FILE__, __LINE__);
  message_p->channels = *channels;

  ERL_NIF_TERM channels_left = channels_term, channels_head, channels_tail;
  for (unsigned int i = 0; i < channels_length; ++i, channels_left = channels_tail) {
    if (!enif_get_list_cell(env, channels_left, &channels_head, &channels_tail)) return enif_make_badarg(env);

    ERL_NIF_TERM name_term;
    if (!get_map_field(env, channels_head, atom_name, &name_term)) return enif_make_badarg(env);
    ErlNifBinary name_binary;
    if (!enif_inspect_binary(env, name_term, &name_binary)) return enif_make_badarg(env);
    if (!rosidl_runtime_c__String__assignn(&(message_p->channels.data[i].name), (const char *)name_binary.data, name_binary.size))
      return raise(env, __FILE__, __LINE__);

    ERL_NIF_TERM values_term;
    if (!get_map_field(env, channels_head, atom_values, &values_term)) return enif_make_badarg(env);

    unsigned int values_length;
    if (!enif_get_list_length(env, values_term, &values_length)) return enif_make_badarg(env);

    rosidl_runtime_c__float32__Sequence values;
    if (!rosidl_runtime_c__float32__Sequence__init(&values, values_length)) return enif_make_badarg(env);
    message_p->channels.data[i].values = values;

    ERL_NIF_TERM values_left = values_term, values_head, values_tail;
    for (unsigned int j = 0; j < values_length; ++j, values_left = values_tail) {
      if (!enif_get_list_cell(env, values_left, &values_head, &values_tail)) return enif_make_badarg(env);

      double value;
      ERL_NIF_TERM err = get_float32_term(env, &value, values_head);
      if (enif_is_exception(env, err)) return err;
      message_p->channels.data[i].values.data[j] = (float)value;
    }
  }

  return atom_ok;
}

ERL_NIF_TERM nif_sensor_msgs_msg_point_cloud_get_struct(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 1) return enif_make_badarg(env);

  void **ros_message_pp;
  if (!enif_get_resource(env, argv[0], rt_ros_message, (void **)&ros_message_pp))
    return enif_make_badarg(env);
  sensor_msgs__msg__PointCloud *message_p = (sensor_msgs__msg__PointCloud *)*ros_message_pp;

  if (message_p->points.size > message_p->points.capacity ||
      message_p->channels.size > message_p->channels.capacity)
    return raise_with_message(env, __FILE__, __LINE__, "invalid sequence size/capacity");

  // NOTE (generalization note 5): build each map in one shot with
  // enif_make_map_from_arrays instead of chaining enif_make_map_put calls -
  // each enif_make_map_put on a small (flatmap) map reallocates/copies the
  // whole backing array, so N chained puts cost O(N^2) rather than O(N).
  // A generator emitting one-put-per-field code (the "obvious" translation
  // of the tuple codegen) would be a lot slower than this.
  ERL_NIF_TERM points_list = enif_make_list(env, 0);
  for (size_t i = message_p->points.size; i > 0; --i) {
    size_t idx = i - 1;
    ERL_NIF_TERM keys[4]   = {atom_struct_key, atom_x, atom_y, atom_z};
    ERL_NIF_TERM values[4] = {
        atom_module_point32,
        make_float32_term(env, message_p->points.data[idx].x),
        make_float32_term(env, message_p->points.data[idx].y),
        make_float32_term(env, message_p->points.data[idx].z),
    };
    ERL_NIF_TERM point_map;
    if (!enif_make_map_from_arrays(env, keys, values, 4, &point_map))
      return raise(env, __FILE__, __LINE__);
    points_list = enif_make_list_cell(env, point_map, points_list);
  }

  ERL_NIF_TERM channels_list = enif_make_list(env, 0);
  for (size_t i = message_p->channels.size; i > 0; --i) {
    size_t idx = i - 1;
    sensor_msgs__msg__ChannelFloat32 *channel = &message_p->channels.data[idx];

    if (channel->values.size > channel->values.capacity)
      return raise_with_message(env, __FILE__, __LINE__, "invalid sequence size/capacity");

    ERL_NIF_TERM values_list = enif_make_list(env, 0);
    for (size_t j = channel->values.size; j > 0; --j) {
      values_list = enif_make_list_cell(env, make_float32_term(env, channel->values.data[j - 1]), values_list);
    }

    ERL_NIF_TERM name_term = enif_make_binary_wrapper(env, channel->name.data, channel->name.size);
    if (enif_is_exception(env, name_term)) return name_term;

    ERL_NIF_TERM keys[3]   = {atom_struct_key, atom_name, atom_values};
    ERL_NIF_TERM values[3] = {atom_module_channel_float32, name_term, values_list};
    ERL_NIF_TERM channel_map;
    if (!enif_make_map_from_arrays(env, keys, values, 3, &channel_map))
      return raise(env, __FILE__, __LINE__);
    channels_list = enif_make_list_cell(env, channel_map, channels_list);
  }

  ERL_NIF_TERM frame_id_term = enif_make_binary_wrapper(env, message_p->header.frame_id.data, message_p->header.frame_id.size);
  if (enif_is_exception(env, frame_id_term)) return frame_id_term;

  ERL_NIF_TERM stamp_keys[3]   = {atom_struct_key, atom_sec, atom_nanosec};
  ERL_NIF_TERM stamp_values[3] = {
      atom_module_time,
      enif_make_int(env, message_p->header.stamp.sec),
      enif_make_uint(env, message_p->header.stamp.nanosec),
  };
  ERL_NIF_TERM stamp_map;
  if (!enif_make_map_from_arrays(env, stamp_keys, stamp_values, 3, &stamp_map))
    return raise(env, __FILE__, __LINE__);

  ERL_NIF_TERM header_keys[3]   = {atom_struct_key, atom_stamp, atom_frame_id};
  ERL_NIF_TERM header_values[3] = {atom_module_header, stamp_map, frame_id_term};
  ERL_NIF_TERM header_map;
  if (!enif_make_map_from_arrays(env, header_keys, header_values, 3, &header_map))
    return raise(env, __FILE__, __LINE__);

  ERL_NIF_TERM result_keys[4]   = {atom_struct_key, atom_header, atom_points, atom_channels};
  ERL_NIF_TERM result_values[4] = {atom_module_point_cloud, header_map, points_list, channels_list};
  ERL_NIF_TERM result_map;
  if (!enif_make_map_from_arrays(env, result_keys, result_values, 4, &result_map))
    return raise(env, __FILE__, __LINE__);

  return result_map;
}

