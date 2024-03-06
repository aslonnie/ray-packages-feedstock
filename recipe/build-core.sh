#!/bin/bash
set -xe

if [[ "$target_platform" == osx* ]]; then
  # make sure the vendored redis OSX build can find the correct toolchain. the SDKROOT is
  # also passed as we are using at least OSX 10.15 which moves the include directory out
  # of /usr/include to ${SDKROOT}/MacOSX.sdk/usr/include
  cat >> .bazelrc <<EOF
build --define CONDA_CC=${CC}
build --define CONDA_CFLAGS="${CFLAGS}"
build --define CONDA_AR=${AR}
build --define CONDA_NM=${NM}
build --define CONDA_RANLIB=${RANLIB}
build --define CONDA_SDKROOT=${SDKROOT}
EOF
fi

if [[ -e $CONDA_PREFIX/include/crypt.h ]]; then
    # fix for python3.8 which depends on system includes for crypt.h
    # but the bazel sandbox does not add it
    cp $CONDA_PREFIX/include/crypt.h $PREFIX/include/python*
fi

cd python/
export SKIP_THIRDPARTY_INSTALL=1
"${PYTHON}" setup.py build
# bazel by default makes everything read-only,
# which leads to patchelf failing to fix rpath in binaries.
# find all ray binaries and make them writable
grep -lR ELF build/ | xargs chmod +w

# now install the thing so conda could pick it up
"${PYTHON}" setup.py install  --single-version-externally-managed --root=/

# now clean everything up so subsequent builds (for potentially
# different Python version) do not stumble on some after-effects
"${PYTHON}" setup.py clean --all
bazel "--output_user_root=$SRC_DIR/../bazel-root" "--output_base=$SRC_DIR/../b-o" clean
bazel "--output_user_root=$SRC_DIR/../bazel-root" "--output_base=$SRC_DIR/../b-o" shutdown
rm -rf "$SRC_DIR/../b-o" "$SRC_DIR/../bazel-root"

if [[ "$target_platform" == "linux-"* ]]; then
  ls -lR $SP_DIR
  # Remove RUNPATH and set RPATH
  for f in "ray/_raylet.so" "ray/core/src/ray/raylet/raylet" "ray/core/src/ray/gcs/gcs_server" "ray/core/libjemalloc.so"; do
    chmod +w $SP_DIR/$f
    patchelf --remove-rpath $SP_DIR/$f
    patchelf --force-rpath --add-rpath $PREFIX/lib $SP_DIR/$f
  done
fi
