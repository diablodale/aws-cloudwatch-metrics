#!/bin/bash -e

registry='036129835789.dkr.ecr.us-east-1.amazonaws.com'
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
        pull='--pull --no-cache'
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
if [[ "$env_tier" != "dev" && -n "$gitdirty" ]]; then
    echo "Error: git status dirty, action denied" >&2
    exit 1
fi
tag="${env_tier}-${githash}${gitdirty}"

# dev has no registry
if [[ "$env_tier" == "dev" ]]; then
    registry=''
else
    registry="${registry}/"
    push='--push'
    # Authenticate Docker to AWS ECR
    aws ecr get-login-password --region $region | docker login --username AWS --password-stdin $registry
fi


# Create and use a multiplatform builder
echo "Building multiplatform with tags: ${tag}, ${env_tier}"
#docker buildx create --use --name multiplatform-builder || docker buildx use multiplatform-builder

# Build and push multiplatform image
# often written `docker buildx build` yet `docker build` on docker desktop is an alias for the same
# Note: Local tags are not created; use --load for local testing if needed
docker build $pull -f ecs-metrics.dockerfile \
    --platform linux/amd64,linux/arm64 \
    -t "${registry}${namespace}/ecs-metrics:${tag}" \
    -t "${registry}${namespace}/ecs-metrics:${env_tier}" \
    $push \
    .

# git push to origin with tier as the branch
if [[ "$env_tier" != "dev" ]]; then
    git checkout -B "${env_tier}"
    git push origin "${env_tier}"
    git checkout -
fi
