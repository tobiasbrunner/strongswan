#!/bin/sh
# Build script for Travis CI

if test -z $TRAVIS_BUILD_DIR; then
	TRAVIS_BUILD_DIR=$PWD
fi

cd $TRAVIS_BUILD_DIR

TARGET=check

DEPS="libgmp-dev"

CFLAGS="-g -O2 -Wall -Wno-format -Wno-format-security -Wno-pointer-sign -Werror"

case "$TEST" in
default)
	# should be the default, but lets make sure
	CONFIG="--with-printf-hooks=glibc"
	;;
openssl)
	CONFIG="--disable-defaults --enable-pki --enable-openssl"
	DEPS="libssl-dev"
	;;
gcrypt)
	CONFIG="--disable-defaults --enable-pki --enable-gcrypt --enable-pkcs1"
	DEPS="libgcrypt11-dev"
	;;
printf-builtin)
	CONFIG="--with-printf-hooks=builtin"
	;;
all)
	CONFIG="--enable-all --disable-android-dns --disable-android-log
			--disable-dumm --disable-kernel-pfroute --disable-keychain
			--disable-lock-profiler --disable-maemo --disable-padlock
			--disable-osx-attr --disable-tkm --disable-uci
			--disable-systemd --disable-soup --disable-unwind-backtraces
			--disable-svc --disable-dbghelp-backtraces --disable-socket-win
			--disable-kernel-wfp --disable-kernel-iph --disable-winhttp"
	if test "$MONOLITHIC" = "yes"; then
		# Ubuntu 12.04 does not provide a proper -liptc pkg-config
		CONFIG="$CONFIG --disable-forecast --disable-connmark"
	fi
	# Ubuntu 12.04 does not provide libtss2-dev
	CONFIG="$CONFIG --disable-aikpub2 --disable-tss-tss2"
	# not enabled on the build server
	CONFIG="$CONFIG --disable-af-alg"
	# TODO: enable? perhaps via coveralls.io (cpp-coveralls)?
	CONFIG="$CONFIG --disable-coverage"
	DEPS="$DEPS libcurl4-gnutls-dev libsoup2.4-dev libunbound-dev libldns-dev
		  libmysqlclient-dev libsqlite3-dev clearsilver-dev libfcgi-dev
		  libnm-glib-dev libnm-glib-vpn-dev libpcsclite-dev libpam0g-dev
		  binutils-dev libunwind7-dev libjson0-dev iptables-dev python-pip
		  libtspi-dev"
	PYDEPS="pytest"
	;;
win*)
	CONFIG="--disable-defaults --enable-svc --enable-ikev2
			--enable-ikev1 --enable-static --enable-test-vectors --enable-nonce
			--enable-constraints --enable-revocation --enable-pem --enable-pkcs1
			--enable-pkcs8 --enable-x509 --enable-pubkey --enable-acert
			--enable-eap-tnc --enable-eap-ttls --enable-eap-identity
			--enable-updown --enable-ext-auth
			--enable-tnccs-20 --enable-imc-attestation --enable-imv-attestation
			--enable-imc-os --enable-imv-os --enable-tnc-imv --enable-tnc-imc
			--enable-pki --enable-swanctl --enable-socket-win"
	# no make check for Windows binaries
	TARGET=
	CFLAGS="$CFLAGS -mno-ms-bitfields"
	DEPS="gcc-mingw-w64-base mingw-w64-dev"
	case "$TEST" in
	win64)
		CONFIG="--host=x86_64-w64-mingw32 $CONFIG"
		DEPS="gcc-mingw-w64-x86-64 binutils-mingw-w64-x86-64 $DEPS"
		CC="x86_64-w64-mingw32-gcc"
		;;
	win32)
		CONFIG="--host=i686-w64-mingw32 $CONFIG"
		DEPS="gcc-mingw-w64-i686 binutils-mingw-w64-i686 $DEPS"
		CC="i686-w64-mingw32-gcc"
		;;
	esac
	;;
osx)
	# use the same options as in the Homebrew Formula
	CONFIG="--disable-defaults --enable-charon --enable-cmd --enable-constraints
			--enable-curl --enable-eap-gtc --enable-eap-identity
			--enable-eap-md5 --enable-eap-mschapv2 --enable-ikev1 --enable-ikev2
			--enable-kernel-libipsec --enable-kernel-pfkey
			--enable-kernel-pfroute --enable-nonce --enable-openssl
			--enable-osx-attr --enable-pem --enable-pgp --enable-pkcs1
			--enable-pkcs8 --enable-pki --enable-pubkey --enable-revocation
			--enable-scepclient --enable-socket-default --enable-sshkey
			--enable-stroke --enable-swanctl --enable-unity --enable-updown
			--enable-x509 --enable-xauth-generic"
	DEPS="bison gettext openssl curl"
	BREW_PREFIX=$(brew --prefix)
	export PATH=$BREW_PREFIX/opt/bison/bin:$PATH
	export ACLOCAL_PATH=$BREW_PREFIX/opt/gettext/share/aclocal:$ACLOCAL_PATH
	for pkg in openssl curl
	do
		PKG_CONFIG_PATH=$BREW_PREFIX/opt/$PKG/lib/pkgconfig:$PKG_CONFIG_PATH
		CPPFLAGS="-I$BREW_PREFIX/opt/$pkg/include $CPPFLAGS"
		LDFLAGS="-L$BREW_PREFIX/opt/$pkg/lib $LDFLAGS"
	done
	export PKG_CONFIG_PATH
	export CPPFLAGS
	export LDFLAGS
	;;
dist)
	TARGET=distcheck
	;;
*)
	echo "$0: unknown test $TEST" >&2
	exit 1
	;;
esac

if test "$1" = "deps"; then
	case "$TRAVIS_OS_NAME" in
	linux)
		sudo apt-get update -qq && \
		sudo apt-get install -qq bison flex gperf gettext gdb $DEPS
		;;
	osx)
		brew update && \
		brew install $DEPS
		;;
	esac
	exit $?
fi

if test "$1" = "pydeps"; then
	test -z "$PYDEPS" || sudo pip -q install $PYDEPS
	exit $?
fi

CONFIG="$CONFIG
	--disable-dependency-tracking
	--enable-silent-rules
	--enable-test-vectors
	--enable-monolithic=${MONOLITHIC-no}
	--enable-leak-detective=${LEAK_DETECTIVE-no}"

get_backtrace() {
	RUNNER=`pidof lt-tests | cut -f 1 -d ' '`
	if test -n "$RUNNER"; then
		echo
		echo "### BACKTRACE OF TEST RUNNER ###"
		echo
		sudo gdb -batch -quiet -ex "thread apply all bt full" -ex "quit" -p $RUNNER
		echo
		echo "################################"
	fi
}
trap get_backtrace 14

# trigger backtrace after 9 minutes (travis stops after 10 min without output)
sleep 540 && kill -s 14 $$ &
TIMER=$!

echo "$ ./autogen.sh"
./autogen.sh || exit $?
echo "$ CC=$CC CFLAGS=\"$CFLAGS\" ./configure $CONFIG && make $TARGET"
CC="$CC" CFLAGS="$CFLAGS" ./configure $CONFIG && make -j4 $TARGET && kill $TIMER &
wait $!
