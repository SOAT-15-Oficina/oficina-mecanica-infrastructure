#!/bin/sh
set -eu

ENDPOINT="${AWS_ENDPOINT_URL:-http://localstack:4566}"
REGION="${AWS_DEFAULT_REGION:-sa-east-1}"
ACCOUNT="000000000000"

aws_() {
  aws --endpoint-url "$ENDPOINT" --region "$REGION" "$@"
}

queue_arn() {
  aws_ sqs get-queue-attributes --queue-url "$1" \
    --attribute-names QueueArn --query Attributes.QueueArn --output text
}

create_inbox() {
  name="$1"
  dlq_url="$(aws_ sqs create-queue --queue-name "${name}-dlq.fifo" \
    --attributes FifoQueue=true,ContentBasedDeduplication=false \
    --query QueueUrl --output text)"
  dlq_arn="$(queue_arn "$dlq_url")"
  aws_ sqs create-queue --queue-name "${name}.fifo" \
    --attributes "{\"FifoQueue\":\"true\",\"ContentBasedDeduplication\":\"false\",\"VisibilityTimeout\":\"60\",\"RedrivePolicy\":\"{\\\"deadLetterTargetArn\\\":\\\"${dlq_arn}\\\",\\\"maxReceiveCount\\\":\\\"5\\\"}\"}" \
    --query QueueUrl --output text
}

create_topic() {
  aws_ sns create-topic --name "$1" \
    --attributes FifoTopic=true,ContentBasedDeduplication=false \
    --query TopicArn --output text
}

os_inbox_url="$(create_inbox os-inbox)"
create_inbox billing-inbox >/dev/null
create_inbox execution-inbox >/dev/null

billing_topic="$(create_topic billing-events.fifo)"
execution_topic="$(create_topic execution-events.fifo)"

os_inbox_arn="$(queue_arn "$os_inbox_url")"

for topic in "$billing_topic" "$execution_topic"; do
  aws_ sns subscribe --topic-arn "$topic" --protocol sqs \
    --notification-endpoint "$os_inbox_arn" \
    --attributes RawMessageDelivery=true \
    --return-subscription-arn --query SubscriptionArn --output text
done

if ! aws_ dynamodb describe-table --table-name execution-tickets >/dev/null 2>&1; then
  aws_ dynamodb create-table --table-name execution-tickets \
    --billing-mode PAY_PER_REQUEST \
    --attribute-definitions \
      AttributeName=PK,AttributeType=S AttributeName=SK,AttributeType=S \
      AttributeName=GSI1PK,AttributeType=S AttributeName=GSI1SK,AttributeType=S \
    --key-schema AttributeName=PK,KeyType=HASH AttributeName=SK,KeyType=RANGE \
    --global-secondary-indexes 'IndexName=queue,KeySchema=[{AttributeName=GSI1PK,KeyType=HASH},{AttributeName=GSI1SK,KeyType=RANGE}],Projection={ProjectionType=ALL}' \
    >/dev/null
  aws_ dynamodb wait table-exists --table-name execution-tickets
fi

ttl_status="$(aws_ dynamodb describe-time-to-live --table-name execution-tickets \
  --query TimeToLiveDescription.TimeToLiveStatus --output text)"
if [ "$ttl_status" != "ENABLED" ]; then
  aws_ dynamodb update-time-to-live --table-name execution-tickets \
    --time-to-live-specification Enabled=true,AttributeName=expires_at >/dev/null
fi

echo "filas, topicos, assinaturas e tabela prontos na conta ${ACCOUNT} (${REGION})"
