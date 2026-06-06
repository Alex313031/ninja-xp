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
SCRIPTVER="2.1.2"

export HERE=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# configure.py and the ./ninja_bootstrap paths are relative, so run from the
# repo root regardless of where the script was invoked from.
cd "$HERE" || die "Failed to cd into $HERE"

JOB_COUNT=$(getconf _NPROCESSORS_ONLN)

WANT_DEBUG=0
WANT_TARGET=""
VFLAG=""

show_help() {
  cat <<EOF
Usage:
  $SCRIPTNAME [options]

A script to build Ninja on Linux for Linux or Windows.

Options:
  -h, --help    Show this help.
  --version     Show script version.
  -c, --clean   Remove build artifacts
  --deps        Install build dependencies
  -l, --linux   Build Ninja for Linux
  -w, --win     Build Ninja for Windows
  -d, --debug   Make a debug build
  -v, --verbose Verbose build output

EOF

  exit 0
}

show_version() {
  printf "\n %s Version %s \n\n" "$SCRIPTNAME" "$SCRIPTVER"
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
  # build-essential: gcc, g++, make for the Linux build. mingw-w64 provides the
  # x86_64-w64-mingw32-* cross toolchain used by the Windows build.
  $sudo apt-get update || die "apt-get update failed"
  $sudo apt-get install build-essential python3 re2c zip \
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
  if [ "$WANT_DEBUG" == "1" ]; then
    printf "${GRE}Building Ninja for Linux using GCC (Debug)...${c0}\n"
    printf "${CYA}Making bootstrap build...${c0}\n"
    try python3 configure.py --bootstrap --host=linux --platform=linux --debug $VFLAG
    try mv -fv ninja ninja_bootstrap
    printf "${CYA}Making final build...${c0}\n"
    try python3 configure.py --host=linux --platform=linux --debug $VFLAG
    try ./ninja_bootstrap -j"$JOB_COUNT"
    try mv -fv ninja ninja_debug
    printf "${GRE}Zipping up build.${c0}\n"
    try zip "ninja_debug.zip" ninja_debug
    rm -fv ./ninja_bootstrap
    printf "${GRE}Done!${c0}\n"
  else
    printf "${GRE}Building Ninja for Linux using GCC...${c0}\n"
    printf "${CYA}Making bootstrap build...${c0}\n"
    try python3 configure.py --bootstrap --host=linux --platform=linux $VFLAG
    try mv -fv ninja ninja_bootstrap
    printf "${CYA}Making final build...${c0}\n"
    try python3 configure.py --host=linux --platform=linux $VFLAG
    try ./ninja_bootstrap -j"$JOB_COUNT"
    printf "${GRE}Zipping up build.${c0}\n"
    try zip "ninja_linux.zip" ninja
    rm -fv ./ninja_bootstrap
    printf "${GRE}Done!${c0}\n"
  fi
}

clean_out() {
  printf "${YEL}Cleaning build artifacts...${c0}\n"
  rm -fv "${HERE}"/ninja_*.zip \
         "${HERE}"/ninja "${HERE}"/ninja.exe \
         "${HERE}"/ninja_bootstrap \
         "${HERE}"/ninja_debug "${HERE}"/ninja_debug.exe
}

build_windows() {
  export CC=gcc
  export CXX=g++
  export AR=ar
  export LD=g++
  if [ "$WANT_DEBUG" == "1" ]; then
    printf "${GRE}Building Ninja for Windows using MinGW (Debug)...${c0}\n"
    printf "${CYA}Making bootstrap Linux build...${c0}\n"
    try python3 configure.py --bootstrap --host=linux --platform=linux --debug $VFLAG
    try mv -fv ninja ninja_bootstrap
    printf "${CYA}Making final build...${c0}\n"
    # Cross-compile for Windows using the mingw-w64 toolchain (installed via --deps).
    # configure.py defaults the mingw toolchain to plain g++/ar, which is the host
    # compiler, so we must point it at the cross compiler explicitly.
    export CC=x86_64-w64-mingw32-gcc
    export CXX=x86_64-w64-mingw32-g++
    export AR=x86_64-w64-mingw32-ar
    export LD=x86_64-w64-mingw32-g++
    try python3 configure.py --host=linux --platform=mingw --debug $VFLAG
    try ./ninja_bootstrap -j"$JOB_COUNT"
    try mv -fv ninja.exe ninja_debug.exe
    printf "${GRE}Zipping up build.${c0}\n"
    try zip "ninja_win_debug.zip" ninja_debug.exe
    rm -fv ./ninja_bootstrap
    printf "${GRE}Done!${c0}\n"
  else
    printf "${GRE}Building Ninja for Windows using MinGW...${c0}\n"
    printf "${CYA}Making bootstrap Linux build...${c0}\n"
    try python3 configure.py --bootstrap --host=linux --platform=linux $VFLAG
    try mv -fv ninja ninja_bootstrap
    printf "${CYA}Making final build...${c0}\n"
    export CC=x86_64-w64-mingw32-gcc
    export CXX=x86_64-w64-mingw32-g++
    export AR=x86_64-w64-mingw32-ar
    export LD=x86_64-w64-mingw32-g++
    try python3 configure.py --host=linux --platform=mingw $VFLAG
    try ./ninja_bootstrap -j"$JOB_COUNT"
    printf "${GRE}Zipping up build.${c0}\n"
    try zip "ninja_win.zip" ninja.exe
    rm -fv ./ninja_bootstrap
    printf "${GRE}Done!${c0}\n"
  fi
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
      yell "${YEL}No build target specified (use -l/--linux or -w/--win).${c0}"
      show_help
      ;;
esac

exit 0
