#include "tf2_buffer.h"

#include <algorithm>
#include <cstring>
#include <initializer_list>
#include <memory>
#include <mutex>
#include <new>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

#include <tf2/buffer_core.hpp>
#include <tf2_geometry_msgs/tf2_geometry_msgs.hpp>
#include <yaml-cpp/yaml.h>

namespace {

ErlNifResourceType *buffer_type;

struct BufferResource {
  std::mutex mutex;
  std::unique_ptr<tf2::BufferCore> buffer;

  explicit BufferResource(std::unique_ptr<tf2::BufferCore> value) : buffer(std::move(value)) {}
};

ERL_NIF_TERM atom(ErlNifEnv *env, const char *name) { return enif_make_atom(env, name); }

ERL_NIF_TERM binary(ErlNifEnv *env, const std::string &value) {
  ERL_NIF_TERM result;
  auto *data = enif_make_new_binary(env, value.size(), &result);
  if (!data) throw std::bad_alloc();
  std::memcpy(data, value.data(), value.size());
  return result;
}

ERL_NIF_TERM ok(ErlNifEnv *env, ERL_NIF_TERM value) {
  return enif_make_tuple2(env, atom(env, "ok"), value);
}

ERL_NIF_TERM error(ErlNifEnv *env, const char *kind, const std::string &message) {
  return enif_make_tuple2(env, atom(env, "error"),
                          enif_make_tuple2(env, atom(env, kind), binary(env, message)));
}

ERL_NIF_TERM map(ErlNifEnv *env,
                 std::initializer_list<std::pair<const char *, ERL_NIF_TERM>> fields) {
  auto result = enif_make_new_map(env);
  for (const auto &field : fields) {
    if (!enif_make_map_put(env, result, atom(env, field.first), field.second, &result)) {
      throw std::bad_alloc();
    }
  }
  return result;
}

std::string string(ErlNifEnv *env, ERL_NIF_TERM term) {
  ErlNifBinary value;
  if (!enif_inspect_binary(env, term, &value)) throw std::invalid_argument("expected a binary");
  return std::string(reinterpret_cast<const char *>(value.data), value.size);
}

ErlNifSInt64 integer(ErlNifEnv *env, ERL_NIF_TERM term) {
  ErlNifSInt64 value;
  if (!enif_get_int64(env, term, &value)) throw std::invalid_argument("expected int64 nanoseconds");
  return value;
}

double number(ErlNifEnv *env, ERL_NIF_TERM term) {
  double value;
  if (enif_get_double(env, term, &value)) return value;
  return static_cast<double>(integer(env, term));
}

const ERL_NIF_TERM *tuple(ErlNifEnv *env, ERL_NIF_TERM term, int size) {
  int arity;
  const ERL_NIF_TERM *values;
  if (!enif_get_tuple(env, term, &arity, &values) || arity != size) {
    throw std::invalid_argument("invalid transform tuple");
  }
  return values;
}

tf2::TimePoint time_point(ErlNifEnv *env, ERL_NIF_TERM term) {
  return tf2::TimePoint(tf2::Duration(integer(env, term)));
}

ERL_NIF_TERM stamped_term(ErlNifEnv *env, const geometry_msgs::msg::TransformStamped &value) {
  const auto &translation = value.transform.translation;
  const auto &rotation    = value.transform.rotation;
  auto stamp              = map(env, {{"sec", enif_make_int(env, value.header.stamp.sec)},
                                      {"nanosec", enif_make_uint(env, value.header.stamp.nanosec)}});
  auto header = map(env, {{"frame_id", binary(env, value.header.frame_id)}, {"stamp", stamp}});
  auto translation_term = map(env, {{"x", enif_make_double(env, translation.x)},
                                    {"y", enif_make_double(env, translation.y)},
                                    {"z", enif_make_double(env, translation.z)}});
  auto rotation_term    = map(env, {{"x", enif_make_double(env, rotation.x)},
                                    {"y", enif_make_double(env, rotation.y)},
                                    {"z", enif_make_double(env, rotation.z)},
                                    {"w", enif_make_double(env, rotation.w)}});
  auto transform = map(env, {{"translation", translation_term}, {"rotation", rotation_term}});
  return map(env, {{"header", header},
                   {"child_frame_id", binary(env, value.child_frame_id)},
                   {"transform", transform}});
}

template <typename Function> ERL_NIF_TERM protect(ErlNifEnv *env, Function function) {
  try {
    return function();
  } catch (const tf2::LookupException &exception) {
    return error(env, "lookup", exception.what());
  } catch (const tf2::ConnectivityException &exception) {
    return error(env, "connectivity", exception.what());
#ifndef ROS_DISTRO_humble
  } catch (const tf2::BackwardExtrapolationException &exception) {
    return error(env, "extrapolation_past", exception.what());
  } catch (const tf2::ForwardExtrapolationException &exception) {
    return error(env, "extrapolation_future", exception.what());
#endif
  } catch (const tf2::ExtrapolationException &exception) {
    return error(env, "extrapolation", exception.what());
  } catch (const tf2::InvalidArgumentException &exception) {
    return error(env, "invalid_argument", exception.what());
  } catch (const std::invalid_argument &exception) {
    return error(env, "invalid_argument", exception.what());
  } catch (const std::exception &exception) {
    return error(env, "native_error", exception.what());
  } catch (...) {
    return error(env, "native_error", "unknown C++ exception");
  }
}

template <typename Function>
ERL_NIF_TERM with_buffer(ErlNifEnv *env, ERL_NIF_TERM term, Function function) {
  return protect(env, [&]() {
    BufferResource *resource;
    if (!enif_get_resource(env, term, buffer_type, reinterpret_cast<void **>(&resource))) {
      return enif_make_badarg(env);
    }
    std::lock_guard<std::mutex> lock(resource->mutex);
    if (!resource->buffer) return error(env, "buffer_not_found", "buffer has been destroyed");
    return function(*resource->buffer);
  });
}

void destroy_buffer(ErlNifEnv *, void *resource) {
  static_cast<BufferResource *>(resource)->~BufferResource();
}

ERL_NIF_TERM field(ErlNifEnv *env, ERL_NIF_TERM value, const char *name) {
  ERL_NIF_TERM result;
  if (!enif_get_map_value(env, value, atom(env, name), &result)) {
    throw std::invalid_argument(std::string("missing message field: ") + name);
  }
  return result;
}

template <typename Vector> Vector decode_xyz(ErlNifEnv *env, ERL_NIF_TERM value) {
  Vector result;
  result.x = number(env, field(env, value, "x"));
  result.y = number(env, field(env, value, "y"));
  result.z = number(env, field(env, value, "z"));
  return result;
}

geometry_msgs::msg::Quaternion decode_rotation(ErlNifEnv *env, ERL_NIF_TERM value) {
  auto result = decode_xyz<geometry_msgs::msg::Quaternion>(env, value);
  result.w    = number(env, field(env, value, "w"));
  return result;
}

template <typename Vector> ERL_NIF_TERM xyz_term(ErlNifEnv *env, const Vector &value) {
  return map(env, {{"x", enif_make_double(env, value.x)},
                   {"y", enif_make_double(env, value.y)},
                   {"z", enif_make_double(env, value.z)}});
}

ERL_NIF_TERM rotation_term(ErlNifEnv *env, const geometry_msgs::msg::Quaternion &value) {
  return map(env, {{"x", enif_make_double(env, value.x)},
                   {"y", enif_make_double(env, value.y)},
                   {"z", enif_make_double(env, value.z)},
                   {"w", enif_make_double(env, value.w)}});
}

ERL_NIF_TERM header_term(ErlNifEnv *env, const std_msgs::msg::Header &value) {
  return map(env, {{"frame_id", binary(env, value.frame_id)},
                   {"stamp", map(env, {{"sec", enif_make_int(env, value.stamp.sec)},
                                       {"nanosec", enif_make_uint(env, value.stamp.nanosec)}})}});
}

} // namespace

