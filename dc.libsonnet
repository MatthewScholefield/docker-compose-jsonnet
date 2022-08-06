
local useSwarm = std.extVar('useSwarm'); // Must be passed to jsonnet like `--ext-code useSwarm=true`

local maskFields(object, maskFields) = {
  [field]: object[field]
  for field in std.objectFields(object)
  if std.length(std.find(field, maskFields)) == 0
};

{
  Service(config): (
    local _config = { restart: 'unless-stopped' } + config;
    if useSwarm then maskFields(_config, ['restart', 'expose', 'build', 'links']) else _config
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
  Deployment(services, volumes=[]): {
    services: services,
    volumes: volumes,
  },
  Volumes(volumes): (
    if std.isArray(volumes)
    then { [volume]: {} for volume in volumes }
    else volumes
  ),
  ComposeFile(services, volumes={}): {services: services, volumes: Volumes(volumes)},
  composeFileDeployments(deployments): (
    local volumes = std.flatMap(function(d) d.volumes, deployments);
    ComposeFile(
      services={
        [serviceName]: deployment.services[serviceName]
        for deployment in deployments
        for serviceName in std.objectFields(deployment.services)
      },
      volumes=std.foldl(
        function(volumeMap, deployment) (
          volumeMap + Volumes(deployment.volumes)
        ),
        deployments,
        {}
      )
    )
  )
}
