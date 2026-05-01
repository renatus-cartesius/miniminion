local Resource(type, name, args={}, deps=[]) = {
  deps: deps,
  type: type,
  name: name,
} + args;


{
  config_file: Resource('file', 'myconfig', { path: '/etc/config', content: 'foobar' }),
  some_pkg: Resource('package', 'mypackage', { name: 'vim', version: '1.2.3' }, deps=['config_file']),
  another_pkg: Resource('package', 'mypackage', { name: 'vim', version: '1.2.3' }),
}
