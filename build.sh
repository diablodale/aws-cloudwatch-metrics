#!/bin/bash -e

repo_base='036129835789.dkr.ecr.us-east-1.amazonaws.com'
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

# Abort early if the environment is NOT one of dev|test|prod
if [[ ! "$1" =~ ^(dev|test|prod)$ ]]; then
    echo "Aborting. No $1 operations with this script" >&2
    exit 1
fi
env_tier="$1"

# calculate tag for images
githash=$(git log -1 --pretty=%h)
[[ -n "$(git status --short)" ]] && gitdirty='-dirty'
tag="${env_tier}-${githash}${gitdirty}"

if [[ "$env_tier" == "prod" && -n "$gitdirty" ]]; then
    echo "Error: git status dirty, PROD action denied" >&2
    exit 1
fi

echo "Building with tags: ${tag}, ${env_tier}"
docker build $PULL -f ecs-metrics.dockerfile \
    -t "${namespace}/ecs-metrics:${tag}" \
    -t "${namespace}/ecs-metrics:${env_tier}" \
    -t "${repo_base}/${namespace}/ecs-metrics:${tag}" \
    -t "${repo_base}/${namespace}/ecs-metrics:${env_tier}" \
    .

if [ "$env_tier" != 'dev' ]; then
    # push image to ecr
    aws ecr get-login-password --region $region | docker login --username AWS --password-stdin $repo_base
    docker push "${repo_base}/${namespace}/ecs-metrics:${tag}"
    docker push "${repo_base}/${namespace}/ecs-metrics:${env_tier}"
fi
