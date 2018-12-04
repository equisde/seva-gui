#!/bin/bash
LOKI_URL=https://gitlab.com/Sevabit/SevaBit.git

pushd $(pwd)
ROOT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source $ROOT_DIR/utils.sh

INSTALL_DIR=$ROOT_DIR/wallet
SEVABIT_DIR=$ROOT_DIR/sevabit
BUILD_LIBWALLET=false

# init and update sevabit submodule
if [ ! -d $SEVABIT_DIR/src ]; then
    git submodule init sevabit
fi
git submodule update --remote
# git -C $SEVABIT_DIR fetch
git -C $SEVABIT_DIR checkout master

# get sevabit core tag
get_tag
# create local sevabit branch
git -C $SEVABIT_DIR checkout -B $VERSIONTAG

git -C $SEVABIT_DIR submodule init
git -C $SEVABIT_DIR submodule update

# Merge sevabit PR dependencies

# Workaround for git username requirements
# Save current user settings and revert back when we are done with merging PR's
OLD_GIT_USER=$(git -C $SEVABIT_DIR config --local user.name)
OLD_GIT_EMAIL=$(git -C $SEVABIT_DIR config --local user.email)
git -C $SEVABIT_DIR config user.name "SevaBit GUI"
git -C $SEVABIT_DIR config user.email "gui@sevabit.local"
# check for PR requirements in most recent commit message (i.e requires #xxxx)
for PR in $(git log --format=%B -n 1 | grep -io "requires #[0-9]*" | sed 's/[^0-9]*//g'); do
    echo "Merging sevabit push request #$PR"
    # fetch pull request and merge
    git -C $SEVABIT_DIR fetch origin pull/$PR/head:PR-$PR
    git -C $SEVABIT_DIR merge --quiet PR-$PR  -m "Merge sevabit PR #$PR"
    BUILD_LIBWALLET=true
done

# revert back to old git config
$(git -C $SEVABIT_DIR config user.name "$OLD_GIT_USER")
$(git -C $SEVABIT_DIR config user.email "$OLD_GIT_EMAIL")

# Build libwallet if it doesnt exist
if [ ! -f $SEVABIT_DIR/lib/libwallet_merged.a ]; then 
    echo "libwallet_merged.a not found - Building libwallet"
    BUILD_LIBWALLET=true
# Build libwallet if no previous version file exists
elif [ ! -f $SEVABIT_DIR/version.sh ]; then 
    echo "sevabit/version.h not found - Building libwallet"
    BUILD_LIBWALLET=true
## Compare previously built version with submodule + merged PR's version. 
else
    source $SEVABIT_DIR/version.sh
    # compare submodule version with latest build
    pushd "$SEVABIT_DIR"
    get_tag
    popd
    echo "latest libwallet version: $GUI_LOKI_VERSION"
    echo "Installed libwallet version: $VERSIONTAG"
    # check if recent
    if [ "$VERSIONTAG" != "$GUI_LOKI_VERSION" ]; then
        echo "Building new libwallet version $GUI_LOKI_VERSION"
        BUILD_LIBWALLET=true
    else
        echo "latest libwallet ($GUI_LOKI_VERSION) is already built. Remove sevabit/lib/libwallet_merged.a to force rebuild"
    fi
fi

if [ "$BUILD_LIBWALLET" != true ]; then
    # exit this script
    return
fi

echo "GUI_LOKI_VERSION=\"$VERSIONTAG\"" > $SEVABIT_DIR/version.sh

## Continue building libwallet

# default build type
BUILD_TYPE=$1
if [ -z $BUILD_TYPE ]; then
    BUILD_TYPE=release
fi

STATIC=false
ANDROID=false
if [ "$BUILD_TYPE" == "release" ]; then
    echo "Building libwallet release"
    CMAKE_BUILD_TYPE=Release
elif [ "$BUILD_TYPE" == "release-static" ]; then
    echo "Building libwallet release-static"
    CMAKE_BUILD_TYPE=Release
    STATIC=true
elif [ "$BUILD_TYPE" == "release-android" ]; then
    echo "Building libwallet release-static for ANDROID"
    CMAKE_BUILD_TYPE=Release
    STATIC=true
    ANDROID=true
elif [ "$BUILD_TYPE" == "debug-android" ]; then
    echo "Building libwallet debug-static for ANDROID"
    CMAKE_BUILD_TYPE=Debug
    STATIC=true
    ANDROID=true
elif [ "$BUILD_TYPE" == "debug" ]; then
    echo "Building libwallet debug"
    CMAKE_BUILD_TYPE=Debug
    STATIC=true
else
    echo "Valid build types are release, release-static, release-android, debug-android and debug"
    exit 1;
fi


echo "cleaning up existing sevabit build dir, libs and includes"
rm -fr $SEVABIT_DIR/build
rm -fr $SEVABIT_DIR/lib
rm -fr $SEVABIT_DIR/include
rm -fr $SEVABIT_DIR/bin