int open_tf2_resource_type(ErlNifEnv *env) {
  buffer_type = enif_open_resource_type(
      env, nullptr, "tf2_buffer", destroy_buffer,
      static_cast<ErlNifResourceFlags>(ERL_NIF_RT_CREATE | ERL_NIF_RT_TAKEOVER), nullptr);
  return buffer_type ? 0 : 1;
}

ERL_NIF_TERM nif_tf2_buffer_new(ErlNifEnv *env, int, const ERL_NIF_TERM argv[]) {
  return protect(env, [&]() {
    auto cache_time = integer(env, argv[0]);
    if (cache_time < 0) throw std::invalid_argument("cache time must be nonnegative");
    auto buffer   = std::make_unique<tf2::BufferCore>(tf2::Duration(cache_time));
    auto *storage = enif_alloc_resource(buffer_type, sizeof(BufferResource));
    if (!storage) throw std::bad_alloc();
    new (storage) BufferResource(std::move(buffer));
    auto result = enif_make_resource(env, storage);
    enif_release_resource(storage);
    return ok(env, result);
  });
}

ERL_NIF_TERM nif_tf2_buffer_destroy(ErlNifEnv *env, int, const ERL_NIF_TERM argv[]) {
  return protect(env, [&]() {
    BufferResource *resource;
    if (!enif_get_resource(env, argv[0], buffer_type, reinterpret_cast<void **>(&resource))) {
      return enif_make_badarg(env);
    }
    std::lock_guard<std::mutex> lock(resource->mutex);
    resource->buffer.reset();
    return atom(env, "ok");
  });
}

