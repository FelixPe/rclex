#include <erl_nif.h>
#include <stdio.h>
#include <string.h>
#include <rcutils/error_handling.h>

extern ERL_NIF_TERM atom_ok;
extern ERL_NIF_TERM atom_error;
extern ERL_NIF_TERM atom_true;
extern ERL_NIF_TERM atom_false;
extern ERL_NIF_TERM atom_nan;
extern ERL_NIF_TERM atom_infinity;
extern ERL_NIF_TERM atom_neg_infinity;

extern void make_common_atoms(ErlNifEnv *env);
extern ERL_NIF_TERM nif_test_raise(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]);
extern ERL_NIF_TERM nif_test_raise_with_message(ErlNifEnv *env, int argc,
                                                const ERL_NIF_TERM argv[]);
extern ERL_NIF_TERM enif_make_binary_wrapper(ErlNifEnv *env, const char *data, size_t size);

static inline ERL_NIF_TERM raise(ErlNifEnv *env, const char *file, int line) {
  char str[1024];
  snprintf(str, sizeof(str), "at %s:%d", file, line);
  return enif_raise_exception(env, enif_make_string(env, str, ERL_NIF_LATIN1));
}

static inline ERL_NIF_TERM raise_with_message(ErlNifEnv *env, const char *file, int line,
                                              const char *message) {
  char str[2048];
  snprintf(str, sizeof(str), "at %s:%d %s", file, line, message);
  return enif_raise_exception(env, enif_make_string(env, str, ERL_NIF_LATIN1));
}

static inline ERL_NIF_TERM raise_with_safe_message(ErlNifEnv *env, const char *file, int line,
                                                   int error_code) {
  const char *error_str = rcutils_get_error_string().str;
  char fallback_msg[256];

  // If error string is empty or just "error not set", provide a fallback with return code
  if (!error_str || strlen(error_str) == 0 || strcmp(error_str, "error not set") == 0) {
    snprintf(fallback_msg, sizeof(fallback_msg), "rcl function returned error code %d", error_code);
    return raise_with_message(env, file, line, fallback_msg);
  }

  return raise_with_message(env, file, line, error_str);
}
