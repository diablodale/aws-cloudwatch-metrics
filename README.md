# AWS Cloudwatch Custom Metrics for EC2 and ECS

Custom metrics

## Build

```bash
docker build -f ecs-metrics.dockerfile -t ecs-metrics -t ecs-metrics:$(git log -1 --pretty=%h) .
```

## Setup

1. Configure IAM role for EC2 instance
2. Configure optional IAM role for ECS Tasks
3. Run `aws-ec2-custom-metrics` on the host instance, e.g. cron
4. Run the `ecs-metrics` container while mounting a work folder
   on the host to `/mnt/ecs-metrics` in that container, e.g.
   ```bash
   docker run -v /run/ecsm:/mnt/ecs-metrics ecs-metrics
   ```

## Alternates

An AWS-provided distribution of the OpenTelemetry project. Known as ADOT.

https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/deploy-container-insights-ECS-adot.html

https://aws-otel.github.io/docs/setup/ecs

https://aws.amazon.com/blogs/containers/cost-savings-by-customizing-metrics-sent-by-container-insights-in-amazon-eks/

https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/receiver/awsecscontainermetricsreceiver#available-metrics

