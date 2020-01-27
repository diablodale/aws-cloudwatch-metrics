#!/bin/sh -e

WORKDIR="$(mktemp -d -p /mnt/ecs-metrics)"
cd "$WORKDIR"

# curl --unix-socket /var/run/docker.sock http://dummyhost/v1.24/containers/samba/stats?stream=false
# https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-metadata-endpoint-v3.html
curl -s ${ECS_CONTAINER_METADATA_URI}/task > es_task.json
curl -s ${ECS_CONTAINER_METADATA_URI}/task/stats > es_stats.json

ECS_CLUSTER="$(jq -r '.Cluster' es_task.json)"
ECS_SERVICE="$(jq -r '.Family' es_task.json)"
ECS_TASK_ID="$(jq -r '.TaskARN' es_task.json | grep -o -E '[^/]+$')"
ECS_AVAILZONE="$(jq -r '.AvailabilityZone' es_task.json)"

jq '.Limits as $tlimits | [.Containers[] | {id:.DockerId, dcName:.Name, taskLimits:$tlimits}]' es_task.json > es_containers.json
jq '[.[]]' es_stats.json > es_stats_array.json

jq -s '[ .[0] + .[1] | group_by(.id)[] | select(length > 1) | add ]' \
    es_containers.json es_stats_array.json > es_combo_stats.json

# https://www.datadoghq.com/blog/how-to-collect-docker-metrics/
# https://docs.docker.com/config/containers/runmetrics/
# https://docs.docker.com/engine/api/v1.30/#operation/ContainerStats
# https://stackoverflow.com/questions/30271942/get-docker-container-cpu-usage-as-percentage
# 27 Jan 2020: changed usage to be app memory usage + tmpfs; no longer includes page cache
jq "[.[] | {time: .read, \
            cluster: \"${ECS_CLUSTER}\", \
            service: \"${ECS_SERVICE}\", \
            taskId: \"${ECS_TASK_ID}\", \
            availZone: \"${ECS_AVAILZONE}\", \
            containerId: .id, \
            containerName: .dcName, \
            currentMem: .memory_stats.usage, \
            fileCache: (.memory_stats.stats.active_file + .memory_stats.stats.inactive_file), \
            maxMem: .memory_stats.max_usage, \
            percentMemOfTask: (100 * (.memory_stats.usage - .memory_stats.stats.active_file - .memory_stats.stats.inactive_file) / (if (.memory_stats.stats.hierarchical_memory_limit == 9223372036854771712) then .memory_stats.limit else .memory_stats.stats.hierarchical_memory_limit end)), \
            percentMemOfHost: (100 * (.memory_stats.usage - .memory_stats.stats.active_file - .memory_stats.stats.inactive_file) / .memory_stats.limit), \
            tmpfsMem: (.memory_stats.stats.cache - .memory_stats.stats.active_file - .memory_stats.stats.inactive_file), \
            tmpfsMem2: (.memory_stats.stats.active_anon + .memory_stats.stats.inactive_anon - .memory_stats.stats.rss), \
            percentCpuOfTask: (100 * (.cpu_stats.cpu_usage.total_usage - .precpu_stats.cpu_usage.total_usage) / (.cpu_stats.system_cpu_usage - .precpu_stats.system_cpu_usage) * .cpu_stats.online_cpus / (if (.taskLimits.CPU > 0) then .taskLimits.CPU else .cpu_stats.online_cpus end)), \
            percentCpuOfHost: (100 * (.cpu_stats.cpu_usage.total_usage - .precpu_stats.cpu_usage.total_usage) / (.cpu_stats.system_cpu_usage - .precpu_stats.system_cpu_usage)), \
            percentThrottle: (if (.cpu_stats.throttling_data.periods - .precpu_stats.throttling_data.periods) == 0 then 0 else 100 * (.cpu_stats.throttling_data.throttled_periods - .precpu_stats.throttling_data.throttled_periods) / (.cpu_stats.throttling_data.periods - .precpu_stats.throttling_data.periods) end), \
            percentThrottle2: (100 * (.cpu_stats.throttling_data.throttled_time - .precpu_stats.throttling_data.throttled_time) / (.cpu_stats.system_cpu_usage - .precpu_stats.system_cpu_usage)) \
    }]" \
    es_combo_stats.json > es_ready_stats.json

# move to host instance volume, where agent on host will forward to cloudwatch
EPOCH=$(date --utc +%s)
mv es_ready_stats.json "/mnt/ecs-metrics/${ECS_TASK_ID}-${EPOCH}.json"

cd /
rm -rf "$WORKDIR"
