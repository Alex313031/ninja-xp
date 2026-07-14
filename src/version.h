// Copyright 2013 Google Inc. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#ifndef NINJA_VERSION_H_
#define NINJA_VERSION_H_

#if defined(__clang__) && defined(_UNICODE)
 #pragma code_page(65001) // UTF-8
#endif

// Macro to convert to string
#if !defined(_STRINGIZER_)
 #define _STRINGIZER_
 #define _STRINGIZER(in) #in
 #define STRINGIZE(in) _STRINGIZER(in)
  // Wide-string variant: L ## "x" -> L"x". Two levels so the argument expands
 // before the L## paste widens the resulting narrow literal.
 #define _WIDEN(in) L ## in
 #define WIDEN(in) _WIDEN(in)
#endif // !defined(_STRINGIZER_)

// ---------------------------------------------------------------------------
// Version and fork identity.
//
// These are plain preprocessor macros (rather than C++ constants) so that the
// Windows resource script windows/ninja.rc can #include this header and feed
// the same values into its VERSIONINFO block.  Keep the four numeric
// components below in sync with NINJA_VERSION.
// ---------------------------------------------------------------------------
#define NINJA_VERSION_MAJOR 1
#define NINJA_VERSION_MINOR 13
#define NINJA_VERSION_PATCH 2
#define NINJA_VERSION_TWEAK 0

/// The version number of the current Ninja release, as a string.  This will
/// always be "git" on trunk.
#define NINJA_VERSION STRINGIZE(NINJA_VERSION_MAJOR.NINJA_VERSION_MINOR.NINJA_VERSION_PATCH)
#define NINJA_VERSIONW WIDEN(STRINGIZE(NINJA_VERSION_MAJOR.NINJA_VERSION_MINOR.NINJA_VERSION_PATCH))

// Fork identity, surfaced in the Windows executable's "Details" tab.
#define PRODUCT_NAME L"Ninja XP"
#define RC_INTERNALNAME L"ninja-xp"
#define RC_COMPANYNAME   L"Alex313031"
#define RC_FILEDESCRIPTION L"Ninja build system - Windows XP/Vista fork."
#define RC_COPYRIGHT L"\251 2011-2026 Google Inc. and Alex313031."
#define RC_TRADEMARKS L"Apache License"
#define RC_COMMENTS L"https://github.com/Alex313031/ninja-xp"

// RC_INVOKED is defined by the resource compiler's preprocessor; the C++
// declarations below are of no use to it (and <string> must not be pulled in).
#ifndef RC_INVOKED

#include <string>

/// The version number of the current Ninja release.  This will always
/// be "git" on trunk.
extern const char* kNinjaVersion;

// Brand name for Ninja
extern const char* kNinjaProductName;

/// Parse the major/minor components of a version string.
void ParseVersion(const std::string& version, int* major, int* minor);

/// Check whether \a version is compatible with the current Ninja version,
/// aborting if not.
void CheckNinjaVersion(const std::string& required_version);

#endif  // RC_INVOKED

#endif  // NINJA_VERSION_H_
