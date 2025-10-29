FROM debian:bookworm

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl git wget unzip xz-utils zip \
    libgconf-2-4 gdb libstdc++6 libglu1-mesa \
    fonts-droid-fallback lib32stdc++6 python3 \
    openjdk-17-jdk build-essential \
    ruby ruby-dev make gcc

# Install Flutter
ENV FLUTTER_VERSION=3.16.0
ENV FLUTTER_HOME=/opt/flutter
RUN git clone https://github.com/flutter/flutter.git ${FLUTTER_HOME} -b stable
ENV PATH="${FLUTTER_HOME}/bin:${PATH}"

# Install Android SDK
ENV ANDROID_SDK_ROOT=/opt/android-sdk
RUN mkdir -p ${ANDROID_SDK_ROOT}/cmdline-tools && \
    wget -q https://dl.google.com/android/repository/commandlinetools-linux-9477386_latest.zip && \
    unzip -q commandlinetools-linux-9477386_latest.zip -d ${ANDROID_SDK_ROOT}/cmdline-tools && \
    mv ${ANDROID_SDK_ROOT}/cmdline-tools/cmdline-tools ${ANDROID_SDK_ROOT}/cmdline-tools/latest && \
    rm commandlinetools-linux-9477386_latest.zip

ENV PATH="${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin:${ANDROID_SDK_ROOT}/platform-tools:${PATH}"

# Accept licenses and install build tools
RUN yes | sdkmanager --licenses
RUN sdkmanager "platform-tools" "platforms;android-33" "build-tools;33.0.0" "extras;google;google_play_services"

# Pre-download Flutter dependencies
RUN flutter doctor -v
RUN flutter config --no-analytics

# Install fastlane for deployment
RUN gem install fastlane

WORKDIR /workspace
