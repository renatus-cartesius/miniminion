local Resource(type, args={}, deps=[]) = { deps: deps, type: type, } + args;

{
  apk_update:
    Resource('apk_update', {}),

  curl:
    Resource('apk_pkg', { name: 'curl' }, deps=['apk_update']),

  vim:
    Resource('apk_pkg', { name: 'vim' }, deps=['apk_update']),

  htop:
    Resource('apk_pkg', { name: 'htop' }, deps=['apk_update']),

  motd:
    Resource('file', {
      path: '/etc/motd',
      content: |||
        Welcome to Alpine Linux managed by miniminion!
        Resources applied: curl, vim, htop
      |||,
      mode: '0644',
    }, deps=['curl', 'vim', 'htop']),
}