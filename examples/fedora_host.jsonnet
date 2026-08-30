local Resource(type, args={}, deps=[]) = { deps: deps, type: type, } + args;

{
  dnf_update:
    Resource('dnf_update', {}),

  git:
    Resource('dnf_pkg', { name: 'git' }, deps=['dnf_update']),

  vim:
    Resource('dnf_pkg', { name: 'vim-enhanced' }, deps=['dnf_update']),

  htop:
    Resource('dnf_pkg', { name: 'htop' }, deps=['dnf_update']),

  firewalld:
    Resource('dnf_pkg', { name: 'firewalld' }, deps=['dnf_update']),

  firewalld_service:
    Resource('service', {
      name: 'firewalld',
      state: 'started',
      enabled: true,
    }, deps=['firewalld']),

  sysctl_conf:
    Resource('sysctl', {
      name: 'net.ipv4.ip_forward',
      value: '1',
    }),

  motd:
    Resource('file', {
      path: '/etc/motd',
      content: |||
        Welcome to Fedora Linux managed by miniminion!
        Resources applied: git, vim-enhanced, htop, firewalld
        Kernel param: net.ipv4.ip_forward = 1
      |||,
      mode: '0644',
    }, deps=['git', 'vim', 'htop', 'firewalld_service', 'sysctl_conf']),
}