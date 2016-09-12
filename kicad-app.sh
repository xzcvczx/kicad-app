#!/bin/sh

# -----
# Options
# -----
THREADS=5
OSX_SDK_VER=10.11

BASE=`pwd`
COMPILER=clang

WX_SRC_URL="http://downloads.sourceforge.net/project/wxpython/wxPython/3.0.2.0/wxPython-src-3.0.2.0.tar.bz2"
WX_SRC_NAME=wxPython-src-3.0.2.0.tar.bz2

KICAD_GIT=https://git.launchpad.net/kicad
I18N_GIT=https://github.com/KiCad/kicad-i18n.git
LIBRARY_GIT=https://github.com/KiCad/kicad-library.git

KICAD_SRC=kicad
I18N_DIR=i18n
LIBRARY_DIR=library

KICAD_BUILD_DIR=build

KICAD_BIN=bin
SUPPORT_BIN=support

KICAD_SETTINGS=(
    "-DDEFAULT_INSTALL_PATH=/Library/Application Support/kicad"
    "-DCMAKE_OSX_DEPLOYMENT_TARGET=$OSX_SDK_VER"
    "-DwxWidgets_CONFIG_EXECUTABLE=$BASE/wx/bin/bin/wx-config"
    "-DPYTHON_SITE_PACKAGE_PATH=$BASE/wx/bin/lib/python2.7/site-packages"
    "-DCMAKE_INSTALL_PREFIX=$BASE/bin"
    "-DCMAKE_BUILD_TYPE=Release"
    "-DUSE_SCH_IO_MANAGER=ON"
    "-DKICAD_SPICE=ON"
    "-DKICAD_USE_OCE=ON"
    "-DOCE_DIR=$(brew --prefix oce)/OCE.framework/Versions/0.17/Resources/"
    "-DKICAD_SCRIPTING=ON"
    "-DKICAD_SCRIPTING_MODULES=ON"
    "-DKICAD_SCRIPTIN_WXPYTHON=ON"
    "-DPYTHON_EXECUTABLE=$(which python)"
)
# -----
# End Options
# -----

check_compiler() {
    printf "Checking for Compiler... "
    if !(which cc > /dev/null); then
        printf "Unable to find a compiler. Install a compiler and try again\n"
        exit 1
    else
        printf "${COMPILER}\n"
    fi
}

check_deps() {
    printf "Checking for Brew... "
    if !(which brew > /dev/null); then
        printf "Unable to find Brew. See http://brew.sh to install\n"
    else
        printf "Done\n"
    fi
    printf "Checking Dependencies... "
    if ! brew list gettext cmake glew cairo glm automake libtool oce libngspice> /dev/null; then
        printf "Run brew install boost gettext cmake glew cairo glm automake libtool homebrew/science/oce libngspice\n"
        exit 1
    else
        printf "Done\n"
    fi
}

check_wx() {
    cd wx
    printf "Fetching wxPython... "
    if [ ! -f $WX_SRC_NAME ]; then
        printf "Downloading $WX_SRC_NAME"
        curl -L -o $WX_SRC_NAME $WX_SRC_URL
    else
        printf "Done\n"
    fi
    
    printf "Extracting wxWidgets... "
    if [ ! -d src ]; then
        mkdir src
        cd src
        tar xf ../$WX_SRC_NAME --strip-components 1
        
        patch -p0 < ../patches/wxwidgets-3.0.0_macosx.patch || exit 1
		patch -p0 < ../patches/wxwidgets-3.0.0_macosx_bug_15908.patch || exit 1 
		patch -p0 < ../patches/wxwidgets-3.0.0_macosx_soname.patch || exit 1
		patch -p0 < ../patches/wxwidgets-3.0.2_macosx_yosemite.patch || exit 1
		patch -p0 < ../patches/wxwidgets-3.0.0_macosx_scrolledwindow.patch || exit 1
		patch -p0 < ../patches/wxwidgets-3.0.2_macosx_retina_opengl.patch || exit 1
		patch -p0 < ../patches/wxwidgets-3.0.2_macosx_magnify_event.patch || exit 1
        
        cd ..
    else
        printf "Done\n"
    fi
    
    printf "Building wxWidgets... "
    if [ ! -d build ]; then
        mkdir build
        cd build
        export MAC_OS_X_VERSION_MIN_REQUIRED=$OSX_SDK_VER
        ../src/configure \
            --prefix=`pwd`/../bin \
            --with-opengl \
            --enable-aui \
            --enable-utf8 \
            --enable-html \
            --enable-stl \
            --enable-monolithic \
            --with-libjpeg=builtin \
            --with-libpng=builtin \
            --with-regex=builtin \
            --with-libtiff=builtin \
            --with-zlib=builtin \
            --with-expat=builtin \
            --without-liblzma \
            --with-macosx-version-min=$OSX_SDK_VER
        cd ..
    fi

    if [ ! -d bin ]; then
        cd build
        make -j$THREADS
        if [ $? == 0 ]; then
            mkdir ../bin
            make install
            cd ..
        else 
            cd ..
            exit 1
        fi
    else
        printf "Done\n"
    fi

    printf "Building wxPython... "
    if [ ! -d bin/lib/python2.7/site-packages ]; then
        cd src/wxPython
        export MAC_OSX_VERSION_MIN_REQUIRED=$OSX_SDK_VER
        WXPYTHON_BUILD_OPTS="WX_CONFIG=`pwd`/../../bin/bin/wx-config \
            BUILD_BASE=`pwd`/../../build \
            UNICODE=1 \
            WXPORT=osx_cocoa"
            
        WXPYTHON_PREFIX="--prefix=`pwd`/../../bin"
        python setup.py build_ext $WXPYTHON_BUILD_OPTS
        if [ $? == 0 ]; then
            python setup.py install $WXPYTHON_PREFIX $WXPYTHON_BUILD_OPTS
        else
            cd ../../
            exit 1
        fi
        cd ../../
    else
        printf "Done\n"
    fi

    cd ..
}

