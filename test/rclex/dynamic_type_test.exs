defmodule Rclex.DynamicTypeTest do
  use ExUnit.Case

  alias Rclex.DynamicType
  alias Rclex.Nif

  setup do
    Application.ensure_started(:rclex)
    context = Nif.rcl_init!()
    on_exit(fn -> Nif.rcl_fini!(context) end)
    :ok
  end

  test "from_description, fill_message, destroy_message, and fini" do
    type_description = %{
      type_description: %{
        type_name: "std_msgs/msg/String",
        fields: [
          %{
            name: "data",
            type: %{
              type_id: 17,
              capacity: 0,
              string_capacity: 0,
              nested_type_name: ""
            },
            default_value: ""
          }
        ]
      },
      referenced_type_descriptions: []
    }

    case DynamicType.from_description(type_description) do
      {:ok, dynamic_type_res} ->
        assert is_reference(dynamic_type_res)

        message_map = %{data: "hello dynamic world"}
        assert {:ok, dynamic_msg_res} = DynamicType.fill_message(dynamic_type_res, message_map)
        assert is_reference(dynamic_msg_res)

        assert :ok = DynamicType.destroy_message(dynamic_msg_res)
        assert :ok = DynamicType.fini(dynamic_type_res)

      {:error, {:dynamic_type_support_init_failed, _reason}} ->
        # Expected on RMWs that do not support dynamic typesupport (e.g. rmw_zenoh_cpp, rmw_cyclonedds_cpp)
        :ok
    end
  end

  test "nested type description, fill_message, destroy_message, and fini" do
    type_description = %{
      type_description: %{
        type_name: "geometry_msgs/msg/PointStamped",
        fields: [
          %{
            name: "header",
            type: %{
              type_id: 1,
              capacity: 0,
              string_capacity: 0,
              nested_type_name: "std_msgs/msg/Header"
            },
            default_value: ""
          },
          %{
            name: "point",
            type: %{
              type_id: 1,
              capacity: 0,
              string_capacity: 0,
              nested_type_name: "geometry_msgs/msg/Point"
            },
            default_value: ""
          }
        ]
      },
      referenced_type_descriptions: [
        %{
          type_name: "builtin_interfaces/msg/Time",
          fields: [
            %{
              name: "sec",
              type: %{
                type_id: 6,
                capacity: 0,
                string_capacity: 0,
                nested_type_name: ""
              },
              default_value: ""
            },
            %{
              name: "nanosec",
              type: %{
                type_id: 7,
                capacity: 0,
                string_capacity: 0,
                nested_type_name: ""
              },
              default_value: ""
            }
          ]
        },
        %{
          type_name: "geometry_msgs/msg/Point",
          fields: [
            %{
              name: "x",
              type: %{
                type_id: 11,
                capacity: 0,
                string_capacity: 0,
                nested_type_name: ""
              },
              default_value: ""
            },
            %{
              name: "y",
              type: %{
                type_id: 11,
                capacity: 0,
                string_capacity: 0,
                nested_type_name: ""
              },
              default_value: ""
            },
            %{
              name: "z",
              type: %{
                type_id: 11,
                capacity: 0,
                string_capacity: 0,
                nested_type_name: ""
              },
              default_value: ""
            }
          ]
        },
        %{
          type_name: "std_msgs/msg/Header",
          fields: [
            %{
              name: "stamp",
              type: %{
                type_id: 1,
                capacity: 0,
                string_capacity: 0,
                nested_type_name: "builtin_interfaces/msg/Time"
              },
              default_value: ""
            },
            %{
              name: "frame_id",
              type: %{
                type_id: 17,
                capacity: 0,
                string_capacity: 0,
                nested_type_name: ""
              },
              default_value: ""
            }
          ]
        }
      ]
    }

    case DynamicType.from_description(type_description) do
      {:ok, dynamic_type_res} ->
        assert is_reference(dynamic_type_res)

        message_map = %{
          header: %{
            stamp: %{sec: 123, nanosec: 456},
            frame_id: "map"
          },
          point: %{
            x: 1.0,
            y: 2.0,
            z: 3.0
          }
        }

        assert {:ok, dynamic_msg_res} = DynamicType.fill_message(dynamic_type_res, message_map)
        assert is_reference(dynamic_msg_res)

        assert :ok = DynamicType.destroy_message(dynamic_msg_res)
        assert :ok = DynamicType.fini(dynamic_type_res)

      {:error, {:dynamic_type_support_init_failed, _reason}} ->
        :ok
    end
  end
end
