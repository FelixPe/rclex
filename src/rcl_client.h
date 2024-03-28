#include <erl_nif.h>

ERL_NIF_TERM nif_rcl_client_init(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]);
ERL_NIF_TERM nif_rcl_client_fini(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]);
ERL_NIF_TERM nif_rcl_send_request(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]);
ERL_NIF_TERM nif_rcl_take_response_with_info(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]);
