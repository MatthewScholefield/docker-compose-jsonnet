
local maskFields(object, maskFields) = {
  [field]: object[field]
  for field in std.objectFields(object)
  if std.length(std.find(field, maskFields)) == 0
};

{
  usingSwarm: std.extVar('useSwarm'), // Must be passed to jsonnet like `--ext-code useSwarm=true`
  Service(config): (
    local _config = { restart: 'unless-stopped' } + config;
    if $.usingSwarm then maskFields(_config, ['restart', 'expose', 'build', 'links']) else _config
  ),
  BindMount(source, target): {
    type: 'bind',
    source: source,
    target: target,
  },
  // Set bindToHost=true on docker swarm to pass through source ip
  // See https://stackoverflow.com/a/50592485/2132312
  bindOrExpose(ports, bindPorts=true, bindToHost=false): (
    if bindPorts then
      { ports: [
        if bindToHost then {
          mode: 'host',
          protocol: 'tcp',
          published: port,
          target: port,
        } else '%s:%s' % [port, port]
        for port in ports
      ] }
    else
      { expose: ['%s' % [port] for port in ports] }
  ),
  Env(valuesMap): [
    '%s=%s' % [key, valuesMap[key]]
    for key in std.objectFields(valuesMap)
    if valuesMap[key] != null
  ],
  localImage(image): '127.0.0.1:5000/%s' % [image],
  labelAttributes(labels): if $.usingSwarm then {deploy: {labels: labels}} else {labels: labels},
  Deployment(services, volumes=[]): {
    services: services,
    volumes: volumes,
  },
  HealthCheck(command, interval='15s', timeout='10s'): {
    test: command,
    interval: interval,
    timeout: timeout,
  },
  DeploymentConfig(config): if $.usingSwarm then config else {},
  RollingDeploymentConfig(): $.DeploymentConfig({
    update_config: {
      order: 'start-first',
      failure_action: 'rollback',
      delay: '10s',
    },
    rollback_config: {
      parallelism: 0,
      order: 'stop-first',
    },
  }),
  Volumes(volumes): (
    if std.isArray(volumes)
    then { [volume]: {} for volume in volumes }
    else volumes
  ),
  Networks(networks): (
    if std.isArray(networks)
    then { [network]: {} for network in networks }
    else networks
  ),
  volumeServices(volumes):: {
    ['volume-container_' + volume]: $.Service({
      image: 'alpine:3.15',
      command: 'sleep 99999909',
      volumes: ['%s:/volume' % volume]
    })
    for volume in volumes
  },
  ComposeFile(services, volumes={}, networks={}, configs={}, onlyVolumes=false): {
    version: '3.8',
    services: if onlyVolumes then $.volumeServices(volumes) else services,
    volumes: $.Volumes(volumes),
    networks: $.Networks(networks),
    configs: configs,
  },
  composeFileDeployments(deployments): (
    local volumes = std.flatMap(function(d) d.volumes, deployments);
    $.ComposeFile(
      services={
        [serviceName]: deployment.services[serviceName]
        for deployment in deployments
        for serviceName in std.objectFields(deployment.services)
      },
      volumes=std.foldl(
        function(volumeMap, deployment) (
          volumeMap + $.Volumes(deployment.volumes)
        ),
        deployments,
        {}
      )
    )
  )
}
