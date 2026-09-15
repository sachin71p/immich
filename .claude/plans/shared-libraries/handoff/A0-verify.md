# A0 verify — results (2026-09-14)

1. `native-apple/scripts/verify.sh all` → FAIL

First relevant error lines:
```
error: 'photoscore': Invalid manifest
error: link command failed with exit code 1 (use -v to see invocation)
Undefined symbols for architecture arm64:
  "PackageDescription.Package.__allocating_init(...)", referenced from:
      _main in Package-1.o
ld: symbol(s) not found for architecture arm64
clang: error: linker command failed with exit code 1
```

This failure is environmental: the Command Line Tools compiler and its
PackageDescription manifest API are version-incompatible. No project test ran.