ERL_NIF_TERM nif_tf2_clear(ErlNifEnv *env, int, const ERL_NIF_TERM argv[]) {
  return with_buffer(env, argv[0], [&](tf2::BufferCore &buffer) {
    buffer.clear();
    return atom(env, "ok");
  });
}

ERL_NIF_TERM nif_tf2_set_transform(ErlNifEnv *env, int, const ERL_NIF_TERM argv[]) {
  return with_buffer(env, argv[0], [&](tf2::BufferCore &buffer) {
    auto values = tuple(env, argv[1], 5);
    geometry_msgs::msg::TransformStamped transform;
    transform.header.frame_id = string(env, values[0]);
    transform.child_frame_id  = string(env, values[1]);
    auto stamp                = integer(env, values[2]);
    if (stamp < 0 || stamp / 1000000000LL > INT32_MAX) {
      throw std::invalid_argument("stamp is outside builtin_interfaces/Time range");
    }
    transform.header.stamp.sec        = static_cast<int32_t>(stamp / 1000000000LL);
    transform.header.stamp.nanosec    = static_cast<uint32_t>(stamp % 1000000000LL);
    auto translation                  = tuple(env, values[3], 3);
    auto rotation                     = tuple(env, values[4], 4);
    transform.transform.translation.x = number(env, translation[0]);
    transform.transform.translation.y = number(env, translation[1]);
    transform.transform.translation.z = number(env, translation[2]);
    transform.transform.rotation.x    = number(env, rotation[0]);
    transform.transform.rotation.y    = number(env, rotation[1]);
    transform.transform.rotation.z    = number(env, rotation[2]);
    transform.transform.rotation.w    = number(env, rotation[3]);
    auto authority                    = string(env, argv[2]);
    if (!enif_is_identical(argv[3], atom(env, "true")) &&
        !enif_is_identical(argv[3], atom(env, "false"))) {
      throw std::invalid_argument("is_static must be a boolean");
    }
    bool is_static = enif_is_identical(argv[3], atom(env, "true"));
    if (!buffer.setTransform(transform, authority, is_static)) {
      return error(env, "transform_rejected", "tf2 rejected invalid or expired transform data");
    }
    return atom(env, "ok");
  });
}

ERL_NIF_TERM nif_tf2_lookup_transform(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  return with_buffer(env, argv[0], [&](tf2::BufferCore &buffer) {
    auto result = argc == 4 ? buffer.lookupTransform(string(env, argv[1]), string(env, argv[2]),
                                                     time_point(env, argv[3]))
                            : buffer.lookupTransform(string(env, argv[1]), time_point(env, argv[2]),
                                                     string(env, argv[3]), time_point(env, argv[4]),
                                                     string(env, argv[5]));
    return ok(env, stamped_term(env, result));
  });
}

ERL_NIF_TERM nif_tf2_can_transform(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  return with_buffer(env, argv[0], [&](tf2::BufferCore &buffer) {
    std::string reason;
    bool result = argc == 4 ? buffer.canTransform(string(env, argv[1]), string(env, argv[2]),
                                                  time_point(env, argv[3]), &reason)
                            : buffer.canTransform(string(env, argv[1]), time_point(env, argv[2]),
                                                  string(env, argv[3]), time_point(env, argv[4]),
                                                  string(env, argv[5]), &reason);
    return enif_make_tuple2(env, atom(env, result ? "true" : "false"), binary(env, reason));
  });
}

ERL_NIF_TERM nif_tf2_all_frames_as_yaml(ErlNifEnv *env, int, const ERL_NIF_TERM argv[]) {
  return with_buffer(env, argv[0], [&](tf2::BufferCore &buffer) {
    return ok(env, binary(env, buffer.allFramesAsYAML()));
  });
}

ERL_NIF_TERM nif_tf2_list_frames(ErlNifEnv *env, int, const ERL_NIF_TERM argv[]) {
  return with_buffer(env, argv[0], [&](tf2::BufferCore &buffer) {
    auto frames = YAML::Load(buffer.allFramesAsYAML());
    std::vector<std::pair<std::string, ERL_NIF_TERM>> entries;
    if (frames.IsMap()) {
      for (const auto &frame : frames) {
        auto child = frame.first.as<std::string>();
        auto info  = frame.second;
        auto result =
            map(env,
                {{"child", binary(env, child)},
                 {"parent", binary(env, info["parent"].as<std::string>())},
                 {"broadcaster", binary(env, info["broadcaster"].as<std::string>())},
                 {"rate", enif_make_double(env, info["rate"].as<double>())},
                 {"most_recent_transform",
                  enif_make_double(env, info["most_recent_transform"].as<double>())},
                 {"oldest_transform", enif_make_double(env, info["oldest_transform"].as<double>())},
                 {"buffer_length", enif_make_double(env, info["buffer_length"].as<double>())}});
        entries.emplace_back(child, result);
      }
    }
    std::sort(entries.begin(), entries.end(),
              [](const auto &left, const auto &right) { return left.first < right.first; });
    auto result = enif_make_list(env, 0);
    for (auto entry = entries.rbegin(); entry != entries.rend(); ++entry) {
      result = enif_make_list_cell(env, entry->second, result);
    }
    return ok(env, result);
  });
}

