FROM ghcr.io/cirruslabs/flutter:3.22.0

ENV FLUTTER_GIT_URL=https://mirrors.tuna.tsinghua.edu.cn/git/flutter.git
ENV FLUTTER_STORAGE_BASE_URL=https://mirrors.tuna.tsinghua.edu.cn/flutter

# proxy settings - set yours
ENV HTTP_PROXY=
ENV HTTPS_PROXY=
ENV NO_PROXY=

# Accept Android licenses (persists in the image)
RUN yes | flutter doctor --android-licenses

RUN apt-get update && apt-get install -y iputils-ping apt-utils
