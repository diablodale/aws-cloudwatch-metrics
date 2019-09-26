#!/bin/sh -e

# curl --unix-socket /var/run/docker.sock http://dummyhost/v1.24/containers/samba/stats?stream=false
# https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-metadata-endpoint-v3.html
curl -s ${ECS_CONTAINER_METADATA_URI}/task > /tmp/es_task.json
curl -s ${ECS_CONTAINER_METADATA_URI}/task/stats > /tmp/es_stats.json

ECS_CLUSTER="$(jq -r '.Cluster' /tmp/es_task.json)"
ECS_SERVICE="$(jq -r '.Family' /tmp/es_task.json)"
ECS_TASK_ID="$(jq -r '.TaskARN' /tmp/es_task.json | grep -o -E '[^/]+$')"
ECS_AVAILZONE="$(jq -r '.AvailabilityZone' /tmp/es_task.json)"

jq '[.Containers[] | {id:.DockerId,dcName:.Name}]' /tmp/es_task.json > /tmp/es_containers.json
jq '[.[]]' /tmp/es_stats.json > /tmp/es_stats_array.json

jq -s '[ .[0] + .[1] | group_by(.id)[] | select(length > 1) | add ]' \
    /tmp/es_containers.json /tmp/es_stats_array.json > /tmp/es_combo_stats.json

MEM_TOTAL=$(free -b | grep Mem | awk '{print $2}')

# https://www.datadoghq.com/blog/how-to-collect-docker-metrics/
# https://docs.docker.com/config/containers/runmetrics/
# https://docs.docker.com/engine/api/v1.30/#operation/ContainerStats
# https://stackoverflow.com/questions/30271942/get-docker-container-cpu-usage-as-percentage
jq "[.[] | {time: .read, \
            cluster: \"${ECS_CLUSTER}\", \
            service: \"${ECS_SERVICE}\", \
            taskId: \"${ECS_TASK_ID}\", \
            availZone: \"${ECS_AVAILZONE}\", \
            containerId: .id, \
            containerName: .dcName, \
            currentMem: .memory_stats.usage, \
            maxMem: .memory_stats.max_usage, \
            percentMem: (100 * .memory_stats.usage / (if (.memory_stats.stats.hierarchical_memory_limit == 9223372036854771712) then $MEM_TOTAL else .memory_stats.stats.hierarchical_memory_limit end)), \
            tmpfsMem: (.memory_stats.stats.cache - .memory_stats.stats.active_file - .memory_stats.stats.inactive_file), \
            tmpfsMem2: (.memory_stats.stats.active_anon + .memory_stats.stats.inactive_anon - .memory_stats.stats.rss), \
            percentCpu: (100 * (.cpu_stats.cpu_usage.total_usage - .precpu_stats.cpu_usage.total_usage) / (.cpu_stats.system_cpu_usage - .precpu_stats.system_cpu_usage)), \
            percentThrottle: (if (.cpu_stats.throttling_data.periods - .precpu_stats.throttling_data.periods) == 0 then 0 else 100 * (.cpu_stats.throttling_data.throttled_periods - .precpu_stats.throttling_data.throttled_periods) / (.cpu_stats.throttling_data.periods - .precpu_stats.throttling_data.periods) end), \
            percentThrottle2: (100 * (.cpu_stats.throttling_data.throttled_time - .precpu_stats.throttling_data.throttled_time) / (.cpu_stats.system_cpu_usage - .precpu_stats.system_cpu_usage)) \
    }]" \
    /tmp/es_combo_stats.json > /tmp/es_ready_stats.json

# move to host instance volume, where agent on host will forward to cloudwatch
EPOCH=$(date --utc +%s)
mv /tmp/es_ready_stats.json "/mnt/ecs-metrics/${ECS_TASK_ID}-${EPOCH}.json"

rm /tmp/es_*.json