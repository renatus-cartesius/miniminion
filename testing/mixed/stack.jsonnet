{
  agents: {
    'ubuntu-host': { state: 'states/ubuntu_host.jsonnet', depends: [] },
    'alpine-host': { state: 'states/alpine_host.jsonnet', depends: [] },
    'fedora-host': { state: 'states/fedora_host.jsonnet', depends: [] },
  },
}