mkdir -p $SEVABIT_DIR/build/$BUILD_TYPE
pushd $SEVABIT_DIR/build/$BUILD_TYPE

# reusing function from "utils.sh"
platform=$(get_platform)
# default make executable
make_exec="make"

env | sort

## OS X
if [ "$platform" == "darwin" ]; then
    echo "Configuring build for MacOS.."
    if [ "$STATIC" == true ]; then
        # cmake -D CMAKE_BUILD_TYPE=$CMAKE_BUILD_TYPE -D STATIC=ON -D ARCH="x86-64" -D BUILD_64=ON -D BUILD_GUI_DEPS=ON -D INSTALL_VENDORED_LIBUNBOUND=ON -D CMAKE_INSTALL_PREFIX="$SEVABIT_DIR"  ../..
        cmake -D CMAKE_BUILD_TYPE=$CMAKE_BUILD_TYPE -D STATIC=ON -D ARCH="x86-64" -D BUILD_64=ON -D BUILD_GUI_DEPS=ON -D INSTALL_VENDORED_LIBUNBOUND=ON -D CMAKE_PREFIX_PATH="$OPENSSL_ROOT_DIR" -D CMAKE_INSTALL_PREFIX="$SEVABIT_DIR" -D ZMQ_LIB=$ZMQ_LIBRARY -D Termcap_LIBRARY=$Termcap_LIBRARY -D Readline_ROOT_DIR=$Readline_ROOT_DIR -D ZMQ_INCLUDE_PATH=$ZMQ_INCLUDE_PATH ../.. -D PCSC_LIBRARY=$PCSC_LIBRARY -D PCSC_INCLUDE_DIR=$PCSC_INCLUDE_DIR
    else
        cmake -D CMAKE_BUILD_TYPE=$CMAKE_BUILD_TYPE  -D BUILD_GUI_DEPS=ON -D INSTALL_VENDORED_LIBUNBOUND=ON -D CMAKE_INSTALL_PREFIX="$SEVABIT_DIR"  ../..
    fi

## LINUX 64
elif [ "$platform" == "linux64" ]; then
    echo "Configuring build for Linux x64"
    if [ "$ANDROID" == true ]; then
        echo "Configuring build for Android on Linux host"
        cmake -D CMAKE_BUILD_TYPE=$CMAKE_BUILD_TYPE -D STATIC=ON -D ARCH="armv7-a" -D ANDROID=true -D BUILD_GUI_DEPS=ON -D USE_LTO=OFF -D INSTALL_VENDORED_LIBUNBOUND=ON -D CMAKE_INSTALL_PREFIX="$SEVABIT_DIR"  ../..
    elif [ "$STATIC" == true ]; then
        cmake -D CMAKE_BUILD_TYPE=$CMAKE_BUILD_TYPE -D STATIC=ON -D ARCH="x86-64" -D BUILD_64=ON -D BUILD_GUI_DEPS=ON -D INSTALL_VENDORED_LIBUNBOUND=ON -D CMAKE_INSTALL_PREFIX="$SEVABIT_DIR" -D CMAKE_PREFIX_PATH=$OPENSSL_ROOT_DIR -D PCSC_LIBRARY=$PCSC_LIBRARY -D PCSC_INCLUDE_DIR=$PCSC_INCLUDE_DIR -D Termcap_LIBRARY=$Termcap_LIBRARY -D Readline_ROOT_DIR=$Readline_ROOT_DIR -D ZMQ_LIB=$ZMQ_LIBRARY -D ZMQ_INCLUDE_PATH=$ZMQ_INCLUDE_PATH ../..
    else
        cmake -D CMAKE_BUILD_TYPE=$CMAKE_BUILD_TYPE -D BUILD_GUI_DEPS=ON -D CMAKE_INSTALL_PREFIX="$SEVABIT_DIR"  ../..
    fi

## LINUX 32
elif [ "$platform" == "linux32" ]; then
    echo "Configuring build for Linux i686"
    if [ "$STATIC" == true ]; then
        cmake -D CMAKE_BUILD_TYPE=$CMAKE_BUILD_TYPE -D STATIC=ON -D ARCH="i686" -D BUILD_64=OFF -D BUILD_GUI_DEPS=ON -D INSTALL_VENDORED_LIBUNBOUND=ON -D CMAKE_INSTALL_PREFIX="$SEVABIT_DIR"  ../..
    else
        cmake -D CMAKE_BUILD_TYPE=$CMAKE_BUILD_TYPE -D BUILD_GUI_DEPS=ON -D CMAKE_INSTALL_PREFIX="$SEVABIT_DIR"  ../..
    fi

