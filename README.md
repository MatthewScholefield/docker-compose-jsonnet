# Docker Compose Jsonnet

*Jsonnet library for docker-compose files compatible with both "docker compose" and Docker Swarm*

Using jsonnet to write docker-compose files is useful for DRY and to allow dynamically changing the configuration based on environments. Additionally, it is useful because the docker compose fields change slightly between regular "docker compose" and docker swarm deployments used in production.

This library makes it easier to specify a deployment while handling a few edge cases around these field differences.

## Usage

To use this library, simply clone it as a submodule and import the `.libsonnet` file in your own `jsonnet` file:

```bash
mkdir -p libs
git submodule add https://github.com/MatthewScholefield/docker-compose-jsonnet libs/docker-compose-jsonnet
```

And then, example usage of the library is as follows:

```jsonnet
local dc = import 'libs/docker-compose-jsonnet/dc.libsonnet';

{
  MyAppDeployment(fooPort=8080): dc.ComposeFile(
    services={
      'foo-backend': Service({
        image: localImage('foo-backend'),
        build: './foo-backend',  # Make sure ./foo-backend/Dockerfile exists
        ports: ['%s:8000' % fooPort],  # Assuming foo-backend internally runs on port 8000
        environment: Env({
          FOO_PORT: fooPort,
          REDIS_HOST: 'foo-redis'
        }),
      }),
      'foo-redis': Service({
        image: 'redis',
        expose: ['6379'],
        volumes: ['foo-redis-volume:/data'],
      })
    },
    volumes=['foo-volume', 'foo-redis-volume']
  )
}
```

Note that almost all fields are forwarded directly to docker-compose so the fields should all be the same. Equivalently this means in most cases you should be able to use as much or as little of this library as you would like mixing in direct docker-compose fields as much as necessary.

Finally, you can generate your docker-compose file within separate files per environment (ie. `.env.dev.jsonnet`) and render it on-the-fly with [docker-compose-plus](https://github.com/MatthewScholefield/docker-compose-plus).
