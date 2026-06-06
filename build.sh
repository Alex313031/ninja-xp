#!/bin/bash

# Copyright (c) 2026 Alex313031

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
SCRIPTVER="2.0.1"

export HERE=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

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
  -l, --linux   Build GN for Linux
  -w, --win     Build GN for Windows
  -d, --debug   Make a debug build
  -v, --verbose Verbose build output

EOF

  exit 0
}

show_version() {
  printf "\n $SCRIPTNAME Version $SCRIPTVER \n\n"
  exit 0
}

install_deps() {
  if ! command -v apt-get >/dev/null; then
    die "--deps only supports apt-based systems (Ubuntu/Debian); install the prerequisites manually"
  fi
  # use sudo only when not already root (e.g. plain CI containers lack sudo)
  local sudo=""
  [ "$(id -u)" -ne 0 ] && sudo="sudo"

  printf "${GRE}Installing dependencies for $SCRIPTNAME...${c0}\n"
  # build-essential: gcc, g++, make for the Linux build. mingw-w64 provides the
  # x86_64-w64-mingw32-* cross toolchain used by the Windows build.
  $sudo apt-get update || die "apt-get update failed"
  $sudo apt-get install build-essential python3 \
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
    python3 configure.py --bootstrap --host=linux --platform=linux --debug $VFLAG &&
    mv -fv ninja ninja_bootstrap &&
    printf "${CYA}Making final build...${c0}\n"
    python3 configure.py --host=linux --platform=linux --debug $VFLAG &&
    ./ninja_bootstrap -j$JOB_COUNT &&
    mv -fv ninja ninja_debug &&
    printf "${GRE}Zipping up build.${c0}\n"
    zip "ninja_debug.zip" ninja_debug
    rm -fv ./ninja_bootstrap &&
    printf "${GRE}Done!${c0}\n"
  else
    printf "${GRE}Building Ninja for Linux using GCC...${c0}\n"
    printf "${CYA}Making bootstrap build...${c0}\n"
    python3 configure.py --bootstrap --host=linux --platform=linux $VFLAG &&
    mv -fv ninja ninja_bootstrap &&
    printf "${CYA}Making final build...${c0}\n"
    python3 configure.py --host=linux --platform=linux $VFLAG &&
    ./ninja_bootstrap -j$JOB_COUNT &&
    printf "${GRE}Zipping up build.${c0}\n"
    zip "ninja_linux.zip" ninja
    rm -fv ./ninja_bootstrap &&
    printf "${GRE}Done!${c0}\n"
  fi
}

clean_out() {
  printf "${YEL}Cleaning .zips...${c0}\n"
  rm -rfv ${HERE}/ninja*.zip
}

build_windows() {
  export CC=gcc
  export CXX=g++
  export AR=ar
  export LD=g++
  if [ "$WANT_DEBUG" == "1" ]; then
    printf "${GRE}Building Ninja for Windows using MinGW (Debug)...${c0}\n"
    printf "${CYA}Making bootstrap Linux build...${c0}\n"
    python3 configure.py --bootstrap --host=linux --platform=linux --debug $VFLAG &&
    mv -fv ninja ninja_bootstrap &&
    printf "${CYA}Making final build...${c0}\n"
    # Cross-compile for Windows using the mingw-w64 toolchain (installed via --deps).
    # gen.py defaults the mingw toolchain to plain g++/ar, which is the host
    # compiler, so we must point it at the cross compiler explicitly.
    export CC=x86_64-w64-mingw32-gcc
    export CXX=x86_64-w64-mingw32-g++
    export AR=x86_64-w64-mingw32-ar
    export LD=x86_64-w64-mingw32-g++
    python3 configure.py --host=linux --platform=mingw --debug $VFLAG &&
    ./ninja_bootstrap -j$JOB_COUNT &&
    mv -fv ninja.exe ninja_debug.exe &&
    printf "${GRE}Zipping up build.${c0}\n"
    zip "ninja_win_debug.zip" ninja_debug.exe
    rm -fv ./ninja_bootstrap &&
    printf "${GRE}Done!${c0}\n"
  else
    printf "${GRE}Building Ninja for Windows using MinGW...${c0}\n"
    printf "${CYA}Making bootstrap Linux build...${c0}\n"
    python3 configure.py --bootstrap --host=linux --platform=linux $VFLAG &&
    mv -fv ninja ninja_bootstrap &&
    printf "${CYA}Making final build...${c0}\n"
    export CC=x86_64-w64-mingw32-gcc
    export CXX=x86_64-w64-mingw32-g++
    export AR=x86_64-w64-mingw32-ar
    export LD=x86_64-w64-mingw32-g++
    python3 configure.py --host=linux --platform=mingw $VFLAG &&
    ./ninja_bootstrap -j$JOB_COUNT &&
    printf "${GRE}Zipping up build.${c0}\n"
    zip "ninja_win.zip" ninja.exe
    rm -fv ./ninja_bootstrap &&
    printf "${GRE}Done!${c0}\n"
  fi
}

while :; do
  case $1 in
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
        WANT_TARGET="linux"
        ;;
    -w|--win)
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
      show_help
      ;;
esac

exit 0
