local Resource(type, args={}, deps=[]) = {
  deps: deps,
  type: type,
} + args;

// Simple miniminion manifest for docker setup

// {
//   common_deps: Resource('package', { name: 'apt-transport-https', version: 'latest' }),
//
//   docker_pkg: Resource(
//     'package',
//     { name: 'docker-ce', version: '24.0.0' },
//     deps=['common_deps']
//   ),
//
//   docker_config: Resource(
//     'file',
//     {
//       path: '/etc/docker/daemon.json',
//       content: '{"log-driver": "json-file", "log-opts": {"max-size": "10m"}}',
//     },
//     deps=['docker_pkg']
//   ),
//
//   docker_compose: Resource(
//     'package',
//     { name: 'docker-compose-plugin' },
//     deps=['docker_config', 'docker_pkg']
//   ),
// }
// +
local fileMode(mode) =
  local digits = std.stringChars(mode);
  std.foldl(function(acc, digit) acc * 8 + std.parseInt(digit), digits, 0);

{
  neovim: Resource(
    'package',
    { name: 'neovim', version: '0.9.5-6ubuntu2' },
    deps=['some_file_10']
  ),
  vim: Resource(
    'package',
    { name: 'vim-common', version: '2:9.1.0016-1ubuntu7' },
    deps=['neovim']
  ),
}
+
{
  some_file_0: Resource(
    'file',
    {
      path: './tmp/miniminion_file_0',
      content: 'hello from file 0\n',
      mode: fileMode('777'),
    },
    // deps=['docker_compose']
  ),
}
+
{
  ['some_file_' + i]: Resource(
    'file',
    {
      path: '/tmp/miniminion_file_%d' % i,
      content: 'hello from file %d\n' % i,
      mode: fileMode('777'),
    },
    deps=['some_file_%d' % (i - 1)]
  )
  for i in std.range(1, 10)

}
