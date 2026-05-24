local Resource(type, args={}, deps=[]) = {
  deps: deps,
  type: type,
} + args;

local fileMode(mode) =
  local digits = std.stringChars(mode);
  std.foldl(function(acc, digit) acc * 8 + std.parseInt(digit), digits, 0);

local shellExec = std.native('shellExec');
local apt_updated = shellExec('[ -f /root/apt-updated ] && echo -n updated || true');

// Simple miniminion manifest for docker setup

// Updating cache on the first time
(if apt_updated != 'updated' then {
   kernel_info: Resource(
     'shell',
     {
       command: 'apt update && touch /root/apt-updated',
     },
   ),
 } else {})

+

// Other part of state
{
  common_deps: Resource(
    'package',
    {
      name: 'apt-transport-https',
    },
    deps=(if apt_updated != 'updated' then ['kernel_info'] else [])
  ),

  docker_pkg: Resource(
    'package',
    // { name: 'docker.io', version: '29.1.3-0ubuntu3~24.04.1' },
    { name: 'docker.io' },
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
