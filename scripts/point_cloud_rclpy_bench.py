"""Python/rclpy equivalent of scripts/point_cloud_conversion_benchee.exs.

Uses the *real* rclpy-generated message classes and its compiled C extension
(rclpy._rclpy_pybind11 via rclpy.serialization) to convert Python message
objects into the rmw/rosidl C representation and back - this is the actual
"C code that does the objects" path rclpy uses, not a hand-rolled Python
approximation.

IMPORTANT SCOPE CAVEAT: rclpy only exposes this conversion bundled with CDR
(de)serialization to bytes (serialize_message/deserialize_message). The
rclex benchmark (point_cloud_conversion_benchee.exs) measures only
struct <-> tuple <-> rcl-C-struct, *not* CDR encoding - that happens later,
symmetrically for both bindings, inside rcl_publish/rcl_take via the shared
rmw implementation. So the numbers below are not perfectly isolated to the
"language binding tax" - they include one extra step rclex's numbers don't.
Treat this as an upper bound / different-scope reference, not a strict
apples-to-apples split of conversion cost.

Usage: python3 scripts/point_cloud_rclpy_bench.py
"""

import timeit

from rclpy.serialization import deserialize_message, serialize_message
from sensor_msgs.msg import ChannelFloat32, PointCloud
from geometry_msgs.msg import Point32
from std_msgs.msg import Header


def build_point_cloud(n):
    return PointCloud(
        header=Header(frame_id="map"),
        points=[Point32(x=i * 1.0, y=i * 2.0, z=i * 3.0) for i in range(1, n + 1)],
        channels=[ChannelFloat32(name="intensity", values=[i * 1.0 for i in range(1, n + 1)])],
    )


def format_stat(seconds_per_op):
    if seconds_per_op < 1e-3:
        return f"{seconds_per_op * 1e6:.2f} us"
    return f"{seconds_per_op * 1e3:.2f} ms"


def bench(label, fn, number):
    duration = timeit.timeit(fn, number=number)
    per_op = duration / number
    print(f"{label:55s} {format_stat(per_op):>12s}/op  ({1 / per_op:,.0f} ops/sec)")


if __name__ == "__main__":
    for n in (10, 100, 1_000, 10_000):
        print(f"\n##### n={n} #####")
        struct = build_point_cloud(n)
        payload = serialize_message(struct)
        number = max(10, 20_000 // n)

        bench(
            "serialize_message() (obj -> C struct -> CDR bytes)",
            lambda: serialize_message(struct),
            number,
        )
        bench(
            "deserialize_message() (CDR bytes -> C struct -> obj)",
            lambda: deserialize_message(payload, PointCloud),
            number,
        )
