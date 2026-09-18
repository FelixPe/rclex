#include <erl_nif.h>

// See prototype_point_cloud_struct.c for the generalization notes.
void make_prototype_point_cloud_struct_atoms(ErlNifEnv *env);
ERL_NIF_TERM nif_sensor_msgs_msg_point_cloud_set_struct(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]);
ERL_NIF_TERM nif_sensor_msgs_msg_point_cloud_get_struct(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]);