ERL_NIF_TERM nif_tf2_get_latest_common_time(ErlNifEnv *env, int, const ERL_NIF_TERM argv[]) {
  return with_buffer(env, argv[0], [&](tf2::BufferCore &buffer) {
    auto target = buffer._validateFrameId("target_frame", string(env, argv[1]));
    auto source = buffer._validateFrameId("source_frame", string(env, argv[2]));
    tf2::TimePoint time;
    std::string reason;
    auto result = buffer._getLatestCommonTime(target, source, time, &reason);
    if (result != tf2::TF2Error::TF2_NO_ERROR) {
      return error(env, result == tf2::TF2Error::TF2_CONNECTIVITY_ERROR ? "connectivity" : "lookup",
                   reason);
    }
    return ok(env, enif_make_int64(env, time.time_since_epoch().count()));
  });
}

ERL_NIF_TERM nif_tf2_transform(ErlNifEnv *env, int, const ERL_NIF_TERM argv[]) {
  return with_buffer(env, argv[0], [&](tf2::BufferCore &buffer) {
    auto message = argv[1];
    auto header  = field(env, message, "header");
    auto stamp   = field(env, header, "stamp");
    auto sec     = integer(env, field(env, stamp, "sec"));
    auto nanosec = integer(env, field(env, stamp, "nanosec"));
    if (sec < 0 || sec > INT32_MAX || nanosec < 0 || nanosec >= 1000000000LL) {
      throw std::invalid_argument("invalid message timestamp");
    }
    auto source    = string(env, field(env, header, "frame_id"));
    auto transform = buffer.lookupTransform(
        string(env, argv[2]), source, tf2::TimePoint(tf2::Duration(sec * 1000000000LL + nanosec)));
    if (enif_is_identical(argv[3], atom(env, "point"))) {
      geometry_msgs::msg::PointStamped input, output;
      input.point = decode_xyz<geometry_msgs::msg::Point>(env, field(env, message, "point"));
      tf2::doTransform(input, output, transform);
      return ok(env, map(env, {{"header", header_term(env, output.header)},
                               {"point", xyz_term(env, output.point)}}));
    }
    if (enif_is_identical(argv[3], atom(env, "vector"))) {
      geometry_msgs::msg::Vector3Stamped input, output;
      input.vector = decode_xyz<geometry_msgs::msg::Vector3>(env, field(env, message, "vector"));
      tf2::doTransform(input, output, transform);
      return ok(env, map(env, {{"header", header_term(env, output.header)},
                               {"vector", xyz_term(env, output.vector)}}));
    }
    if (enif_is_identical(argv[3], atom(env, "quaternion"))) {
      geometry_msgs::msg::QuaternionStamped input, output;
      input.quaternion = decode_rotation(env, field(env, message, "quaternion"));
      tf2::doTransform(input, output, transform);
      return ok(env, map(env, {{"header", header_term(env, output.header)},
                               {"quaternion", rotation_term(env, output.quaternion)}}));
    }
    if (enif_is_identical(argv[3], atom(env, "pose"))) {
      geometry_msgs::msg::PoseStamped input, output;
      auto pose = field(env, message, "pose");
      input.pose.position =
          decode_xyz<geometry_msgs::msg::Point>(env, field(env, pose, "position"));
      input.pose.orientation = decode_rotation(env, field(env, pose, "orientation"));
      tf2::doTransform(input, output, transform);
      auto result = map(env, {{"position", xyz_term(env, output.pose.position)},
                              {"orientation", rotation_term(env, output.pose.orientation)}});
      return ok(env, map(env, {{"header", header_term(env, output.header)}, {"pose", result}}));
    }
    if (enif_is_identical(argv[3], atom(env, "transform"))) {
      geometry_msgs::msg::TransformStamped input, output;
      auto data            = field(env, message, "transform");
      input.child_frame_id = string(env, field(env, message, "child_frame_id"));
      input.transform.translation =
          decode_xyz<geometry_msgs::msg::Vector3>(env, field(env, data, "translation"));
      input.transform.rotation = decode_rotation(env, field(env, data, "rotation"));
      tf2::doTransform(input, output, transform);
      output.child_frame_id = input.child_frame_id;
      return ok(env, stamped_term(env, output));
    }
    throw std::invalid_argument("unsupported stamped geometry type");
  });
}