# avoid conflicts with meta-clang
TOOLCHAIN = "gcc"

DEPENDS:append = " swift-native glibc gcc libgcc"
EXTRANATIVEPATH:append = " swift-tools"

python() {
    # Set UNPACKDIR to WORKDIR for Yocto versions older than Styhead
    if d.getVar('UNPACKDIR') is None:
        d.setVar('UNPACKDIR', d.getVar('WORKDIR'))
}

python () {
    # Determine SWIFT_GCC_VERSION by examining bitbake's context dictionary key
    # RECIPE_MAINTAINER:pn-gcc-source-<version>
    gcc_src_maint_pkg = [x for x in d if x.startswith("RECIPE_MAINTAINER:pn-gcc-source-")][0]
    gcc_ver = gcc_src_maint_pkg.rpartition("-")[2]

    d.setVar("SWIFT_GCC_VERSION", gcc_ver)
}

SWIFT_CLANG_VERSION = "21"

SWIFT_TARGET_NAME = "${@oe.utils.conditional('TARGET_ARCH', 'arm', 'armv7-unknown-linux-gnueabihf', '${TARGET_ARCH}-unknown-linux-gnu', d)}"
SWIFT_TARGET_ARCH = "${@oe.utils.conditional('TARGET_ARCH', 'arm', 'armv7', '${TARGET_ARCH}', d)}"
TARGET_CPU_NAME = "${@oe.utils.conditional('TARGET_ARCH', 'arm', 'armv7-a', '${TARGET_ARCH}', d)}"

BUILD_MODE = "${@['release', 'debug'][d.getVar('DEBUG_BUILD') == '1']}"

# True when building a multilib image with 64-bit target userspace (lib32 present
# for 32-bit compat only). Swift target packages are 64-bit only in this mode.
MULTILIB_BUILD = "${@bb.utils.contains('MULTILIBS', 'multilib:lib32', 'true', 'false', d)}"

swift_multilib_prepare_sysroot() {
    if [ "${MULTILIB_BUILD}" != "true" ]; then
        return
    fi

    # Swift/CMake hard-code /usr/lib/swift. On multilib aarch64 the runtime is
    # under usr/${baselib}/swift, while usr/lib already exists as a real dir.
    # yocto uses ${libdir} to refer to usr/${baselib} and ${nonarch_libdir} to refer to /usr/lib.
    swift_src="${STAGING_DIR_TARGET}/${libdir}/swift"
    lib_swift="${STAGING_DIR_TARGET}/${nonarch_libdir}/swift"
    if [ -d "${swift_src}" ]; then
        mkdir -p "${STAGING_DIR_TARGET}/${nonarch_libdir}"
        rm -rf "${lib_swift}"
        ln -sf "../${baselib}/swift" "${lib_swift}"
    elif [ ! -e "${STAGING_DIR_TARGET}/${nonarch_libdir}" ]; then
        ln -s "${baselib}" "${STAGING_DIR_TARGET}/${nonarch_libdir}"
    fi

    # Linker isn't finding crtbeginS.o and crtendS.o under ${TARGET_SYS} path.
    if [ -d "${STAGING_DIR_TARGET}/${libdir}/${TARGET_SYS}" ]; then
        cp -r ${STAGING_DIR_TARGET}/${libdir}/${TARGET_SYS}/*/* ${STAGING_DIR_TARGET}/${libdir}/ 2>/dev/null || true
    fi
}

swift_multilib_install_fixup() {
    if [ "${MULTILIB_BUILD}" != "true" ]; then
        return
    fi

    if [ ! -d "${D}/${nonarch_libdir}" ]; then
        return
    fi

    # CMake/Swift often install under hard-coded usr/lib while other artifacts
    # land in usr/${baselib}; merge so FILES:${PN} paths match ${libdir}.
    if [ ! -d "${D}/${libdir}" ]; then
        mv "${D}/${nonarch_libdir}" "${D}/${libdir}"
    else
        cp -a "${D}/${nonarch_libdir}/." "${D}/${libdir}/"
        rm -rf "${D}/${nonarch_libdir}"
    fi
}

inherit swift-target-tune
