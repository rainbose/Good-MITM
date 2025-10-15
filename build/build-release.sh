#!/bin/bash

CUR_DIR=$( cd $( dirname $0 ) && pwd )
VERSION=$(grep -E '^version' ${CUR_DIR}/../Cargo.toml | awk '{print $3}' | sed 's/"//g')

## Disable macos ACL file
if [[ "$(uname -s)" == "Darwin" ]]; then
    export COPYFILE_DISABLE=1
fi

targets=()
features=()
use_upx=false

while getopts "t:f:u" opt; do
    case $opt in
        t)
            targets+=($OPTARG)
            ;;
        f)
            features+=($OPTARG)
            ;;
        u)
            use_upx=true
            ;;
        ?)
            echo "Usage: $(basename $0) [-t <target-triple>] [-f features] [-u]"
            ;;
    esac
done

features+=${EXTRA_FEATURES}

if [[ "${#targets[@]}" == "0" ]]; then
    echo "Specifying compile target with -t <target-triple>"
    exit 1
fi

if [[ "${use_upx}" = true ]]; then
    if [[ -z "$upx" ]] && command -v upx &> /dev/null; then
        upx="upx -9"
    fi

    if [[ "x$upx" == "x" ]]; then
        echo "Couldn't find upx in PATH, consider specifying it with variable \$upx"
        exit 1
    fi
fi


function build() {
    cd "$CUR_DIR/.."

    TARGET=$1

    RELEASE_DIR="target/${TARGET}/release"
    TARGET_FEATURES="${features[@]}"

    # 检测是否需要交叉编译
    # 获取当前主机架构
    HOST_ARCH=$(rustc -Vv | grep 'host:' | awk '{print $2}')

    # 如果目标平台与主机相同，使用 cargo；否则使用 cross
    if [[ "$TARGET" == "$HOST_ARCH" ]] || [[ "$TARGET" == "x86_64-unknown-linux-gnu" && "$HOST_ARCH" == "x86_64"* ]]; then
        BUILD_CMD="cargo"
        echo "* Using native cargo for ${TARGET}"
    else
        BUILD_CMD="cross"
        echo "* Using cross for ${TARGET}"
    fi

    if [[ "${TARGET_FEATURES}" != "" ]]; then
        echo "* Building ${TARGET} package ${VERSION} with features \"${TARGET_FEATURES}\" ..."

        $BUILD_CMD build --target "${TARGET}" \
                    --features "${TARGET_FEATURES}" \
                    --release
    else
        echo "* Building ${TARGET} package ${VERSION} ..."

        $BUILD_CMD build --target "${TARGET}" \
                    --release
    fi

    if [[ $? != "0" ]]; then
        exit 1
    fi

    PKG_DIR="${CUR_DIR}/release"
    mkdir -p "${PKG_DIR}"

    if [[ "$TARGET" == *"-linux-"* ]]; then
        PKG_NAME="good-mitm-${VERSION}-${TARGET}.tar.xz"
        PKG_PATH="${PKG_DIR}/${PKG_NAME}"

        cd ${RELEASE_DIR}

        if [[ "${use_upx}" = true ]]; then
            # Enable upx for MIPS.
            $upx good-mitm #>/dev/null
        fi

        echo "* Packaging XZ in ${PKG_PATH} ..."
        tar -cJf ${PKG_PATH} "good-mitm"

        if [[ $? != "0" ]]; then
            exit 1
        fi

        cd "${PKG_DIR}"
        shasum -a 256 "${PKG_NAME}" > "${PKG_NAME}.sha256"
    elif [[ "$TARGET" == *"-windows-"* ]]; then
        PKG_NAME="good-mitm-${VERSION}-${TARGET}.zip"
        PKG_PATH="${PKG_DIR}/${PKG_NAME}"

        echo "* Packaging ZIP in ${PKG_PATH} ..."
        cd ${RELEASE_DIR}
        zip ${PKG_PATH} "good-mitm.exe"

        if [[ $? != "0" ]]; then
            exit 1
        fi

        cd "${PKG_DIR}"
        shasum -a 256 "${PKG_NAME}" > "${PKG_NAME}.sha256"
    fi

    echo "* Done build package ${PKG_NAME}"
}

for target in "${targets[@]}"; do
    build "$target";
done
