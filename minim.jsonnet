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
{
  some_file_0: Resource(
    'file',
    {
      path: '/tmp/miniminion_file_0',
      content: 'hello from file 02',
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
    },
    deps=['some_file_%d' % (i - 1)]
  )
  for i in std.range(1, 5)

}
