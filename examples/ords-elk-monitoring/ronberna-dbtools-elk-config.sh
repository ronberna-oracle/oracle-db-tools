#!/bin/bash -x
#
# 
# ronberna-dbtools-elk-config.sh
#
# Copyright (c) 2019, 2021, Oracle and/or its affiliates.
#
#    NAME
#      ronberna-dbtools-elk-config.sh - Configure script for ELK docker stack
#
#    MODIFIED   (MM/DD/YY)
#    ronberna    24/02/22 - Refactored for generic use & adapted for ords only monitoring
#    ronberna    18/02/22 - Fix permissions and target user for kibana
#    ronberna    16/02/22 - Moving ords logs volumes out of the repo
#    ronberna    26/01/22 - Added support to ADE code pull
#    ronberna    24/01/22 - Added support to existing installations
#    ronberna    25/11/21 - Created from prvtelk-configure.sh version 11.02.21
#
#    TODO:
#
#

script_directory="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
if real_script_path="$( readlink -e "$script_directory/$( basename "$0" )" )";then
  BASEDIR="$( dirname "${real_script_path}" )"
else
  BASEDIR="$script_directory"
fi

export user='elastic'
export newpass='welcome1'
export elk_host='localhost'
export elasticsearch_port="9200"
export kibana_port="5601"

docker_containers_volumes_dir="${BASEDIR}/persistent-data-docker-deployments"

sed -i "s|SED_REPLACE_HERE:/usr/share/logstash/data/logs|${docker_containers_volumes_dir}/ords_logs:/usr/share/logstash/data/logs|g" "${BASEDIR}"/docker-compose.yml
sed -i "s|SED_REPLACE_HERE:/usr/share/elasticsearch/data|${docker_containers_volumes_dir}/elasticdata:/usr/share/elasticsearch/data|g" "${BASEDIR}"/docker-compose.yml

docker compose -f "${BASEDIR}"/docker-compose.yml down

if [ ! -d "${docker_containers_volumes_dir}/elasticdata" ]; then mkdir -p "${docker_containers_volumes_dir}/elasticdata"; fi
if [ ! -d "${docker_containers_volumes_dir}/ords_logs/access_logs" ]; then mkdir -p "${docker_containers_volumes_dir}/ords_logs/access_logs"; fi
if [ ! -d "${docker_containers_volumes_dir}/ords_logs/java_logs" ]; then mkdir -p "${docker_containers_volumes_dir}/ords_logs/java_logs"; fi
chmod -R 777 "${BASEDIR}"
if [ -e "${BASEDIR}/logstash.conf" ]; then chmod 766 "${BASEDIR}/logstash.conf"; fi

docker compose -f "${BASEDIR}"/docker-compose.yml up -d elasticsearch
sleep 60

# Clearing previous kibana configuration
echo "Deleting kibana indexes"
curl --noproxy '*' -XDELETE -u $user:$newpass "http://$elk_host:$elasticsearch_port/.kibana*"
echo ""

#Starting Kibana
echo "Starting Kibana"
docker compose -f "${BASEDIR}"/docker-compose.yml up -d kibana

res_kibana=$(curl --noproxy '*' -sX GET -u $user:$newpass "http://$elk_host:$kibana_port/status" -I | grep HTTP | cut -d$' ' -f2)
echo "Kibana status is :" $res_kibana
echo "Waiting till Kibana is up"
COUNTER=0
while [[ ! "$res_kibana" == 200 ]]
do
  COUNTER=$((COUNTER + 10))
  res_kibana=$(curl --noproxy '*' -sX GET -u $user:$newpass "http://$elk_host:$kibana_port/status" -I | grep HTTP | cut -d$' ' -f2)
  sleep 30
  echo "Kibana status is :" $res_kibana
  if [ $COUNTER -gt 200 ]; then
    echo "Kibana start failed after $COUNTER seconds"
    exit 1;
  fi
done
sleep 15

# Change default timezone settings for kibana
echo "Changing default timezone settings for Kibana"
curl --noproxy '*' -X POST -u $user:$newpass -H "Content-Type: application/json" -H "kbn-xsrf: true" -d '{"value":"UTC"}' "http://$elk_host:$kibana_port/api/kibana/settings/dateFormat:tz"
echo ""

# Apply index templates
echo "Creating index templates"
files=$(ls *template.json)
for file in $files
do
   echo $file
   filename=${file%.*}
   curl --noproxy '*' -X PUT -u $user:$newpass "http://$elk_host:$elasticsearch_port/_template/$filename?pretty" -H "Content-Type: application/json" -d @$file
   echo ""
done

# Set max shards
echo "Setting cluster max shards"
curl --noproxy '*' -X PUT -u $user:$newpass "http://$elk_host:$elasticsearch_port/_cluster/settings" -H 'Content-type: application/json' --data-binary $'{"persistent":{"cluster.max_shards_per_node":15000}}'
echo ""

# Import ILM policy
echo "Importing ILM policy"
curl --noproxy '*' -X PUT -u $user:$newpass "$elk_host:$elasticsearch_port/_ilm/policy/common-retention-policy?pretty" -H 'Content-Type: application/json' -d @${BASEDIR}/common-retention-policy.json
echo ""

# Apply retention policy to existing indices
for index in $(curl --noproxy '*' -sX GET -u $user:$newpass $elk_host:$elasticsearch_port/_cat/indices | grep adb | grep -v broker | awk {'print $3'}) ; do
  echo "Applying ILM policy to $index"
  curl --noproxy '*' -X PUT -u $user:$newpass "$elk_host:$elasticsearch_port/$index/_settings?pretty" -H 'Content-Type: application/json' -d '{"lifecycle.name":"common-retention-policy", "number_of_replicas":0}'
  echo ""
done

# Create index patterns
echo "Creating index patterns"
files=$(ls *pattern.json)
for file in $files
do
   echo $file
   filename=${file%.*}
   curl --noproxy '*' -X POST -u $user:$newpass "$elk_host:$kibana_port/api/saved_objects/index-pattern/$filename?overwrite=true" -H 'kbn-xsrf: true' -H 'Content-Type: application/json' -d @$file
   echo ""
done

# Set default index
echo "Setting adb-ords-index-pattern as default index"
curl --noproxy '*' -X POST -u $user:$newpass "$elk_host:$kibana_port/api/kibana/settings/defaultIndex" -H 'Content-Type: application/json' -H 'kbn-xsrf: true'  -d '{"value": "adb-ords-index-pattern"}'
echo ""

docker exec elasticsearch chmod -R 777 /usr/share/elasticsearch/data

#Starting Logstash
echo "Starting Logstash"
docker compose -f "${BASEDIR}"/docker-compose.yml up -d logstash

echo "ronberna-dbtools-elk configuration completed"