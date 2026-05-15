local Resource(type, args={}, deps=[]) = {
  deps: deps,
  type: type,
} + args;

local fileMode(mode) =
  local digits = std.stringChars(mode);
  std.foldl(function(acc, digit) acc * 8 + std.parseInt(digit), digits, 0);

// Simple miniminion manifest for docker setup
{
  common_deps: Resource('package', { name: 'apt-transport-https' }),

  docker_pkg: Resource(
    'package',
    { name: 'docker-io', version: '29.1.3-0ubuntu3~24.04.1' },
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
    { name: 'docker-compose-v2' },
    deps=['docker_config', 'docker_pkg']
  ),
}
