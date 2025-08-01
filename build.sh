#!/bin/bash

rm -r web build 2>/dev/null
appName="alist"
builtAt="$(date +'%F %T %z')"
gitAuthor="Xhofe <i@nn.ci>"
gitCommit=$(git log --pretty=format:"%h" -1)
if [ "$1" = "dev" ]; then
  version="dev"
  webVersion="dev"
elif [ "$1" = "beta" ]; then
  version="beta"
  webVersion="dev"
else
  version=$(curl -s https://api.github.com/repos/NodeSeekDev/nlist/tags | jq -r '.[0].name')
  webVersion=$(curl -s https://api.github.com/repos/NodeSeekDev/nlist-web/tags | jq -r '.[0].name')
fi

echo "backend version: $version"
echo "frontend version: $webVersion"

ldflags="\
-w -s \
-X 'github.com/NodeSeekDev/nlist/v3/internal/conf.BuiltAt=$builtAt' \
-X 'github.com/NodeSeekDev/nlist/v3/internal/conf.GitAuthor=$gitAuthor' \
-X 'github.com/NodeSeekDev/nlist/v3/internal/conf.GitCommit=$gitCommit' \
-X 'github.com/NodeSeekDev/nlist/v3/internal/conf.Version=$version' \
-X 'github.com/NodeSeekDev/nlist/v3/internal/conf.WebVersion=$webVersion' \
"

FetchWebDev() {
  curl -L https://codeload.github.com/alist-org/web-dist/tar.gz/refs/heads/dev -o web-dist-dev.tar.gz
  tar -zxvf web-dist-dev.tar.gz
  rm -rf public/dist
  mv -f web-dist-dev/dist public
  rm -rf web-dist-dev web-dist-dev.tar.gz
}

FetchWebRelease() {
  WEB_TAG=$(curl -s https://api.github.com/repos/NodeSeekDev/nlist-web/tags | jq -r '.[0].name')
  mkdir web
  git clone https://github.com/NodeSeekDev/nlist-web.git web
  cd web
  git fetch --tags
  git checkout -b "$WEB_TAG" "$WEB_TAG"
  git clone https://github.com/AlistGo/solid-router.git solid-router
  pnpm install
  pnpm run build
  cd ../
  rm -rf public/dist
  mv -f web/dist public
}

BuildWinArm64() {
  echo building for windows-arm64
  chmod +x ./wrapper/zcc-arm64
  chmod +x ./wrapper/zcxx-arm64
  export GOOS=windows
  export GOARCH=arm64
  export CC=$(pwd)/wrapper/zcc-arm64
  export CXX=$(pwd)/wrapper/zcxx-arm64
  export CGO_ENABLED=1
  go build -o "$1" -ldflags="$ldflags" -tags=jsoniter .
}

BuildDev() {
  rm -rf .git/
  mkdir -p "dist"
  muslflags="--extldflags '-static -fpic' $ldflags"
  BASE="https://musl.nn.ci/"
  FILES=(x86_64-linux-musl-cross aarch64-linux-musl-cross)
  OS_ARCHES=(linux-musl-amd64 linux-musl-arm64)
  CGO_ARGS=(x86_64-linux-musl-gcc aarch64-linux-musl-gcc)
  flag="false"
  if [ -n "$3" ] && [ -n "$4" ]; then
    found_index=-1  # 初始化为 -1，表示未找到
    for i in "${!OS_ARCHES[@]}"; do
      if [ "${OS_ARCHES[$i]}" = "$3" ] && [ "${CGO_ARGS[$i]}" = "$4" ]; then
        found_index=$i  # 找到匹配的索引
        break  # 只取第一个匹配
      fi
    done

    if [ "$found_index" -ne -1 ]; then
      # 找到匹配，只构建这一个版本
      i=$found_index
      os_arch=${OS_ARCHES[$i]}
      cgo_cc=${CGO_ARGS[$i]}
      file_name=${FILES[$i]}
      url="${BASE}${file_name}.tgz"
      curl -L -o "${file_name}.tgz" "${url}"
      sudo tar xf "${file_name}.tgz" --strip-components 1 -C /usr/local
      rm -f "${file_name}.tgz"
      echo "Found matching index $i, building only for ${os_arch}"
      export GOOS=${os_arch%%-*}
      export GOARCH=${os_arch##*-}
      export CC=${cgo_cc}
      export CGO_ENABLED=1
      go build -o ./build/$appName-$os_arch -ldflags="$muslflags" -tags=jsoniter .
      flag="true"
    else
      echo "No matching entry found for $3, $4. Building all versions."
    fi
  else
    echo "Parameters $3, $4 not all provided. Building all versions."
  fi

  if flag = "false"; then
    for i in "${!OS_ARCHES[@]}"; do
      os_arch=${OS_ARCHES[$i]}
      cgo_cc=${CGO_ARGS[$i]}
      file_name=${FILES[$i]}
      url="${BASE}${file_name}.tgz"
      curl -L -o "${file_name}.tgz" "${url}"
      sudo tar xf "${file_name}.tgz" --strip-components 1 -C /usr/local
      rm -f "${file_name}.tgz"
      echo building for ${os_arch}
      export GOOS=${os_arch%%-*}
      export GOARCH=${os_arch##*-}
      export CC=${cgo_cc}
      export CGO_ENABLED=1
      go build -o ./build/$appName-$os_arch -ldflags="$muslflags" -tags=jsoniter .
    done
  fi  
  xgo -targets=windows/amd64,darwin/amd64,darwin/arm64 -out "$appName" -ldflags="$ldflags" -tags=jsoniter .
  mv alist-* dist
  cd dist
  cp ./alist-windows-amd64.exe ./alist-windows-amd64-upx.exe
  upx -9 ./alist-windows-amd64-upx.exe
  find . -type f -print0 | xargs -0 md5sum >md5.txt
  cat md5.txt
}

BuildDocker() {
  go build -o ./bin/alist -ldflags="$ldflags" -tags=jsoniter .
}

PrepareBuildDockerMusl() {
  mkdir -p build/musl-libs
  BASE="https://musl.cc/"
  FILES=(x86_64-linux-musl-cross aarch64-linux-musl-cross i486-linux-musl-cross s390x-linux-musl-cross armv6-linux-musleabihf-cross armv7l-linux-musleabihf-cross riscv64-linux-musl-cross powerpc64le-linux-musl-cross)
  for i in "${FILES[@]}"; do
    url="${BASE}${i}.tgz"
    lib_tgz="build/${i}.tgz"
    curl -L -o "${lib_tgz}" "${url}"
    tar xf "${lib_tgz}" --strip-components 1 -C build/musl-libs
    rm -f "${lib_tgz}"
  done
}

BuildDockerMultiplatform() {
  go mod download

  # run PrepareBuildDockerMusl before build
  export PATH=$PATH:$PWD/build/musl-libs/bin

  docker_lflags="--extldflags '-static -fpic' $ldflags"
  export CGO_ENABLED=1

  OS_ARCHES=(linux-amd64 linux-arm64 linux-386 linux-s390x linux-riscv64 linux-ppc64le)
  CGO_ARGS=(x86_64-linux-musl-gcc aarch64-linux-musl-gcc i486-linux-musl-gcc s390x-linux-musl-gcc riscv64-linux-musl-gcc powerpc64le-linux-musl-gcc)
  for i in "${!OS_ARCHES[@]}"; do
    os_arch=${OS_ARCHES[$i]}
    cgo_cc=${CGO_ARGS[$i]}
    os=${os_arch%%-*}
    arch=${os_arch##*-}
    export GOOS=$os
    export GOARCH=$arch
    export CC=${cgo_cc}
    echo "building for $os_arch"
    go build -o build/$os/$arch/alist -ldflags="$docker_lflags" -tags=jsoniter .
  done

  DOCKER_ARM_ARCHES=(linux-arm/v6 linux-arm/v7)
  CGO_ARGS=(armv6-linux-musleabihf-gcc armv7l-linux-musleabihf-gcc)
  GO_ARM=(6 7)
  export GOOS=linux
  export GOARCH=arm
  for i in "${!DOCKER_ARM_ARCHES[@]}"; do
    docker_arch=${DOCKER_ARM_ARCHES[$i]}
    cgo_cc=${CGO_ARGS[$i]}
    export GOARM=${GO_ARM[$i]}
    export CC=${cgo_cc}
    echo "building for $docker_arch"
    go build -o build/${docker_arch%%-*}/${docker_arch##*-}/alist -ldflags="$docker_lflags" -tags=jsoniter .
  done
}

BuildRelease() {
  rm -rf .git/
  mkdir -p "build"
  BuildWinArm64 ./build/alist-windows-arm64.exe
  xgo -out "$appName" -ldflags="$ldflags" -tags=jsoniter .
  # why? Because some target platforms seem to have issues with upx compression
  upx -9 ./alist-linux-amd64
  cp ./alist-windows-amd64.exe ./alist-windows-amd64-upx.exe
  upx -9 ./alist-windows-amd64-upx.exe
  mv alist-* build
}

BuildReleaseLinuxMusl() {
  rm -rf .git/
  mkdir -p "build"
  muslflags="--extldflags '-static -fpic' $ldflags"
  BASE="https://musl.nn.ci/"
  FILES=(x86_64-linux-musl-cross aarch64-linux-musl-cross mips-linux-musl-cross mips64-linux-musl-cross mips64el-linux-musl-cross mipsel-linux-musl-cross powerpc64le-linux-musl-cross s390x-linux-musl-cross)
  OS_ARCHES=(linux-musl-amd64 linux-musl-arm64 linux-musl-mips linux-musl-mips64 linux-musl-mips64le linux-musl-mipsle linux-musl-ppc64le linux-musl-s390x)
  CGO_ARGS=(x86_64-linux-musl-gcc aarch64-linux-musl-gcc mips-linux-musl-gcc mips64-linux-musl-gcc mips64el-linux-musl-gcc mipsel-linux-musl-gcc powerpc64le-linux-musl-gcc s390x-linux-musl-gcc)

  if [ -n "$3" ] && [ -n "$4" ]; then
    found_index=-1  # 初始化为 -1，表示未找到
    for i in "${!OS_ARCHES[@]}"; do
      if [ "${OS_ARCHES[$i]}" = "$3" ] && [ "${CGO_ARGS[$i]}" = "$4" ]; then
        found_index=$i  # 找到匹配的索引
        break  # 只取第一个匹配
      fi
    done

    if [ "$found_index" -ne -1 ]; then
      # 找到匹配，只构建这一个版本
      i=$found_index
      os_arch=${OS_ARCHES[$i]}
      cgo_cc=${CGO_ARGS[$i]}
      file_name=${FILES[$i]}
      url="${BASE}${file_name}.tgz"
      curl -L -o "${file_name}.tgz" "${url}"
      sudo tar xf "${file_name}.tgz" --strip-components 1 -C /usr/local
      rm -f "${file_name}.tgz"
      echo "Found matching index $i, building only for ${os_arch}"
      export GOOS=${os_arch%%-*}
      export GOARCH=${os_arch##*-}
      export CC=${cgo_cc}
      export CGO_ENABLED=1
      go build -o ./build/$appName-$os_arch -ldflags="$muslflags" -tags=jsoniter .
      return  
    else
      echo "No matching entry found for $3, $4. Building all versions."
    fi
  else
    echo "Parameters $3, $4 not all provided. Building all versions."
  fi

  for i in "${!OS_ARCHES[@]}"; do
    os_arch=${OS_ARCHES[$i]}
    cgo_cc=${CGO_ARGS[$i]}
    file_name=${FILES[$i]}
    url="${BASE}${file_name}.tgz"
    curl -L -o "${file_name}.tgz" "${url}"
    sudo tar xf "${file_name}.tgz" --strip-components 1 -C /usr/local
    rm -f "${file_name}.tgz"
    echo building for ${os_arch}
    export GOOS=${os_arch%%-*}
    export GOARCH=${os_arch##*-}
    export CC=${cgo_cc}
    export CGO_ENABLED=1
    go build -o ./build/$appName-$os_arch -ldflags="$muslflags" -tags=jsoniter .
  done
}

BuildReleaseLinuxMuslArm() {
  rm -rf .git/
  mkdir -p "build"
  muslflags="--extldflags '-static -fpic' $ldflags"
  BASE="https://musl.nn.ci/"
#  FILES=(arm-linux-musleabi-cross arm-linux-musleabihf-cross armeb-linux-musleabi-cross armeb-linux-musleabihf-cross armel-linux-musleabi-cross armel-linux-musleabihf-cross armv5l-linux-musleabi-cross armv5l-linux-musleabihf-cross armv6-linux-musleabi-cross armv6-linux-musleabihf-cross armv7l-linux-musleabihf-cross armv7m-linux-musleabi-cross armv7r-linux-musleabihf-cross)
  FILES=(arm-linux-musleabi-cross arm-linux-musleabihf-cross armel-linux-musleabi-cross armel-linux-musleabihf-cross armv5l-linux-musleabi-cross armv5l-linux-musleabihf-cross armv6-linux-musleabi-cross armv6-linux-musleabihf-cross armv7l-linux-musleabihf-cross armv7m-linux-musleabi-cross armv7r-linux-musleabihf-cross)
#  OS_ARCHES=(linux-musleabi-arm linux-musleabihf-arm linux-musleabi-armeb linux-musleabihf-armeb linux-musleabi-armel linux-musleabihf-armel linux-musleabi-armv5l linux-musleabihf-armv5l linux-musleabi-armv6 linux-musleabihf-armv6 linux-musleabihf-armv7l linux-musleabi-armv7m linux-musleabihf-armv7r)
#  CGO_ARGS=(arm-linux-musleabi-gcc arm-linux-musleabihf-gcc armeb-linux-musleabi-gcc armeb-linux-musleabihf-gcc armel-linux-musleabi-gcc armel-linux-musleabihf-gcc armv5l-linux-musleabi-gcc armv5l-linux-musleabihf-gcc armv6-linux-musleabi-gcc armv6-linux-musleabihf-gcc armv7l-linux-musleabihf-gcc armv7m-linux-musleabi-gcc armv7r-linux-musleabihf-gcc)
#  GOARMS=('' '' '' '' '' '' '5' '5' '6' '6' '7' '7' '7')
  OS_ARCHES=(linux-musleabi-arm linux-musleabihf-arm linux-musleabi-armel linux-musleabihf-armel linux-musleabi-armv5l linux-musleabihf-armv5l linux-musleabi-armv6 linux-musleabihf-armv6 linux-musleabihf-armv7l linux-musleabi-armv7m linux-musleabihf-armv7r)
  CGO_ARGS=(arm-linux-musleabi-gcc arm-linux-musleabihf-gcc armel-linux-musleabi-gcc armel-linux-musleabihf-gcc armv5l-linux-musleabi-gcc armv5l-linux-musleabihf-gcc armv6-linux-musleabi-gcc armv6-linux-musleabihf-gcc armv7l-linux-musleabihf-gcc armv7m-linux-musleabi-gcc armv7r-linux-musleabihf-gcc)
  GOARMS=('' '' '' '' '5' '5' '6' '6' '7' '7' '7')

  if [ -n "$3" ] && [ -n "$4" ] && [ -n "$5" ]; then
    found_index=-1  # 初始化为 -1，表示未找到
    for i in "${!OS_ARCHES[@]}"; do
      if [ "${OS_ARCHES[$i]}" = "$3" ] && [ "${CGO_ARGS[$i]}" = "$4" ] && [ "${GOARMS[$i]}" = "$5" ]; then
        found_index=$i  # 找到匹配的索引
        break  # 只取第一个匹配
      fi
    done

    if [ "$found_index" -ne -1 ]; then
      # 找到匹配，只构建这一个版本
      i=$found_index
      os_arch=${OS_ARCHES[$i]}
      cgo_cc=${CGO_ARGS[$i]}
      arm=${GOARMS[$i]}
      file_name=${FILES[$i]}
      url="${BASE}${file_name}.tgz"
      curl -L -o "${file_name}.tgz" "${url}"
      sudo tar xf "${file_name}.tgz" --strip-components 1 -C /usr/local
      rm -f "${file_name}.tgz"
      echo "Found matching index $i, building only for ${os_arch}"
      export GOOS=linux
      export GOARCH=arm
      export CC=${cgo_cc}
      export CGO_ENABLED=1
      export GOARM=${arm}
      go build -o ./build/$appName-$os_arch -ldflags="$muslflags" -tags=jsoniter .
      return  
    else
      echo "No matching entry found for $3, $4, $5. Building all versions."
    fi
  else
    echo "Parameters $3, $4, $5 not all provided. Building all versions."
  fi

  # 原 for 循环：构建所有版本（如果未匹配或参数不全）
  for i in "${!OS_ARCHES[@]}"; do
    os_arch=${OS_ARCHES[$i]}
    cgo_cc=${CGO_ARGS[$i]}
    arm=${GOARMS[$i]}
    file_name=${FILES[$i]}
    url="${BASE}${file_name}.tgz"
    curl -L -o "${file_name}.tgz" "${url}"
    sudo tar xf "${file_name}.tgz" --strip-components 1 -C /usr/local
    rm -f "${file_name}.tgz"
    echo building for ${os_arch}
    export GOOS=linux
    export GOARCH=arm
    export CC=${cgo_cc}
    export CGO_ENABLED=1
    export GOARM=${arm}
    go build -o ./build/$appName-$os_arch -ldflags="$muslflags" -tags=jsoniter .
  done
}


BuildReleaseAndroid() {
  rm -rf .git/
  mkdir -p "build"
  wget https://dl.google.com/android/repository/android-ndk-r26b-linux.zip
  unzip android-ndk-r26b-linux.zip
  rm android-ndk-r26b-linux.zip
  OS_ARCHES=(amd64 arm64 386 arm)
  CGO_ARGS=(x86_64-linux-android24-clang aarch64-linux-android24-clang i686-linux-android24-clang armv7a-linux-androideabi24-clang)

  # 新添加：如果 $3 $4 $5 全部提供了，检查是否匹配数组中的某一项
  if [ -n "$3" ] && [ -n "$4" ]; then
    found_index=-1  # 初始化为 -1，表示未找到
    for i in "${!OS_ARCHES[@]}"; do
      if [ "${OS_ARCHES[$i]}" = "$3" ] && [ "${CGO_ARGS[$i]}" = "$4" ]; then
        found_index=$i  # 找到匹配的索引
        break  # 只取第一个匹配
      fi
    done

    if [ "$found_index" -ne -1 ]; then
      # 找到匹配，只构建这一个版本
      i=$found_index
      os_arch=${OS_ARCHES[$i]}
      cgo_cc=${CGO_ARGS[$i]}
      echo "Found matching index $i, building only for ${os_arch}"
      export GOOS=android
      export GOARCH=${os_arch##*-}
      export CC=${cgo_cc}
      export CGO_ENABLED=1
      go build -o ./build/$appName-android-$os_arch -ldflags="$ldflags" -tags=jsoniter .
      android-ndk-r26b/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip ./build/$appName-android-$os_arch
      return  
    else
      echo "No matching entry found for $3, $4. Building all versions."
    fi
  else
    echo "Parameters $3, $4 not all provided. Building all versions."
  fi

  for i in "${!OS_ARCHES[@]}"; do
    os_arch=${OS_ARCHES[$i]}
    cgo_cc=$(realpath android-ndk-r26b/toolchains/llvm/prebuilt/linux-x86_64/bin/${CGO_ARGS[$i]})
    echo building for android-${os_arch}
    export GOOS=android
    export GOARCH=${os_arch##*-}
    export CC=${cgo_cc}
    export CGO_ENABLED=1
    go build -o ./build/$appName-android-$os_arch -ldflags="$ldflags" -tags=jsoniter .
    android-ndk-r26b/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip ./build/$appName-android-$os_arch
  done
}

BuildReleaseFreeBSD() {
  rm -rf .git/
  mkdir -p "build/freebsd"
  OS_ARCHES=(amd64 arm64 i386)
  GO_ARCHES=(amd64 arm64 386)
  CGO_ARGS=(x86_64-unknown-freebsd14.1 aarch64-unknown-freebsd14.1 i386-unknown-freebsd14.1)

  # 新添加：如果 $3 $4 $5 全部提供了，检查是否匹配数组中的某一项
  if [ -n "$3" ] && [ -n "$4" ] && [ -n "$5" ]; then
    found_index=-1  # 初始化为 -1，表示未找到
    for i in "${!OS_ARCHES[@]}"; do
      if [ "${OS_ARCHES[$i]}" = "$3" ] && [ "${CGO_ARGS[$i]}" = "$4" ] && [ "${CGO_ARGS[$i]}" = "$5" ]; then
        found_index=$i  # 找到匹配的索引
        break  # 只取第一个匹配
      fi
    done

    if [ "$found_index" -ne -1 ]; then
      # 找到匹配，只构建这一个版本
      i=$found_index
      os_arch=${OS_ARCHES[$i]}
      cgo_cc="clang --target=${CGO_ARGS[$i]} --sysroot=/opt/freebsd/${os_arch}"
      echo building for freebsd-${os_arch}
      sudo mkdir -p "/opt/freebsd/${os_arch}"
      wget -q https://download.freebsd.org/releases/${os_arch}/14.1-RELEASE/base.txz
      sudo tar -xf ./base.txz -C /opt/freebsd/${os_arch}
      rm base.txz
      export GOOS=freebsd
      export GOARCH=${GO_ARCHES[$i]}
      export CC=${cgo_cc}
      export CGO_ENABLED=1
      export CGO_LDFLAGS="-fuse-ld=lld"
      go build -o ./build/$appName-freebsd-$os_arch -ldflags="$ldflags" -tags=jsoniter .
      return  
    else
      echo "No matching entry found for $3, $4, $5. Building all versions."
    fi
  else
    echo "Parameters $3, $4, $5 not all provided. Building all versions."
  fi

  for i in "${!OS_ARCHES[@]}"; do
    os_arch=${OS_ARCHES[$i]}
    cgo_cc="clang --target=${CGO_ARGS[$i]} --sysroot=/opt/freebsd/${os_arch}"
    echo building for freebsd-${os_arch}
    sudo mkdir -p "/opt/freebsd/${os_arch}"
    wget -q https://download.freebsd.org/releases/${os_arch}/14.1-RELEASE/base.txz
    sudo tar -xf ./base.txz -C /opt/freebsd/${os_arch}
    rm base.txz
    export GOOS=freebsd
    export GOARCH=${GO_ARCHES[$i]}
    export CC=${cgo_cc}
    export CGO_ENABLED=1
    export CGO_LDFLAGS="-fuse-ld=lld"
    go build -o ./build/$appName-freebsd-$os_arch -ldflags="$ldflags" -tags=jsoniter .
  done
}

MakeRelease() {
  cd build
  mkdir compress
  for i in $(find . -type f -name "$appName-linux-*"); do
    cp "$i" alist
    tar -czvf compress/"$i".tar.gz alist
    rm -f alist
  done
    for i in $(find . -type f -name "$appName-android-*"); do
    cp "$i" alist
    tar -czvf compress/"$i".tar.gz alist
    rm -f alist
  done
  for i in $(find . -type f -name "$appName-darwin-*"); do
    cp "$i" alist
    tar -czvf compress/"$i".tar.gz alist
    rm -f alist
  done
  for i in $(find . -type f -name "$appName-freebsd-*"); do
    cp "$i" alist
    tar -czvf compress/"$i".tar.gz alist
    rm -f alist
  done
  for i in $(find . -type f -name "$appName-windows-*"); do
    cp "$i" alist.exe
    zip compress/$(echo $i | sed 's/\.[^.]*$//').zip alist.exe
    rm -f alist.exe
  done
  cd compress
  find . -type f -print0 | xargs -0 md5sum >"$1"
  cat "$1"
  cd ../..
}

if [ "$1" = "dev" ]; then
  FetchWebDev
  if [ "$2" = "docker" ]; then
    BuildDocker $1 $2 $3 $4 $5 
  elif [ "$2" = "docker-multiplatform" ]; then
      BuildDockerMultiplatform $1 $2 $3 $4 $5 
  elif [ "$2" = "web" ]; then
    echo "web only"
  else
    BuildDev $1 $2 $3 $4 $5 
  fi
elif [ "$1" = "release" -o "$1" = "beta" ]; then
  if [ "$1" = "beta" ]; then
    FetchWebDev
  else
    FetchWebRelease
  fi
  if [ "$2" = "docker" ]; then
    BuildDocker $1 $2 $3 $4 $5 
  elif [ "$2" = "docker-multiplatform" ]; then
    BuildDockerMultiplatform $1 $2 $3 $4 $5 
  elif [ "$2" = "linux_musl_arm" ]; then
    BuildReleaseLinuxMuslArm $1 $2 $3 $4 $5 
    MakeRelease "md5-linux-musl-arm.txt"
  elif [ "$2" = "linux_musl" ]; then
    BuildReleaseLinuxMusl $1 $2 $3 $4 $5 
    MakeRelease "md5-linux-musl.txt"
  elif [ "$2" = "android" ]; then
    BuildReleaseAndroid $1 $2 $3 $4 $5 
    MakeRelease "md5-android.txt"
  elif [ "$2" = "freebsd" ]; then
    BuildReleaseFreeBSD $1 $2 $3 $4 $5 
    MakeRelease "md5-freebsd.txt"
  elif [ "$2" = "web" ]; then
    echo "web only"
  else
    BuildRelease $1 $2 $3 $4 $5 
    MakeRelease "md5.txt"
  fi
elif [ "$1" = "prepare" ]; then
  if [ "$2" = "docker-multiplatform" ]; then
    PrepareBuildDockerMusl
  fi
elif [ "$1" = "zip" ]; then
  MakeRelease "$2".txt
else
  echo -e "Parameter error"
fi
