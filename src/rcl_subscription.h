#include <erl_nif.h>

ERL_NIF_TERM nif_rcl_subscription_init(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]);
ERL_NIF_TERM nif_rcl_subscription_fini(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]);
ERL_NIF_TERM nif_rcl_take(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]);
ERL_NIF_TERM nif_rcl_subscription_can_loan_messages(ErlNifEnv *env, int argc,
                                                    const ERL_NIF_TERM argv[]);
ERL_NIF_TERM nif_rcl_take_loaned_message(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]);
ERL_NIF_TERM nif_rcl_return_loaned_message_from_subscription(ErlNifEnv *env, int argc,
                                                             const ERL_NIF_TERM argv[]);