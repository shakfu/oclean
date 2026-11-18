/* Descriptor-relative file system calls missing from OCaml's Unix library. */

#define CAML_NAME_SPACE
#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
#include <caml/unixsupport.h>
#include <caml/version.h>

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#if OCAML_VERSION_MAJOR >= 5
#define raise_unix_error caml_uerror
#else
#define raise_unix_error uerror
#endif

value oclean_openat_dir(value dirfd, value name)
{
  CAMLparam2(dirfd, name);
  int fd = openat(Int_val(dirfd), String_val(name), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
  if (fd < 0) raise_unix_error("openat", name);
  CAMLreturn(Val_int(fd));
}

/* Constructor order of Unix.file_kind. */
static int kind_of(mode_t mode)
{
  switch (mode & S_IFMT) {
  case S_IFREG: return 0;
  case S_IFDIR: return 1;
  case S_IFCHR: return 2;
  case S_IFBLK: return 3;
  case S_IFLNK: return 4;
  case S_IFIFO: return 5;
  default: return 6; /* S_IFSOCK */
  }
}

/* Returns the At.stat record. dev and ino are converted as Unix.lstat does. */
value oclean_lstatat(value dirfd, value name)
{
  CAMLparam2(dirfd, name);
  CAMLlocal1(res);
  struct stat st;
  if (fstatat(Int_val(dirfd), String_val(name), &st, AT_SYMLINK_NOFOLLOW) < 0)
    raise_unix_error("fstatat", name);
  res = caml_alloc_tuple(4);
  Store_field(res, 0, Val_int(kind_of(st.st_mode)));
  Store_field(res, 1, Val_int(st.st_dev));
  Store_field(res, 2, Val_int(st.st_ino));
  Store_field(res, 3, Val_long(st.st_size));
  CAMLreturn(res);
}

value oclean_unlinkat(value dirfd, value name, value is_dir)
{
  CAMLparam3(dirfd, name, is_dir);
  if (unlinkat(Int_val(dirfd), String_val(name), Bool_val(is_dir) ? AT_REMOVEDIR : 0) < 0)
    raise_unix_error("unlinkat", name);
  CAMLreturn(Val_unit);
}

/* Reads a duplicate, so the caller keeps ownership of [fd]. */
value oclean_readdir_fd(value fd)
{
  CAMLparam1(fd);
  CAMLlocal3(names, cell, name);
  int dup_fd = dup(Int_val(fd));
  if (dup_fd < 0) raise_unix_error("dup", Nothing);
  DIR *d = fdopendir(dup_fd);
  if (d == NULL) {
    int saved = errno;
    close(dup_fd);
    errno = saved;
    raise_unix_error("fdopendir", Nothing);
  }
  rewinddir(d);
  names = Val_emptylist;
  for (;;) {
    errno = 0;
    struct dirent *e = readdir(d);
    if (e == NULL) break;
    if (strcmp(e->d_name, ".") == 0 || strcmp(e->d_name, "..") == 0) continue;
    name = caml_copy_string(e->d_name);
    cell = caml_alloc_small(2, 0);
    Field(cell, 0) = name;
    Field(cell, 1) = names;
    names = cell;
  }
  int saved = errno;
  closedir(d);
  if (saved != 0) {
    errno = saved;
    raise_unix_error("readdir", Nothing);
  }
  CAMLreturn(names);
}
