#include <erl_nif.h>

ERL_NIF_TERM nif_rcl_publisher_init(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]);
ERL_NIF_TERM nif_rcl_publisher_fini(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]);
ERL_NIF_TERM nif_rcl_publish(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]);
ERL_NIF_TERM nif_rcl_publisher_can_loan_messages(ErlNifEnv *env, int argc,
                                                 const ERL_NIF_TERM argv[]);
ERL_NIF_TERM nif_rcl_borrow_loaned_message(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]);
ERL_NIF_TERM nif_rcl_publish_loaned_message(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]);
ERL_NIF_TERM nif_rcl_return_loaned_message_from_publisher(ErlNifEnv *env, int argc,
                                                          const ERL_NIF_TERM argv[]);