# Kicad
kicad_update() {
    if [ ! -d $KICAD_SRC ]; then
        git clone $KICAD_GIT $KICAD_SRC
    else 
        git -C $KICAD_SRC checkout
        git -C $KICAD_SRC pull
    fi
}

kicad_patch() {
    if [ -e $BASE/notes/kicad_patches ]; then
        rm $BASE/notes/kicad_patches
    fi
    
    if [ -e $BASE/kicad_patches ]; then
        for patch in `find $BASE/kicad_patches -type f -name \*.patch`; do
            echo "Applying $patch"
            patch -d $SRC -p0 < $patch
            echo "`basename $patch`" >> $BASE/notes/kicad_patches
        done
    fi
}

kicad_build() {
    if [ ! -d $KICAD_SRC ]; then
        git clone $KICAD_GIT $KICAD_SRC
    fi

    if [ ! -d $KICAD_BUILD_DIR ]; then
        mkdir $KICAD_BUILD_DIR
        cd $KICAD_BUILD_DIR
        cmake "${KICAD_SETTINGS[@]}" ../$KICAD_SRC
        cd ..
    fi

    cd $KICAD_BUILD_DIR
    make -j$THREADS

    if [ -d ../$KICAD_BIN ]; then
        rm -r ../$KICAD_BIN
    fi
    make install

    cd ..
}

kicad_rebuild() {
    if [ -d $KICAD_BUILD_DIR ]; then
        rm -r $KICAD_BUILD_DIR
    fi

    kicad_build
}

i18n_update() {
    if [ ! -d $I18N_DIR ]; then
        mkdir $I18N_DIR
    fi

    cd $I18N_DIR

    if [ ! -d src ]; then
        git clone $I18N_GIT src
    else
        git -C src checkout
        git -C src pull
    fi

    cd -
}

i18n_build() {
    if [ ! -d $I18N_DIR ]; then
        mkdir $I18N_DIR
    fi

    cd $I18N_DIR
    #Fetch
    if [ ! -d src ]; then
        git clone $I18N_GIT src
    fi

    #build
    mkdir -p build
    cd build

    if [ -d ../bin ]; then
        rm -r ../bin
    fi
    mkdir -p ../bin
    cmake -DCMAKE_INSTALL_PREFIX=../bin \
          -DKICAD_I18N_PATH=../bin/internat \
          -DGETTEXT_MSGMERGE_EXECUTABLE=$(brew --prefix gettext)/bin/msgmerge \
          -DGETTEXT_MSGFMT_EXECUTABLE=$(brew --prefix gettext)/bin/msgfmt \
          ../src
    make install

    cd -
}

# Symbols/3d models
library_update() {
    if [ ! -d $LIBRARY_DIR ]; then
        mkdir $LIBRARY_DIR
    fi

    cd $LIBRARY_DIR

    if [ ! -d src ]; then
        git clone $LIBRARY_GIT src
    else
        git -C src checkout
        git -C src pull
    fi

    cd -
}

library_build() {
    if [ ! -d $LIBRARY_DIR ]; then
        mkdir $LIBRARY_DIR
    fi

    cd $LIBRARY_DIR

    if [ ! -d src ]; then
        git clone $LIBRARY_GIT src
    fi

    mkdir -p build
    cd build

    if [ -d ../bin ]; then
        rm -r ../bin
    fi
    mkdir -p ../bin
    cmake -DCMAKE_INSTALL_PREFIX=../bin ../src
    make install

    cd -
}

package_kicad() {
    echo "TODO"
}

clean() {
    for folder in notes $KICAD_BUILD $KICAD_BIN $I18N_BUILD $SUPPORT_BIN; do
        rm -r $folder
    done
}

print_help() {
    echo "Usage: $0 [-h] [command ...]"
    echo
    echo "Options"
    echo "  -h - Help"
    #echo "  -b - Git Branch to use"
    echo
    echo "Commands"
    echo "  check_compiler - Check that a c compiler is installed"
    echo "  check_deps - Check that brew requirements are installed"
    echo "  check_wx - Fetch, Patch and Build wxwidgets"
    echo "  kicad_fetch - Fetch or update the kicad sourcecode tree"
    echo "  kicad_build - Build kicad"
    echo "  kicad_rebuild - Fresh build of kicad"
    echo "  i18n_update - Update i18n tree"
    echo "  i18n_build - Build i18n"
    echo "  library_update - update schematic symbols and 3d models"
    echo "  library_build - build schematic symbols and 3d models"
    echo
}

while getopts ":hb:" opt; do
    case $opt in
        b)
            echo "Branch $OPTARG"
            ;;
        h)
            print_help
            exit 0
            ;;
        \?)
            echo "Usage: $0 [-h] [command ...]"
            exit 2
            ;;
    esac
done
shift $(expr $OPTIND - 1 )

if [ $# -eq 0 ]; then
    echo check_compiler
    echo check_deps
    echo check_wx
    echo kicad_fetch
    echo kicad_build
else
    while [ $# -gt 0 ]; do
        if [[ $(type -t $1) == function ]]; then
            $1
        else
            echo "Unknown Command: $1"
            echo "See -h for help"
            echo
        fi
        shift
    done
fi
