#!/bin/bash

while getopts m: OPT; do
    case "${OPT}" in
        "m")
            MODE="${OPTARG}"
            ;;
    esac
done

if [ "quiesce" == "${MODE}" ]; then
    echo "Application HOGE is requested to be quiesced."
    echo "Quiescing ... leaving target pool for load balancing ..."
    sleep 1
    echo "Quiescing ... stopping service HOGE"
    sleep 1
    echo "Quiescing ... stopping service FUGA"
    sleep 1
    echo "Quiescing ... stopping service PIYO"
    sleep 1
    echo "Quiescing ... stopping service FOO"
    sleep 1
    echo "Quiescing ... stopping service BAR"
    sleep 1
    echo "Quiescing ... stopping service BAZ"
    sleep 1
    echo "Application HOGE has been quiesced and ready for vMotion."
elif [ "unquiesce" == "${MODE}" ]; then
    echo "Application HOGE is requested to be unquiesced."
    echo "UnQuiescing ... starting service BAZ"
    sleep 1
    echo "UnQuiescing ... starting service BAR"
    sleep 1
    echo "UnQuiescing ... starting service FOO"
    sleep 1
    echo "UnQuiescing ... starting service PIYO"
    sleep 1
    echo "UnQuiescing ... starting service FUGA"
    sleep 1
    echo "UnQuiescing ... starting service HOGE"
    sleep 1
    echo "UnQuiescing ... joining target pool for load balancing ..."
    sleep 1
    echo "Application HOGE has been unquiesced and is in production."
else
    echo "Error: Invalid argument" 1>&2
    exit 1
fi
