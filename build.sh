#!/bin/bash -e

ecr_base='036129835789.dkr.ecr.us-east-1.amazonaws.com'
namespace='aws-cloudwatch-metrics'
region='us-east-1'

function confirm {
    while true; do
        read -r -p "Confirm ${1}: [y/n] " answer
        case $answer in
            [Nn]* ) return 1;;
            [Yy]* ) break;;
            *     ) echo 'Please answer yes or no';;
        esac
    done
}

if [ "$#" == "0" ]; then
    echo -e 'Usage:\nbuild.sh [--pull] dev|test|prod'
    exit 0
fi

case "$1" in
    --pull)
        PULL='--pull --no-cache'
        shift
        ;;
    -*|--*)
        echo "Error: unsupported flag $1" >&2
        exit 1
        ;;
    *)
        ;;
esac

if [[ "$1" =~ ^(dev|test|prod)$ ]]; then

    #timestamp=$(date --utc +%FT%TZ)
    githash=$(git log -1 --pretty=%h)
    [[ -n "$(git status --short)" ]] && gitdirty='-dirty'
    tag="${githash}${gitdirty}"
    echo "Tagging as: ${tag}"

    if [[ "$1" == "prod" && -n "$gitdirty" ]]; then
        echo "Error: git status dirty, PROD action denied" >&2
        exit 1
    fi

    ENVTIER=${1} docker build $PULL -f ecs-metrics.dockerfile \
        -t ${namespace}/ecs-metrics \
        -t ${namespace}/ecs-metrics:${tag} \
        -t ${namespace}/ecs-metrics:${1} \
        .

    images="$(docker image ls | grep -E "^${namespace}/\S+\s+${tag}" | awk '{print $1}')"
    if [ "$1" != 'dev' ]; then
        for item in $images; do
            docker tag "${item}:${tag}" "${ecr_base}/${item}:${tag}"
            docker tag "${item}:${tag}" "${ecr_base}/${item}:${1}"
            docker push "${ecr_base}/${item}:${tag}"
            docker push "${ecr_base}/${item}:${1}"
        done
    fi

else
    echo "Aborting. No $1 operations with this script" >&2
    exit 1

fi