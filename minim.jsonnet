local Resource(type, args={}, deps=[]) = {
  deps: deps,
  type: type,
} + args;

// Simple miniminion manifest for docker setup

{
  common_deps: Resource('package', { name: 'apt-transport-https', version: 'latest' }),

  docker_pkg: Resource(
    'package',
    { name: 'docker-ce', version: '24.0.0' },
    deps=['common_deps']
  ),

  docker_config: Resource(
    'file',
    {
      path: '/etc/docker/daemon.json',
      content: '{"log-driver": "json-file", "log-opts": {"max-size": "10m"}}',
    },
    deps=['docker_pkg']
  ),

  docker_compose: Resource(
    'package',
    { name: 'docker-compose-plugin' },
    deps=['docker_pkg']
  ),

}
