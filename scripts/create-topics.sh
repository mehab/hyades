#!/usr/bin/env bash

# This file is part of Dependency-Track.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) OWASP Foundation. All Rights Reserved.

set -euxo pipefail

function create_topic() {
  topic_config_flags=""
  argument_configs=($3)
  for cfg in "${argument_configs[@]}"; do
    topic_config_flags="${topic_config_flags} --topic-config ${cfg}"
  done

  if ! output=$(rpk topic create "$1" --partitions "$2" $topic_config_flags); then
    # Don't fail the script when the rpk command failed because the topic already exists.
    if [[ "$output" != *"TOPIC_ALREADY_EXISTS"* ]]; then
      exit 2
    fi
  fi
}

# Wait for Redpanda to become available
rpk cluster health --watch --exit-when-healthy \
  --api-urls "$(echo "$REDPANDA_BROKERS" | sed -E 's/:[[:digit:]]+/:9644/g')"

notification_topics=(
  "${DT_KAFKA_TOPIC_PREFIX:-}dtrack.notification.analyzer"
  "${DT_KAFKA_TOPIC_PREFIX:-}dtrack.notification.bom"
  "${DT_KAFKA_TOPIC_PREFIX:-}dtrack.notification.configuration"
  "${DT_KAFKA_TOPIC_PREFIX:-}dtrack.notification.datasource-mirroring"
  "${DT_KAFKA_TOPIC_PREFIX:-}dtrack.notification.file-system"
  "${DT_KAFKA_TOPIC_PREFIX:-}dtrack.notification.integration"
  "${DT_KAFKA_TOPIC_PREFIX:-}dtrack.notification.new-vulnerability"
  "${DT_KAFKA_TOPIC_PREFIX:-}dtrack.notification.new-vulnerable-dependency"
  "${DT_KAFKA_TOPIC_PREFIX:-}dtrack.notification.policy-violation"
  "${DT_KAFKA_TOPIC_PREFIX:-}dtrack.notification.project-audit-change"
  "${DT_KAFKA_TOPIC_PREFIX:-}dtrack.notification.project-created"
  "${DT_KAFKA_TOPIC_PREFIX:-}dtrack.notification.project-vuln-analysis-complete"
  "${DT_KAFKA_TOPIC_PREFIX:-}dtrack.notification.repository"
  "${DT_KAFKA_TOPIC_PREFIX:-}dtrack.notification.vex"
  "${DT_KAFKA_TOPIC_PREFIX:-}dtrack.notification.user"
)
for topic_name in "${notification_topics[@]}"; do
  create_topic "$topic_name" "${NOTIFICATION_TOPICS_PARTITIONS:-1}" "retention.ms=${NOTIFICATION_TOPICS_RETENTION_MS:-43200000}"
done

repo_meta_analysis_topics=(
  "${DT_KAFKA_TOPIC_PREFIX:-}dtrack.repo-meta-analysis.component"
  "${DT_KAFKA_TOPIC_PREFIX:-}dtrack.repo-meta-analysis.result"
)
for topic_name in "${repo_meta_analysis_topics[@]}"; do
  create_topic "$topic_name" "${REPO_META_ANALYSIS_TOPICS_PARTITIONS:-3}" "retention.ms=${REPO_META_ANALYSIS_TOPICS_RETENTION_MS:-43200000}"
done

vuln_analysis_topics=(
  "${DT_KAFKA_TOPIC_PREFIX:-}dtrack.vuln-analysis.component"
  "${DT_KAFKA_TOPIC_PREFIX:-}dtrack.vuln-analysis.scanner.result"
  "${DT_KAFKA_TOPIC_PREFIX:-}dtrack.vuln-analysis.result"
  "${DT_KAFKA_TOPIC_PREFIX:-}dtrack.vuln-analysis.result.processed"
)
for topic_name in "${vuln_analysis_topics[@]}"; do
  create_topic "$topic_name" "${VULN_ANALYSIS_TOPICS_PARTITIONS:-3}" "retention.ms=${VULN_ANALYSIS_TOPICS_RETENTION_MS:-43200000}"
done

create_topic "${DT_KAFKA_TOPIC_PREFIX:-}dtrack.event.bom-uploaded" "${EVENT_BOM_UPLOADED_TOPIC_PARTITIONS:-3}" "retention.ms=${EVENT_BOM_UPLOADED_TOPIC_RETENTION_MS:-43200000}"
create_topic "${DT_KAFKA_TOPIC_PREFIX:-}dtrack.vulnerability.mirror.command" "1" "retention.ms=${VULN_MIRROR_TOPICS_RETENTION_MS:-43200000}"
create_topic "${DT_KAFKA_TOPIC_PREFIX:-}dtrack.vulnerability.mirror.state" "1" "cleanup.policy=compact segment.bytes=67108864 max.compaction.lag.ms=1"
create_topic "${DT_KAFKA_TOPIC_PREFIX:-}dtrack.vulnerability.digest" "1" "cleanup.policy=compact segment.bytes=134217728"
create_topic "${DT_KAFKA_TOPIC_PREFIX:-}dtrack.vulnerability" "${VULN_MIRROR_TOPICS_PARTITIONS:-3}" "cleanup.policy=compact"
create_topic "${DT_KAFKA_TOPIC_PREFIX:-}dtrack.epss" "${VULN_MIRROR_TOPICS_PARTITIONS:-3}" "cleanup.policy=compact"

echo "All topics created successfully"