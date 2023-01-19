#!/usr/bin/env bash

printf "If 'flash' is provided as a first argument, [only] flashing will be performed [if image is already built].\n\n"

# Docker image tag
TAG=nrfconnect-sdk

# Final output file, relative to $PWD
OUTPUT=build/zephyr.zip

# https://github.com/NordicPlayground/nrf-docker
# https://developer.nordicsemi.com/nRF_Connect_SDK/doc/latest/nrf/ug_thread_tools.html

check_docker_image()
{
    if ! docker inspect --type=image --format='Using docker image {{.RepoTags}} created {{.Created}}' "$TAG" 2>/dev/null ; then
        printf "First, build a Docker image using:\n"
        printf "    cd <directory where https://github.com/NordicPlayground/nrf-docker is checked out\n"
        printf "    docker build -t $TAG --build-arg sdk_nrf_revision=main .\n"
        exit 1
    fi
}

build()
{
    printf "\n########## Build ##########\n\n"

    docker run --rm \
        -v "${PWD}:/workdir/project" \
        -w /workdir/nrf/samples/openthread/coprocessor \
        $TAG \
        west build --pristine --board nrf52840dongle_nrf52840 --build-dir /workdir/project/build -- -DOVERLAY_CONFIG="overlay-usb.conf" -DDTC_OVERLAY_FILE="usb.overlay"
}

generate_image()
{
    printf "\n########## Generate RCP FW package ##########\n\n"

    docker run --rm \
        -v "${PWD}/build:/workdir/project/build" \
        $TAG \
        nrfutil pkg generate --hw-version 52 --sd-req=0x00 --application build/zephyr/zephyr.hex --application-version 1 "$OUTPUT"
}

flash()
{
    printf "\n########## Flash to $1 ##########\n\n"

    docker run --rm \
        -v "${PWD}/build:/workdir/project/build" \
        --device=$1 --privileged \
        $TAG \
        nrfutil dfu usb-serial -pkg "$OUTPUT" -p $1
}


check_docker_image

if [ "$1" == "bash" ]; then
    TMP_DIR=$(mktemp --tmpdir -d "$TAG.docker-run.$(date +%Y%m%d%H%M%S).project.XXX")
    echo -e "\nMapping /workdir/project to:\n$TMP_DIR\n"

    docker run --rm -it \
        -v "${TMP_DIR}:/workdir/project" \
        $TAG \
        bash

    echo -e "\nWhen done, execute:\nrm -r '$TMP_DIR'\n"
fi

if [ -z "$1" ] || [ ! -f "$OUTPUT" ]; then
    build
    generate_image
fi

if [ "$1" == "flash" ]; then
    printf "\nCurrently available nRF Dongles in DFU mode, auto-selecting first:\n"
    ls -l --color /dev/serial/by-id/usb*Nordic_Semiconductor_Open_DFU_Bootloader*

    SERIAL_PORT=$(ls /dev/serial/by-id/usb*Nordic_Semiconductor_Open_DFU_Bootloader* 2>/dev/null | head -n 1)

    if [ -z "$SERIAL_PORT" ]; then
        printf '\nNo dongle found.\n'
        printf '    1. Connect the nRF52840 Dongle to the USB port.\n'
        printf '    2. Press the RESET button on the dongle to put it into the DFU mode.\n'
        printf '    3. The LED on the dongle starts blinking ("breathing") red.\n'
        printf '    4. Dongle in DFU mode should be registered as /dev/ttyACMx device\n\n'
        exit 1
    fi

    flash $(readlink -f $SERIAL_PORT)
fi
