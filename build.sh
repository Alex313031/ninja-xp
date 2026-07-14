#!/bin/bash

# Copyright (c) 2026 Alex313031

# Abort on errors, unset variables, and failed pipes so a broken build can
# never silently fall through to zipping/cleanup and exit 0.
set -euo pipefail

YEL='\033[1;33m' # Yellow
CYA='\033[1;96m' # Cyan
RED='\033[1;31m' # Red
GRE='\033[1;32m' # Green
c0='\033[0;00m'  # Reset Text
bold='\033[1;37m' # Bold Text
underline='\033[4m' # Underline Text

# Error handling
yell() { echo -e "$0: $*" >&2; }
die()  { yell "${RED}$* ${c0}"; exit 1; }
try() { "$@" || die "${RED}Failed $*"; }

SCRIPTNAME=$(basename "$0")
SCRIPTVER="2.1.4"

export HERE=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# configure.py and the ./ninja_bootstrap paths are relative, so run from the
# repo root regardless of where the script was invoked from.
cd "$HERE" || die "Failed to cd into $HERE"

JOB_COUNT=$(getconf _NPROCESSORS_ONLN)

WANT_DEBUG=0
WANT_I386=0
WANT_TARGET=""
VFLAG=""

show_help() {
  cat <<EOF
Usage:
  $SCRIPTNAME [options]

A script to build Ninja on Linux for Linux or Windows.

Options:
  -h, --help    Show this help
  --version     Show script version
  -c, --clean   Remove build artifacts
  --deps        Install build dependencies
  --i386        Make a 32 bit build (i386 on Linux, win32 on Windows)
  -l, --linux   Build Ninja for Linux
  -w, --win     Build Ninja for Windows
  -d, --debug   Make a debug build
  -v, --verbose Verbose build output

EOF

  exit 0
}

show_version() {
  printf "\n ${bold} %s Version %s \n\n" "$SCRIPTNAME" "$SCRIPTVER"
  exit 0
}

install_deps() {
  if ! command -v apt-get >/dev/null; then
    die "--deps only supports apt-based systems (Ubuntu/Debian); install the prerequisites manually"
  fi
  # use sudo only when not already root (e.g. plain CI containers lack sudo).
  # An if-block (not `&& sudo=...`) so the root case doesn't trip `set -e`.
  local sudo=""
  if [ "$(id -u)" -ne 0 ]; then sudo="sudo"; fi

  printf "${GRE}Installing dependencies for %s...${c0}\n" "$SCRIPTNAME"
  # build-essential: gcc, g++, make for the Linux build; g++-multilib adds the
  # 32-bit libs needed for --i386 Linux builds. mingw-w64 provides the
  # *-w64-mingw32-* cross toolchains used by the Windows builds.
  $sudo apt-get update || die "apt-get update failed"
  $sudo apt-get install build-essential g++-multilib python3 re2c zip \
        mingw-w64 mingw-w64-i686-dev mingw-w64-x86-64-dev mingw-w64-tools \
      || die "Failed to install dependencies"
  printf "${GRE}Done installing dependencies!${c0}\n"
}

build_linux() {
  # Build using system GCC, not clang
  export CC=gcc
  export CXX=g++
  export AR=ar
  export LD=g++
  # 32- vs 64-bit Linux. The bootstrap ninja is built host-native (it runs on the
  # build host to drive the final build); only the FINAL ninja gets the arch flag,
  # via configure.py's CFLAGS/CXXFLAGS (which it routes into both compile and link).
  # So a 64-bit host needs only g++-multilib's 32-bit libs, not a 32-bit runtime.
  local arch="" mflag="-m64"
  if [ "$WANT_I386" == "1" ]; then
    arch="_i386"
    mflag="-m32"
  fi
  local zipname="ninja_linux${arch}"
  if [ "$WANT_DEBUG" == "1" ]; then
    printf "${GRE}Building Ninja for Linux using GCC (Debug)...${c0}\n"
    printf "${CYA}Making bootstrap build...${c0}\n"
    try python3 configure.py --bootstrap --host=linux --platform=linux --debug $VFLAG
    try mv -fv ninja ninja_bootstrap
    printf "${CYA}Making final build...${c0}\n"
    export CFLAGS="$mflag" CXXFLAGS="$mflag" LDFLAGS="$mflag"
    try python3 configure.py --host=linux --platform=linux --debug $VFLAG
    try ./ninja_bootstrap -j"$JOB_COUNT"
    try mv -fv ninja ninja_debug
    zipname+="_debug"
    printf "${GRE}Zipping up ninja_debug...${c0}\n"
    try zip "$zipname.zip" ninja_debug
    rm -fv ./ninja_bootstrap
  else
    printf "${GRE}Building Ninja for Linux using GCC...${c0}\n"
    printf "${CYA}Making bootstrap build...${c0}\n"
    try python3 configure.py --bootstrap --host=linux --platform=linux $VFLAG
    try mv -fv ninja ninja_bootstrap
    printf "${CYA}Making final build...${c0}\n"
    export CFLAGS="$mflag" CXXFLAGS="$mflag" LDFLAGS="$mflag"
    try python3 configure.py --host=linux --platform=linux $VFLAG
    try ./ninja_bootstrap -j"$JOB_COUNT"
    printf "${GRE}Zipping up ninja... ${c0}\n"
    try zip "$zipname.zip" ninja
    rm -fv ./ninja_bootstrap
  fi
  printf "${GRE}Done! Zip at ${CYA}${zipname}.zip ${c0}\n"
}

