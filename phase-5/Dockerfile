FROM ghcr.io/cirruslabs/flutter:3.22.0

ENV FLUTTER_GIT_URL=https://mirrors.tuna.tsinghua.edu.cn/git/flutter.git
ENV FLUTTER_STORAGE_BASE_URL=https://mirrors.tuna.tsinghua.edu.cn/flutter

# proxy settings - set yours
#ENV HTTP_PROXY=
#ENV HTTPS_PROXY=
#ENV NO_PROXY=

# Accept Android licenses (persists in the image)
RUN yes | flutter doctor --android-licenses
RUN    sdkmanager \
        "platform-tools" \
        "platforms;android-33" \
        "platforms;android-34" \
        "build-tools;33.0.3" \
        "build-tools;30.0.3" \
        "build-tools;34.0.0"

RUN git config --global --add safe.directory /sdks/flutter

ARG USER_ID
ARG GROUP_ID
RUN chown -R ${USER_ID}:${GROUP_ID} /sdks/flutter

RUN apt-get update && apt-get install -y iputils-ping


# forcedly enable web in the configuration

USER ubuntu
RUN flutter config --no-analytics 
RUN flutter config --enable-web
RUN flutter precache

USER ubuntu
