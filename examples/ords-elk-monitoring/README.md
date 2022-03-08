# Oracle REST Data Services (ORDS) Monitoring, using ELK stack

## Requirements
- [Docker](https://docs.docker.com/engine/install/)
- [Docker Compose V2](https://docs.docker.com/compose/cli-command/)
- ORDS logging enabled for ORDS JAVA logs
- ORDS logging enabled for Standalone Access logs

## Customizable variables in ronberna-dbtools-elk-config.sh
- Elasticsearch password, if changed, needs to be changed in docker-compose.yml as well.
`export newpass='welcome1'`
- Elasticsearch and Kibana ports, if changed, needs to be changed in docker-compose.yml as well.
`export elasticsearch_port="9200"`
`export kibana_port="5601"`
- Docker containers persistent data directories configuration. Default:
`docker_containers_volumes_dir="${BASEDIR}/persistent-data-docker-deployments"`

## How to enable ORDS JAVA logs?
Before enabling the JAVA logs please take a second to review our provided `logging.properties` file. 
In this file you'll need to modify the directory you've chosen to host the `$docker_containers_volumes_dir` as JAVA logs need to be accessible to the logstash volume \(${docker_containers_volumes_dir}/ords_logs\).

Once you've modified or created your `logging.properties` file, you may do any of the following options to enable JAVA logs:
- Use the JAVA_OPTS variable to pass the following config and restart ORDS:

`JAVA_OPTS=-Djava.util.logging.config.file=$ORDS_HOME/logging.properties`

OR

- Modify the ords binary file located on `$ORDS_HOME/bin/ords` and add the following line inside the function `setupArgs` and restart ORDS

`AddVMOption -Djava.util.logging.config.file=$ORDS_HOME/logging.properties`

**Inside this directory we've provided a `logging.properties` file which demonstrates the correct log format supported by our logstash configuration, this format is necessary for propper log digestion. Any other format is unsupported.**

## How to enable Standalone Access logs?
Enabling standalone access logs is a bit easier, you just need to run the following configuration command on the ORDS binary:
> `$ORDS_HOME/bin/ords config set standalone.access.log /\<$docker_containers_volumes_dir\>/ords_logs/access_logs/`

Remember to provide the base directory of the containers volumes \(Same directory configured in `ronberna-dbtools-elk-config.sh`\)

## How to run this AIO tool?
After modifying \(If customization is needed\) the `ronberna-dbtools-elk-config.sh` script and enabling the required logs for ORDS, simply run the config script using:
> `./ronberna-dbtools-elk-config.sh

This script will take care of:
- Creating directories (if needed)`
- Setting up the docker volumes directories according to the `$docker_containers_volumes_dir` variable
- Flushing the provided Kibana default configuration
- Setting up the Elasticsearch and Kiabana according to ORDS needs
- Starting up Logstash to start ORDS log digestion
