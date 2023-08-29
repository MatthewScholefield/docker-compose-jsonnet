local maskFields(object, maskFields) = {
  [field]: object[field]
  for field in std.objectFields(object)
  if std.length(std.find(field, maskFields)) == 0
};

{
  usingSwarm: std.extVar('useSwarm'),  // Must be passed to jsonnet like `--ext-code useSwarm=true`
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
  labelAttributes(labels): if $.usingSwarm then { deploy: { labels: labels } } else { labels: labels },
  Deployment(services, volumes=[], networks={}): {
    services: services,
    volumes: volumes,
    networks: networks,
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
      volumes: ['%s:/volume' % volume],
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
    local filteredDeployments = [x for x in deployments if x != null];
    local volumes = std.flatMap(function(d) d.volumes, filteredDeployments);
    $.ComposeFile(
      services={
        [serviceName]: deployment.services[serviceName]
        for deployment in filteredDeployments
        for serviceName in std.objectFields(deployment.services)
      },
      volumes=std.foldl(
        function(volumeMap, deployment) (
          volumeMap + $.Volumes(deployment.volumes)
        ),
        filteredDeployments,
        {}
      ),
      networks={
        [networkName]: deployment.networks[networkName]
        for deployment in filteredDeployments
        for networkName in std.objectFields(deployment.networks)
      }
    )
  ),
  rewriteDeployment(composeFile, folderName, networks=[]): (
    std.mergePatch(
      composeFile,
      {
        services: {
          [service]: {
            [if std.objectHas(composeFile.services[service], 'build') &&
                std.objectHas(composeFile.services[service].build, 'context') then 'build']: {
              context: '%s/%s' % [folderName, composeFile.services[service].build.context],
            },
            [if std.length(networks) > 0 then 'networks']: networks,
          }
          for service in std.objectFields(composeFile.services)
        },
      }
    )
  ),
  apps: {
    // Find networks with `docker network ls`
    CaddyStaticSite(url, localPath): { url: url, localPath: localPath },
    caddyDeployment(openPorts, networks, staticSites=[]): $.Deployment(
      services={
        caddy: $.Service({
          image: 'lucaslorentz/caddy-docker-proxy:2.7.1-alpine',
          volumes: [
            '/var/run/docker.sock:/var/run/docker.sock',
            'caddy-data-volume:/data',
            'caddy-config-volume:/config',
          ] + ['%s:%s' % [x.localPath, x.localPath] for x in staticSites],
          deploy: $.DeploymentConfig({
            placement: { constraints: ['node.role == manager'] },
            update_config: {
              order: 'stop-first',
              failure_action: 'rollback',
              delay: '3s',
            },
            rollback_config: {
              parallelism: 0,
              order: 'stop-first',
            },
          }),
          [if std.length(networks) > 0 then 'networks']: networks,
          environment: $.Env({
            [if std.length(networks) > 0 then 'CADDY_INGRESS_NETWORKS']: std.join(',', networks),
          }),
          restart: 'unless-stopped',
        } + $.bindOrExpose(openPorts, bindToHost=$.usingSwarm)) + (
          if std.length(staticSites) > 0 then $.labelAttributes(std.flattenArrays([
            [
              'caddy=%s' % [x.url],
              'caddy.root=* %s' % [x.localPath],
              'caddy.file_server=',
            ]
            for x in staticSites
          ])) else []
        ),
      },
      volumes=[
        'caddy-data-volume',
        'caddy-config-volume',
      ],
      networks={
        [network]: { external: true }
        for network in networks
      }
    ),
    // url can be http://localhost:1234 but 1234 needs to be added to openPorts
    caddyProxyConfig(url, containerPort): $.labelAttributes({
      caddy: url,
      'caddy.reverse_proxy': '{{upstreams %s}}' % [containerPort],
      'caddy.header': '/* { -Server }',
    }),
  },
}