clean_out() {
  printf "${YEL}Cleaning build artifacts...${c0}\n"
  rm -fv "${HERE}"/ninja_*.zip \
         "${HERE}"/ninja "${HERE}"/ninja.exe \
         "${HERE}"/ninja_bootstrap \
         "${HERE}"/ninja_debug "${HERE}"/ninja_debug.exe
}

build_windows() {
  local zipname="" cross=""
  # Pick the cross toolchain prefix and artifact name by target arch. The
  # bootstrap ninja built below is a *native Linux* binary (it compiles POSIX
  # code like browse.cc's fork/pipe), so it MUST use the host g++ -- only the
  # final mingw build uses $cross.
  if [ "$WANT_I386" == "1" ]; then
    cross="i686-w64-mingw32"
    zipname="ninja_win32"
  else
    cross="x86_64-w64-mingw32"
    zipname="ninja_win64"
  fi
  # Host toolchain for the bootstrap build.
  export CC=gcc CXX=g++ AR=ar LD=g++
  if [ "$WANT_DEBUG" == "1" ]; then
    printf "${GRE}Building Ninja for Windows using MinGW (Debug)...${c0}\n"
    printf "${CYA}Making bootstrap Linux build...${c0}\n"
    try python3 configure.py --bootstrap --host=linux --platform=linux --debug $VFLAG
    try mv -fv ninja ninja_bootstrap
    printf "${CYA}Making final build...${c0}\n"
    # Cross-compile for Windows. configure.py defaults the mingw toolchain to
    # plain g++/ar (the host compiler), so point it at the cross compiler.
    export CC="$cross-gcc" CXX="$cross-g++" AR="$cross-ar" LD="$cross-g++" WINDRES="$cross-windres"
    try python3 configure.py --host=linux --platform=mingw --debug $VFLAG
    try ./ninja_bootstrap -j"$JOB_COUNT"
    try mv -fv ninja.exe ninja_debug.exe
    zipname+="_debug"
    printf "${GRE}Zipping up ninja_debug.exe... ${c0}\n"
    try zip "$zipname.zip" ninja_debug.exe
    rm -fv ./ninja_bootstrap
  else
    printf "${GRE}Building Ninja for Windows using MinGW...${c0}\n"
    printf "${CYA}Making bootstrap Linux build...${c0}\n"
    try python3 configure.py --bootstrap --host=linux --platform=linux $VFLAG
    try mv -fv ninja ninja_bootstrap
    printf "${CYA}Making final build...${c0}\n"
    export CC="$cross-gcc" CXX="$cross-g++" AR="$cross-ar" LD="$cross-g++" WINDRES="$cross-windres"
    try python3 configure.py --host=linux --platform=mingw $VFLAG
    try ./ninja_bootstrap -j"$JOB_COUNT"
    printf "${GRE}Zipping up ninja.exe... ${c0}\n"
    try zip "$zipname.zip" ninja.exe
    rm -fv ./ninja_bootstrap
  fi
  printf "${GRE}Done! Zip at ${CYA}${zipname}.zip ${c0}\n"
}

while :; do
  case ${1:-} in
    -h|--help)
        show_help
        ;;
    --version)
        show_version
        ;;
    --deps)
        install_deps
        exit 0
        ;;
    -v|--verbose)
        VFLAG="--verbose"
        ;;
    -c|--clean)
        clean_out
        exit 0
        ;;
    --i386)
        WANT_I386=1
        ;;
    -d|--debug)
        WANT_DEBUG=1
        ;;
    -l|--linux)
        [ -n "$WANT_TARGET" ] && [ "$WANT_TARGET" != "linux" ] && die "Cannot specify both linux and win"
        WANT_TARGET="linux"
        ;;
    -w|--win)
        [ -n "$WANT_TARGET" ] && [ "$WANT_TARGET" != "windows" ] && die "Cannot specify both linux and win"
        WANT_TARGET="windows"
        ;;
    --)
        shift
        break
        ;;
    -?*)
        die "Unknown option '$1'"
        ;;
    *)
        break
  esac
  shift
done

case "$WANT_TARGET" in
  linux)
      build_linux
      ;;
  windows)
      build_windows
      ;;
  *)
      yell "${YEL}No build target specified (use -l/--linux or -w/--win).${c0}\n"
      show_help
      ;;
esac

exit 0