## LINUX ARMv7
elif [ "$platform" == "linuxarmv7" ]; then
    echo "Configuring build for Linux armv7"
    if [ "$STATIC" == true ]; then
        cmake -D BUILD_TESTS=OFF -D ARCH="armv7-a" -D STATIC=ON -D BUILD_64=OFF  -D BUILD_GUI_DEPS=ON -D CMAKE_INSTALL_PREFIX="$SEVABIT_DIR"  ../..
    else
        cmake -D BUILD_TESTS=OFF -D ARCH="armv7-a" -D -D BUILD_64=OFF  -D BUILD_GUI_DEPS=ON -D CMAKE_INSTALL_PREFIX="$SEVABIT_DIR"  ../..
    fi

## LINUX other 
elif [ "$platform" == "linux" ]; then
    echo "Configuring build for Linux general"
    if [ "$STATIC" == true ]; then
        cmake -D CMAKE_BUILD_TYPE=$CMAKE_BUILD_TYPE -D STATIC=ON -D BUILD_GUI_DEPS=ON -D INSTALL_VENDORED_LIBUNBOUND=ON -D CMAKE_INSTALL_PREFIX="$SEVABIT_DIR"  ../..
    else
        cmake -D CMAKE_BUILD_TYPE=$CMAKE_BUILD_TYPE -D BUILD_GUI_DEPS=ON -D CMAKE_INSTALL_PREFIX="$SEVABIT_DIR"  ../..
    fi

## Windows 64
## Windows is always static to work outside msys2
elif [ "$platform" == "mingw64" ]; then
    # Do something under Windows NT platform
    echo "Configuring build for MINGW64.."
    BOOST_ROOT=/mingw64/boost
    cmake -D CMAKE_BUILD_TYPE=$CMAKE_BUILD_TYPE -D STATIC=ON -D BOOST_ROOT="$BOOST_ROOT" -D ARCH="x86-64" -D BUILD_GUI_DEPS=ON -D INSTALL_VENDORED_LIBUNBOUND=ON -D CMAKE_INSTALL_PREFIX="$SEVABIT_DIR" -G "MSYS Makefiles" ../..

## Windows 32
elif [ "$platform" == "mingw32" ]; then
    # Do something under Windows NT platform
    echo "Configuring build for MINGW32.."
    BOOST_ROOT=/mingw32/boost
    cmake -D CMAKE_BUILD_TYPE=$CMAKE_BUILD_TYPE -D STATIC=ON -D Boost_DEBUG=ON -D BOOST_ROOT="$BOOST_ROOT" -D ARCH="i686" -D BUILD_64=OFF -D BUILD_GUI_DEPS=ON -D INSTALL_VENDORED_LIBUNBOUND=ON -D CMAKE_INSTALL_PREFIX="$SEVABIT_DIR" -G "MSYS Makefiles" ../..
    make_exec="mingw32-make"
else
    echo "Unknown platform, configuring general build"
    if [ "$STATIC" == true ]; then
        cmake -D CMAKE_BUILD_TYPE=$CMAKE_BUILD_TYPE -D STATIC=ON -D BUILD_GUI_DEPS=ON -D CMAKE_INSTALL_PREFIX="$SEVABIT_DIR"  ../..
    else
        cmake -D CMAKE_BUILD_TYPE=$CMAKE_BUILD_TYPE -D BUILD_GUI_DEPS=ON -D CMAKE_INSTALL_PREFIX="$SEVABIT_DIR"  ../..
    fi
fi

# set CPU core count
# thanks to SO: http://stackoverflow.com/a/20283965/4118915
if test -z "$CPU_CORE_COUNT"; then
  CPU_CORE_COUNT=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || sysctl -n hw.ncpu)
fi

# Build libwallet_merged
pushd $SEVABIT_DIR/build/$BUILD_TYPE/src/wallet
eval $make_exec version -C ../..
eval $make_exec  -j$CPU_CORE_COUNT
eval $make_exec  install -j$CPU_CORE_COUNT
popd

# Build lokid
# win32 need to build daemon manually with msys2 toolchain
if [ "$platform" != "mingw32" ] && [ "$ANDROID" != true ]; then
    pushd $SEVABIT_DIR/build/$BUILD_TYPE/src/daemon
    eval make  -j$CPU_CORE_COUNT
    eval make install -j$CPU_CORE_COUNT
    popd
fi

# build install epee
eval make -C $SEVABIT_DIR/build/$BUILD_TYPE/contrib/epee all install

# install easylogging
eval make -C $SEVABIT_DIR/build/$BUILD_TYPE/external/easylogging++ all install

# install lmdb
eval make -C $SEVABIT_DIR/build/$BUILD_TYPE/external/db_drivers/liblmdb all install

# Install libunbound
echo "Installing libunbound..."
pushd $SEVABIT_DIR/build/$BUILD_TYPE/external/unbound
# no need to make, it was already built as dependency for libwallet
# make -j$CPU_CORE_COUNT
$make_exec install -j$CPU_CORE_COUNT
popd


popd
